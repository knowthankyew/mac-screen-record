import AppKit
import Combine
import OSLog

/// A menu-bar status item that shows recording state and exposes quick
/// actions (start/stop, show window, toggle webcam, toggle clicks, quit).
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "MenuBar")
    private var statusItem: NSStatusItem?
    private weak var vm: RecordingViewModel?
    private var cancellables: Set<AnyCancellable> = []

    public override init() { super.init() }

    public func install(vm: RecordingViewModel) {
        if let existing = self.statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            self.statusItem = nil
        }
        cancellables.removeAll()
        self.vm = vm
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = idleIcon
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        self.statusItem = item

        vm.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.update(for: status) }
            .store(in: &cancellables)
    }

    private func update(for status: RecordingViewModel.Status) {
        guard let item = statusItem else { return }
        switch status {
        case .recording:
            item.button?.image = recordingIcon
            item.button?.image?.isTemplate = false
            item.button?.toolTip = "Recording in progress…"
        case .paused:
            item.button?.image = pausedIcon
            item.button?.image?.isTemplate = false
            item.button?.toolTip = "Recording paused"
        case .error(let msg):
            item.button?.image = errorIcon
            item.button?.image?.isTemplate = false
            item.button?.toolTip = "⚠️ Recording Error: \(msg)"
        default:
            item.button?.image = idleIcon
            item.button?.image?.isTemplate = true
            item.button?.toolTip = "Mac Screen Record"
        }
        item.menu = buildMenu()
    }

    // MARK: - Menu & NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populateMenu(menu)
        return menu
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if case .error(let msg) = vm?.status {
            let errorItem = NSMenuItem(
                title: "⚠️ Recording Failed: \(msg)",
                action: #selector(showWindow),
                keyEquivalent: ""
            )
            errorItem.target = self
            menu.addItem(errorItem)
            menu.addItem(.separator())
        }

        let isRecording: Bool = {
            if case .recording = vm?.status { return true }
            if case .paused = vm?.status { return true }
            return false
        }()

        let toggle = NSMenuItem(
            title: isRecording ? "Stop Recording  ⌃⌥⌘S" : "Start Recording  ⌃⌥⌘R",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let webcam = NSMenuItem(
            title: (vm?.webcamEnabled ?? false) ? "Hide Webcam Overlay" : "Show Webcam Overlay",
            action: #selector(toggleWebcam),
            keyEquivalent: ""
        )
        webcam.target = self
        menu.addItem(webcam)

        let clicks = NSMenuItem(
            title: (vm?.clickHighlightsEnabled ?? false) ? "Hide Click Highlights" : "Show Click Highlights",
            action: #selector(toggleClicks),
            keyEquivalent: ""
        )
        clicks.target = self
        menu.addItem(clicks)

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Recorder Window", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let library = NSMenuItem(title: "Reveal Recordings Folder", action: #selector(revealFolder), keyEquivalent: "")
        library.target = self
        menu.addItem(library)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Mac Screen Record", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func toggleRecording() { Task { @MainActor in await vm?.toggleRecording() } }
    @objc private func toggleWebcam()    { Task { @MainActor in await vm?.toggleWebcam() } }
    @objc private func toggleClicks()    { vm?.toggleClickHighlights() }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = vm?.recorderWindow {
            w.makeKeyAndOrderFront(nil)
            w.deminiaturize(nil)
        } else {
            NotificationCenter.default.post(name: .recorderWindowShouldBecomeKey, object: nil)
        }
    }

    @objc private func revealFolder() {
        guard let folder = vm?.library.folder else { return }
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Icons

    private var idleIcon: NSImage? {
        NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Mac Screen Record")
    }
    private var recordingIcon: NSImage? {
        let img = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        return img?.tinted(with: .systemRed)
    }
    private var pausedIcon: NSImage? {
        let img = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Recording Paused")
        return img?.tinted(with: .systemOrange)
    }
    private var errorIcon: NSImage? {
        let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Recording Error")
        return img?.tinted(with: .systemRed)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = NSImage(size: self.size)
        img.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: self.size)
        self.draw(in: rect)
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
