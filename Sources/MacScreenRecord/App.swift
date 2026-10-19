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
                .onOpenURL { url in
                    vm.openVideoForTrimming(url: url)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video to Trim…") {
                    vm.presentOpenVideoPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(vm.isCapturing)

                Menu("Open Recent") {
                    let recents = vm.recentsStore.existingRecents
                    if recents.isEmpty {
                        Text("No Recent Recordings")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(recents, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                vm.openVideoForTrimming(url: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            vm.recentsStore.clear()
                        }
                    }
                }
                .disabled(vm.isCapturing)

                Divider()

                Button("Recordings Library…") {
                    vm.showLibrary = true
                }
                .keyboardShortcut("l", modifiers: .command)
            }
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
    private var pendingOpenURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app as a regular app *and* show a menu-bar item, so users
        // can quick-toggle from the bar without closing the main window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let vm {
            vm.openVideoForTrimming(url: url)
        } else {
            pendingOpenURL = url
        }
    }

    @MainActor
    func attach(viewModel: RecordingViewModel) {
        guard self.vm !== viewModel else { return }
        self.vm = viewModel
        menuBar.install(vm: viewModel)
        viewModel.installGlobalHotkeys()
        if let pending = pendingOpenURL {
            pendingOpenURL = nil
            viewModel.openVideoForTrimming(url: pending)
        }
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
