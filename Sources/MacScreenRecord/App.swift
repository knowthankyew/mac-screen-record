import AppKit
import RecorderUI
import SwiftUI

@main
struct MacScreenRecordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = RecordingViewModel()

    var body: some Scene {
        WindowGroup("Mac Screen Record") {
            MainView(vm: vm)
                .onAppear {
                    appDelegate.attach(viewModel: vm)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}   // hide File → New
        }

        Settings {
            SettingsView(settings: vm.settings, hotkeys: vm.hotkeys)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarController()
    private weak var vm: RecordingViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app as a regular app *and* show a menu-bar item, so users
        // can quick-toggle from the bar without closing the main window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func attach(viewModel: RecordingViewModel) {
        guard self.vm !== viewModel else { return }
        self.vm = viewModel
        menuBar.install(vm: viewModel)
        viewModel.installGlobalHotkeys()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = vm?.recorderWindow {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            } else {
                NotificationCenter.default.post(name: .recorderWindowShouldBecomeKey, object: nil)
            }
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let vm else { return .terminateNow }
        switch vm.status {
        case .recording, .paused:
            Task { @MainActor in
                await vm.stopRecording()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .stopping:
            Task { @MainActor in
                while case .stopping = vm.status {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        default:
            return .terminateNow
        }
    }
}
