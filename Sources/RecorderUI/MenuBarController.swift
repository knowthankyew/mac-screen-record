import AppKit
import Combine
import OSLog

/// A transient, zero-bloat menu-bar status item that exists ONLY while recording or paused.
/// Surfaces real-time duration (`🔴 00:02:45`), first-class Pause/Resume controls,
/// direct Trim-before-save review, amnesiac Hard Burn data destruction, and live telemetry.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "MenuBar")
    private var statusItem: NSStatusItem?
    private weak var vm: RecordingViewModel?
    private var cancellables: Set<AnyCancellable> = []
    private var tickerCancellable: AnyCancellable?

    /// Exposes whether a menu bar status item is currently installed on NSStatusBar.
    public var hasStatusItem: Bool { statusItem != nil }

    /// Exposes the current status bar button title (for verification & tests).
    public var currentButtonTitle: String? { statusItem?.button?.title }

    public override init() { super.init() }

    deinit {
        // MainActor deinit cleanup
        tickerCancellable?.cancel()
    }

    /// Wires the controller to the recording view model.
    /// Does NOT create any status bar item while idle — strictly zero tray bloat.
    public func install(vm: RecordingViewModel) {
        removeStatusItem()
        cancellables.removeAll()
        self.vm = vm

        vm.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.update(for: status) }
            .store(in: &cancellables)
    }

    // MARK: - State Management & Ephemeral Lifecycle

    public func update(for status: RecordingViewModel.Status) {
        switch status {
        case .recording(let startedAt):
            ensureStatusItem()
            startTicker(startedAt: startedAt)
            updateButton(isRecording: true, startedAt: startedAt, pausedAt: nil)

        case .paused(let startedAt, let pausedAt):
            ensureStatusItem()
            stopTicker()
            updateButton(isRecording: false, startedAt: startedAt, pausedAt: pausedAt)

        default:
            stopTicker()
            removeStatusItem()
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = buildMenu()
        self.statusItem = item
    }

    public func removeStatusItem() {
        stopTicker()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            self.statusItem = nil
        }
    }

    // MARK: - Live Duration Ticker

    private func startTicker(startedAt: Date) {
        tickerCancellable?.cancel()
        tickerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateButton(isRecording: true, startedAt: startedAt, pausedAt: nil)
            }
    }

    private func stopTicker() {
        tickerCancellable?.cancel()
        tickerCancellable = nil
    }

    private func updateButton(isRecording: Bool, startedAt: Date, pausedAt: Date?) {
        guard let button = statusItem?.button else { return }
        let elapsed: Int
        if let pausedAt {
            elapsed = max(0, Int(pausedAt.timeIntervalSince(startedAt)))
        } else {
            elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        }
        let timeString = formatTime(seconds: elapsed)

        if isRecording {
            button.image = recordingIcon
            button.image?.isTemplate = false
            button.title = " \(timeString)"
            button.toolTip = "Recording in progress (\(timeString)) — Click for options"
        } else {
            button.image = pausedIcon
            button.image?.isTemplate = false
            button.title = " \(timeString) (Paused)"
            button.toolTip = "Recording paused (\(timeString)) — Click for options"
        }
    }

    public func formatTime(seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds / 60) % 60
        let secs = seconds % 60
        if hrs > 0 {
            return String(format: "%02d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
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
        guard let vm else { return }

        let isPaused: Bool
        let elapsedStr: String
        switch vm.status {
        case .recording(let startedAt):
            isPaused = false
            elapsedStr = formatTime(seconds: max(0, Int(Date().timeIntervalSince(startedAt))))
        case .paused(let startedAt, let pausedAt):
            isPaused = true
            elapsedStr = formatTime(seconds: max(0, Int(pausedAt.timeIntervalSince(startedAt))))
        default:
            isPaused = false
            elapsedStr = "--:--"
        }

        // 1. Live Status Header
        let statusTitle = isPaused ? "❚❚ Paused (\(elapsedStr))" : "● Recording (\(elapsedStr))"
        let headerItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(.separator())

        // 2. Pause / Resume Controls
        let pauseTitle = isPaused ? "Resume Recording  ⌥Space" : "Pause Recording  ⌥Space"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        // 3. Termination Actions
        let stopItem = NSMenuItem(title: "Stop Recording  ⌃⌥⌘S", action: #selector(stopRecording), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        let trimItem = NSMenuItem(title: "Trim Before Saving…", action: #selector(stopAndTrimRecording), keyEquivalent: "")
        trimItem.target = self
        menu.addItem(trimItem)

        let burnItem = NSMenuItem(title: "Hard Burn (Discard)  ⌃⌥⌘⌫", action: #selector(burnRecording), keyEquivalent: "")
        burnItem.target = self
        menu.addItem(burnItem)

        menu.addItem(.separator())

        // 4. Capture Telemetry Section
        let micInfo: String
        if vm.captureMicrophone, let micID = vm.selectedMicID, let mic = vm.devices.microphones.first(where: { $0.id == micID }) {
            micInfo = "🎤 Mic: \(mic.localizedName) (Active)"
        } else if vm.captureMicrophone {
            micInfo = "🎤 Mic: Active"
        } else {
            micInfo = "🎤 Mic: Disabled"
        }
        let micItem = NSMenuItem(title: micInfo, action: nil, keyEquivalent: "")
        micItem.isEnabled = false
        menu.addItem(micItem)

        let sysAudioInfo = "🔊 System Audio: \(vm.captureSystemAudio ? "Capturing" : "Off")"
        let sysAudioItem = NSMenuItem(title: sysAudioInfo, action: nil, keyEquivalent: "")
        sysAudioItem.isEnabled = false
        menu.addItem(sysAudioItem)

        let targetInfo: String
        switch vm.sourceKind {
        case .display:
            if let disp = vm.displays.first(where: { $0.id == vm.selectedDisplayID }) {
                targetInfo = "🖥 Target: Display (\(disp.width)×\(disp.height))"
            } else {
                targetInfo = "🖥 Target: Main Display"
            }
        case .window:
            if let win = vm.windows.first(where: { $0.id == vm.selectedWindowID }) {
                targetInfo = "🪟 Target: \(win.title.isEmpty ? win.appName : win.title)"
            } else {
                targetInfo = "🪟 Target: Selected Window"
            }
        case .app:
            if let app = vm.apps.first(where: { $0.id == vm.selectedAppPID }) {
                targetInfo = "📱 Target: \(app.applicationName)"
            } else {
                targetInfo = "📱 Target: Application"
            }
        case .region:
            targetInfo = "📐 Target: Custom Region"
        }
        let targetItem = NSMenuItem(title: targetInfo, action: nil, keyEquivalent: "")
        targetItem.isEnabled = false
        menu.addItem(targetItem)

        menu.addItem(.separator())

        // 5. In-Flight Overlay Toggles
        let webcamTitle = vm.webcamEnabled ? "Hide Facecam (PiP)  ⌃⌥P" : "Show Facecam (PiP)  ⌃⌥P"
        let webcamItem = NSMenuItem(title: webcamTitle, action: #selector(toggleWebcam), keyEquivalent: "")
        webcamItem.target = self
        menu.addItem(webcamItem)

        let keystrokesTitle = vm.keystrokesEnabled ? "Hide Keystroke Overlay  ⌃⌥K" : "Show Keystroke Overlay  ⌃⌥K"
        let keystrokesItem = NSMenuItem(title: keystrokesTitle, action: #selector(toggleKeystrokes), keyEquivalent: "")
        keystrokesItem.target = self
        menu.addItem(keystrokesItem)

        let clicksTitle = vm.clickHighlightsEnabled ? "Hide Click Highlights" : "Show Click Highlights"
        let clicksItem = NSMenuItem(title: clicksTitle, action: #selector(toggleClicks), keyEquivalent: "")
        clicksItem.target = self
        menu.addItem(clicksItem)

        menu.addItem(.separator())

        // 6. Window & App Control
        let showItem = NSMenuItem(title: "Show Recorder Window", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(title: "Quit Mac Screen Record", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func togglePause()          { vm?.togglePause() }
    @objc private func stopRecording()        { Task { @MainActor in await vm?.stopRecording() } }
    @objc private func stopAndTrimRecording() { Task { @MainActor in await vm?.stopRecording(forceTrimReview: true) } }
    @objc private func burnRecording()        { Task { @MainActor in await vm?.burnRecording() } }
    @objc private func toggleWebcam()         { Task { @MainActor in await vm?.toggleWebcam() } }
    @objc private func toggleKeystrokes()     { vm?.toggleKeystrokes() }
    @objc private func toggleClicks()         { vm?.toggleClickHighlights() }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = vm?.recorderWindow {
            w.deminiaturize(nil)
            w.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .recorderWindowShouldBecomeKey, object: nil)
        }
    }

    // MARK: - Icons

    private var recordingIcon: NSImage? {
        let img = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        return img?.tinted(with: .systemRed)
    }
    private var pausedIcon: NSImage? {
        let img = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Recording Paused")
        return img?.tinted(with: .systemOrange)
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
