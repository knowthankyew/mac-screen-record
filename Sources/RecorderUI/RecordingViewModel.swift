import AppKit
import CaptureCore
import Combine
import DeviceKit
import EncoderKit
import Foundation
import OSLog
import ScreenCaptureKit

/// Single source of truth for the UI. Owns a `CaptureSession`, a
/// `DeviceManager`, and the user's current selection.
@MainActor
public final class RecordingViewModel: ObservableObject {

    public enum SourceKind: String, CaseIterable, Identifiable {
        case display = "Display"
        case window  = "Window"
        case app     = "App"
        case region  = "Region"
        public var id: String { rawValue }
    }

    public enum Status: Equatable {
        case idle
        case loadingContent
        case ready
        case recording(startedAt: Date)
        case paused(startedAt: Date, pausedAt: Date)
        case stopping
        case finished(URL)
        case error(String)
    }

    // ── Shareable content ──────────────────────────────────────────────────
    @Published public private(set) var displays: [DisplayInfo] = []
    @Published public private(set) var windows:  [WindowInfo]  = []
    @Published public private(set) var apps:     [AppInfo]     = []

    // ── User selection ─────────────────────────────────────────────────────
    @Published public var sourceKind: SourceKind = .display
    @Published public var selectedDisplayID: CGDirectDisplayID? {
        didSet { webcam.targetDisplayID = selectedDisplayID }
    }
    @Published public var selectedWindowID: CGWindowID?
    @Published public var selectedAppPID: pid_t?
    @Published public var selectedRegion: RegionSelection?
    @Published public var selectedMicID: String?
    @Published public var captureSystemAudio: Bool = true
    @Published public var captureMicrophone: Bool = false
    @Published public var codec: OutputCodec = .h264
    @Published public var fps: Int = 60
    @Published public var showsCursor: Bool = true
    @Published public var customWidth: Int?
    @Published public var customHeight: Int?

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var lastRecordingURL: URL?
    @Published public var overlayError: String? = nil

    private var outputFolder: URL
    public let devices: DeviceManager
    public let levels: AudioLevelMonitor
    public let library: RecordingsLibrary
    public let presets: PresetsStore
    public let settings: AppSettings
    public let permissions: PermissionsMonitor
    public let webcam: WebcamOverlayController
    public let clickHighlights: ClickHighlightController
    public let keystrokes: KeystrokeOverlayController
    public let hotkeys: GlobalHotkeyController
    private let session: CaptureSession
    private var settingsCancellable: AnyCancellable?
    private var presetsCancellable: AnyCancellable?
    private var permissionsCancellable: AnyCancellable?
    public weak var recorderWindow: NSWindow?
    private var salvageTask: Task<Void, Never>?

    @Published public var webcamEnabled: Bool = false
    @Published public var selectedWebcamDeviceID: String?
    @Published public var webcamCorner: WebcamCorner = .bottomRight {
        didSet { webcam.corner = webcamCorner }
    }
    @Published public var webcamSize: WebcamSize = .medium {
        didSet { webcam.size = webcamSize }
    }
    @Published public var webcamMirrored: Bool = true {
        didSet { webcam.mirrored = webcamMirrored }
    }
    @Published public var webcamBackgroundMode: WebcamBackgroundMode = .none {
        didSet { webcam.backgroundMode = webcamBackgroundMode }
    }
    @Published public var webcamBlurStrength: WebcamBlurStrength = .balanced {
        didSet { webcam.blurStrength = webcamBlurStrength }
    }
    @Published public var webcamBackgroundPreset: WebcamBackgroundPreset = .warmStudio {
        didSet { webcam.backgroundPreset = webcamBackgroundPreset }
    }
    @Published public var webcamCustomImageURL: URL? = nil {
        didSet { webcam.customImageURL = webcamCustomImageURL }
    }
    @Published public var webcamShowBorder: Bool = true {
        didSet { webcam.showBorder = webcamShowBorder }
    }
    @Published public var clickHighlightsEnabled: Bool = false
    @Published public var keystrokesEnabled: Bool = false
    public let highlightOverlaysSubject = PassthroughSubject<Void, Never>()
    @Published public var activePresetID: UUID? = nil

    private var webcamToggleTask: Task<Void, Never>?

    public var activePreset: Preset? {
        guard let id = activePresetID else { return nil }
        return presets.presets.first(where: { $0.id == id })
    }

    /// Indicates whether any current settings diverge from the currently active profile.
    public var isPresetModified: Bool {
        guard let active = activePreset else { return false }
        return active.codec != codec
            || active.fps != fps
            || active.showsCursor != showsCursor
            || active.captureSystemAudio != captureSystemAudio
            || active.captureMicrophone != captureMicrophone
            || active.customWidth != customWidth
            || active.customHeight != customHeight
            || active.sourceKindRaw != sourceKind.rawValue
            || active.webcamEnabled != webcamEnabled
            || active.clickHighlightsEnabled != clickHighlightsEnabled
            || active.keystrokesEnabled != keystrokesEnabled
            || (active.webcamCorner != nil && active.webcamCorner != webcamCorner)
            || (active.webcamSize != nil && active.webcamSize != webcamSize)
            || (active.webcamBackgroundMode != nil && active.webcamBackgroundMode != webcamBackgroundMode)
    }

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "ViewModel")
    private let bundleID: String

    public init(bundleID: String = "com.macscreenrecord.app", settings: AppSettings? = nil) {
        self.bundleID = bundleID
        let settings = settings ?? AppSettings.shared
        self.settings = settings
        self.devices = DeviceManager()
        let levels = AudioLevelMonitor()
        self.levels = levels
        self.session = CaptureSession(ourBundleID: bundleID, levels: levels)

        self.outputFolder = settings.outputFolder
        self.library = RecordingsLibrary(folder: settings.outputFolder)
        self.presets = PresetsStore()
        self.permissions = PermissionsMonitor()
        self.webcam = WebcamOverlayController()
        self.clickHighlights = ClickHighlightController()
        self.keystrokes = KeystrokeOverlayController()
        self.hotkeys = GlobalHotkeyController()

        // Apply settings defaults to the working state.
        self.codec = settings.defaultCodec
        self.fps = settings.defaultFPS
        self.showsCursor = settings.defaultShowsCursor
        self.captureSystemAudio = settings.defaultCaptureSystemAudio

        // If a default startup profile is configured, apply its settings to the working state on launch.
        if let defaultP = presets.defaultPreset {
            self.activePresetID = defaultP.id
            if let kind = SourceKind(rawValue: defaultP.sourceKindRaw) { self.sourceKind = kind }
            self.codec = defaultP.codec
            self.fps = defaultP.fps
            self.showsCursor = defaultP.showsCursor
            self.captureSystemAudio = defaultP.captureSystemAudio
            self.captureMicrophone = defaultP.captureMicrophone
            self.customWidth = defaultP.customWidth
            self.customHeight = defaultP.customHeight

            if let corner = defaultP.webcamCorner {
                self.webcamCorner = corner
            }
            if let size = defaultP.webcamSize {
                self.webcamSize = size
            }
            if let mode = defaultP.webcamBackgroundMode {
                self.webcamBackgroundMode = mode
            }
            // Note: overlay activation (webcam, click highlights, keystrokes) is safely deferred
            // to applyStartupDefaultOverlays(), called when the view appears.
        }

        // didSet observers do not fire during init; sync the overlay controller explicitly.
        webcam.corner = webcamCorner
        webcam.size = webcamSize
        webcam.mirrored = webcamMirrored
        webcam.backgroundMode = webcamBackgroundMode
        webcam.blurStrength = webcamBlurStrength
        webcam.backgroundPreset = webcamBackgroundPreset
        webcam.showBorder = webcamShowBorder

        // Reload library if the user changes the output folder.
        self.settingsCancellable = settings.$outputFolder
            .dropFirst()
            .sink { [weak self] url in
                self?.outputFolder = url
                self?.library.relocate(to: url)
            }

        // Forward preset store changes so observers of ViewModel are notified immediately.
        self.presetsCancellable = presets.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        // Auto-load available screens when permission is granted without requiring app relaunch
        self.permissionsCancellable = permissions.$hasScreenRecording
            .dropFirst()
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.loadAvailableContent()
                }
            }

        // Wire mid-session failure handler for immediate detection and aggressive warning
        self.session.onFailure = { [weak self] errorMessage in
            Task { @MainActor in
                self?.handleRecordingFailure(errorMessage)
            }
        }
    }

    /// Install global hotkeys after the app is ready. Called from App.
    public func installGlobalHotkeys() {
        hotkeys.install(
            start: { [weak self] in Task { @MainActor in
                guard let self else { return }
                switch self.status {
                case .recording, .paused, .stopping: return
                default: await self.startRecording()
                }
            }},
            stop: { [weak self] in Task { @MainActor in
                guard let self else { return }
                switch self.status {
                case .recording, .paused: await self.stopRecording()
                default: break
                }
            }}
        )
    }

    public func toggleWebcam() async {
        if webcamEnabled {
            webcam.hide()
            webcamEnabled = false
            return
        }
        guard let id = selectedWebcamDeviceID ?? devices.cameras.first?.id else {
            let msg = "No camera available."
            self.overlayError = msg
            if case .recording = status {} else if case .paused = status {} else {
                status = .error(msg)
            }
            return
        }
        do {
            try webcam.show(deviceID: id)
            selectedWebcamDeviceID = id
            webcamEnabled = true
        } catch {
            let msg = "Couldn't start webcam: \(error.localizedDescription)"
            self.overlayError = msg
            if case .recording = status {} else if case .paused = status {} else {
                status = .error(msg)
            }
        }
    }

    public func pickWebcamCustomImage() {
        guard let url = webcam.pickCustomImage() else { return }
        self.webcamCustomImageURL = url
        self.webcamBackgroundMode = .customImage
    }

    public func clearWebcamCustomImage() {
        self.webcamCustomImageURL = nil
        if webcamBackgroundMode == .customImage {
            self.webcamBackgroundMode = .preset
        }
    }

    public func toggleClickHighlights() {
        if clickHighlightsEnabled {
            clickHighlights.hide()
            clickHighlightsEnabled = false
        } else {
            clickHighlights.show()
            clickHighlightsEnabled = true
        }
    }

    public func toggleKeystrokes() {
        if keystrokesEnabled {
            keystrokes.hide()
            keystrokesEnabled = false
        } else {
            keystrokes.show()
            keystrokesEnabled = true
        }
    }

    // MARK: - Presets & Facecam Workflow

    /// Safely activates startup default overlay features (such as webcam PiP) after the view has appeared,
    /// avoiding races with AVCaptureVideoPreviewLayer or window creation.
    public func applyStartupDefaultOverlays() async {
        guard let defaultP = presets.defaultPreset else { return }
        if defaultP.clickHighlightsEnabled && !clickHighlightsEnabled {
            toggleClickHighlights()
        }
        if defaultP.keystrokesEnabled && !keystrokesEnabled {
            toggleKeystrokes()
        }
        if defaultP.webcamEnabled && !webcamEnabled {
            await toggleWebcam()
        }
    }

    /// Capture the current settings into a new preset.
    public func snapshotPreset(id: UUID = UUID(), named name: String, useForFacecam: Bool = false) -> Preset {
        Preset(
            id: id,
            name: name,
            sourceKindRaw: sourceKind.rawValue,
            codec: codec,
            fps: fps,
            showsCursor: showsCursor,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone,
            customWidth: customWidth,
            customHeight: customHeight,
            webcamEnabled: webcamEnabled,
            useForFacecam: useForFacecam,
            clickHighlightsEnabled: clickHighlightsEnabled,
            keystrokesEnabled: keystrokesEnabled,
            webcamCorner: webcamCorner,
            webcamSize: webcamSize,
            webcamBackgroundMode: webcamBackgroundMode
        )
    }

    /// Generates a deduplicated profile name with an auto-incrementing suffix if a collision exists.
    public func uniquePresetName(from baseName: String, excludingID: UUID? = nil) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Preset 1" }
        let existingNames = Set(presets.presets.filter { $0.id != excludingID }.map { $0.name.lowercased() })
        if !existingNames.contains(trimmed.lowercased()) {
            return trimmed
        }
        var counter = 2
        while existingNames.contains("\(trimmed) (\(counter))".lowercased()) {
            counter += 1
        }
        return "\(trimmed) (\(counter))"
    }

    public func saveCurrentAsPreset(named name: String, useForFacecam: Bool = false, setAsStartupDefault: Bool = false) {
        let finalName = uniquePresetName(from: name)
        let preset = snapshotPreset(named: finalName, useForFacecam: useForFacecam)
        presets.add(preset)
        self.activePresetID = preset.id
        if setAsStartupDefault {
            presets.setDefault(id: preset.id)
        }
    }

    public func updateActivePreset() {
        guard let active = activePreset else { return }
        let updated = snapshotPreset(id: active.id, named: active.name, useForFacecam: active.useForFacecam)
        presets.update(updated)
    }

    public func setDefaultPreset(id: UUID?) {
        presets.setDefault(id: id)
    }

    public func setAsFacecamPreset(id: UUID) {
        presets.setAsFacecam(id: id)
    }

    public func deletePreset(id: UUID) {
        if activePresetID == id {
            activePresetID = nil
        }
        presets.delete(id: id)
    }

    public func apply(_ preset: Preset) {
        self.activePresetID = preset.id
        if let kind = SourceKind(rawValue: preset.sourceKindRaw) { sourceKind = kind }
        codec = preset.codec
        fps = preset.fps
        showsCursor = preset.showsCursor
        captureSystemAudio = preset.captureSystemAudio
        captureMicrophone = preset.captureMicrophone
        customWidth = preset.customWidth
        customHeight = preset.customHeight

        // Apply overlay configuration using typed enums
        if let corner = preset.webcamCorner {
            self.webcamCorner = corner
        }
        if let size = preset.webcamSize {
            self.webcamSize = size
        }
        if let mode = preset.webcamBackgroundMode {
            self.webcamBackgroundMode = mode
        }

        if preset.clickHighlightsEnabled != clickHighlightsEnabled {
            toggleClickHighlights()
        }
        if preset.keystrokesEnabled != keystrokesEnabled {
            toggleKeystrokes()
        }
        if preset.webcamEnabled != webcamEnabled {
            webcamToggleTask?.cancel()
            webcamToggleTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await self.toggleWebcam()
            }
        }
    }

    /// Handles clicking the quick Facecam toggle in the upper right.
    /// Follows intelligent profile resolution:
    /// 1. If Facecam is already running, toggle it off.
    /// 2. If a profile is marked "use for facecam", apply it.
    /// 3. If exactly one profile with PIP exists, mark it as Facecam and apply it.
    /// 4. If multiple profiles exist with PIP, prefer active preset if it has PIP, otherwise use the first one.
    /// 5. If no configured profile with PIP exists, turn on PIP in current context and highlight overlays section.
    public func triggerFacecamToggleAction() {
        if webcamEnabled {
            webcamToggleTask?.cancel()
            webcamToggleTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await self.toggleWebcam()
            }
            return
        }

        // 1. If a Facecam profile is explicitly designated, apply it
        if let facecam = presets.facecamPreset {
            apply(facecam)
            if !webcamEnabled {
                webcamToggleTask?.cancel()
                webcamToggleTask = Task { @MainActor [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    await self.toggleWebcam()
                }
            }
            return
        }

        let pipPresets = presets.presetsWithPIP

        // 2. If exactly one profile with PIP exists, auto-check it and apply
        if pipPresets.count == 1, let single = pipPresets.first {
            presets.setAsFacecam(id: single.id)
            apply(single)
            if !webcamEnabled {
                webcamToggleTask?.cancel()
                webcamToggleTask = Task { @MainActor [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    await self.toggleWebcam()
                }
            }
            return
        }

        // 3. If multiple exist with PIP, prefer active preset if it has PIP, else pick first
        if !pipPresets.isEmpty {
            let chosen: Preset
            if let active = activePreset, active.webcamEnabled {
                chosen = active
            } else {
                chosen = pipPresets[0]
            }
            presets.setAsFacecam(id: chosen.id)
            apply(chosen)
            if !webcamEnabled {
                webcamToggleTask?.cancel()
                webcamToggleTask = Task { @MainActor [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    await self.toggleWebcam()
                }
            }
            return
        }

        // 4. No configured profile with PIP checked:
        // Turn that checkbox on in present context and draw user's attention to the config
        webcamToggleTask?.cancel()
        webcamToggleTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.toggleWebcam()
        }
        highlightOverlaysSubject.send()
    }

    // MARK: - Loading

    public func loadAvailableContent() async {
        status = .loadingContent
        permissions.refresh()
        devices.refresh()

        // If screen recording permission is not yet granted, PermissionsBanner handles
        // guiding the user. Avoid setting .error to prevent duplicate alarming red banners.
        guard permissions.hasScreenRecording else {
            log.info("Screen recording permission not granted yet. Waiting for authorization.")
            status = .idle
            return
        }

        do {
            let content = try await ShareableContentLoader.load(excludingBundleID: bundleID)
            self.displays = content.displays
            self.windows  = content.windows
            self.apps     = content.apps
            if selectedDisplayID == nil { selectedDisplayID = displays.first?.id }
            status = .ready
        } catch {
            log.error("Could not load shareable content: \(error.localizedDescription, privacy: .public)")
            status = .error("Couldn't enumerate screens: \(error.localizedDescription)")
        }
    }

    public func dismissError() {
        if case .error = status {
            status = displays.isEmpty ? .idle : .ready
        }
    }

    // MARK: - Recording

    public func toggleRecording() async {
        switch status {
        case .recording, .paused: await stopRecording()
        default:                  await startRecording()
        }
    }

    public func togglePause() {
        switch status {
        case .recording(let started):
            session.pause()
            status = .paused(startedAt: started, pausedAt: Date())
        case .paused(let started, let pausedAt):
            session.resume()
            let pauseDuration = Date().timeIntervalSince(pausedAt)
            status = .recording(startedAt: started.addingTimeInterval(pauseDuration))
        default:
            break
        }
    }

    public func startRecording() async {
        guard status != .stopping else { return }
        // Friendly preflight: surface the most common reason recording fails.
        permissions.refresh()
        guard permissions.hasScreenRecording else {
            permissions.requestScreenRecordingPrompt()
            status = .error("Screen Recording permission is missing. Grant it in System Settings, then quit & relaunch.")
            return
        }
        guard let source = currentSource() else {
            status = .error("Pick a source to record first.")
            return
        }
        let geometry = currentGeometry(for: source)
        let url = freshOutputURL()

        var settings = RecordingSettings(
            width: geometry.outputWidth,
            height: geometry.outputHeight,
            fps: geometry.fps,
            codec: codec,
            captureMicrophone: captureMicrophone && selectedMicID != nil,
            captureSystemAudio: captureSystemAudio,
            microphoneDeviceID: captureMicrophone ? selectedMicID : nil,
            outputURL: url
        )
        settings.codec = codec

        // Collect window IDs of our overlay windows so they appear in the
        // recording (display/region modes only — see CaptureSession.buildFilter).
        var exceptions: [CGWindowID] = []
        if webcamEnabled, let id = webcam.windowID { exceptions.append(id) }
        if clickHighlightsEnabled { exceptions.append(contentsOf: clickHighlights.windowIDs) }
        if keystrokesEnabled, let id = keystrokes.windowID { exceptions.append(id) }

        do {
            try await session.start(
                source: source,
                geometry: geometry,
                settings: settings,
                exceptingWindowIDs: exceptions
            )
            self.lastRecordingURL = url
            status = .recording(startedAt: Date())
        } catch let captureError as CaptureSession.CaptureError {
            status = .error(captureError.errorDescription ?? "Recording failed.")
        } catch {
            // Surface the underlying NSError message — this is usually the most
            // informative thing (e.g. SCK's TCC error string).
            let ns = error as NSError
            let detail = ns.localizedFailureReason ?? ns.localizedDescription
            status = .error("Recording failed: \(detail)")
        }
    }

    public func stopRecording() async {
        status = .stopping
        do {
            let url = try await session.stop()
            self.lastRecordingURL = url
            status = .finished(url)
            await library.reload()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    @MainActor
    private func handleRecordingFailure(_ message: String) {
        // De-duplicate: ignore if we are not recording/paused or already salvaging
        switch status {
        case .recording, .paused:
            break
        default:
            return
        }
        guard salvageTask == nil else { return }

        log.error("Active recording interrupted: \(message, privacy: .public)")

        // 1. Mark status as stopping while salvage is in progress to prevent re-triggering startRecording
        status = .stopping

        // 2. Aggressive user alert: system alert sound
        NSSound.beep()

        // 3. Request user attention: Dock icon bounces continuously until activated
        NSApp.requestUserAttention(.criticalRequest)

        // 4. Force-activate the app and bring recorder window to front
        NSApp.activate(ignoringOtherApps: true)
        if let window = recorderWindow {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
        } else {
            NotificationCenter.default.post(name: .recorderWindowShouldBecomeKey, object: nil)
        }

        // 5. Attempt auto-salvage of the partial recording so frames recorded up to failure aren't lost
        salvageTask = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.salvageTask = nil } }
            do {
                let savedURL = try await self.session.stop()
                self.lastRecordingURL = savedURL
                self.log.info("Salvaged partial recording: \(savedURL.lastPathComponent, privacy: .public)")
                self.status = .error("⚠️ Recording failed: \(message). Partial video saved as \(savedURL.lastPathComponent).")
                await self.library.reload()
            } catch {
                self.log.error("Auto-salvage failed: \(error.localizedDescription, privacy: .public)")
                self.status = .error("⚠️ Recording interrupted: \(message). Partial file could not be saved.")
            }
        }
    }

    public func revealLastRecording() {
        if case .finished(let url) = status {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let url = lastRecordingURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let latest = library.files.first {
            NSWorkspace.shared.activateFileViewerSelecting([latest.url])
        }
    }

    /// Deletes all artifacts (primary file + any matching temporary/partial fragments) associated with the last recording.
    public func deleteLastRecordingArtifacts(moveToTrash: Bool = true) {
        guard let url = lastRecordingURL else { return }
        library.deleteArtifacts(at: url, moveToTrash: moveToTrash)
        self.lastRecordingURL = nil
        switch status {
        case .finished, .error:
            status = .ready
        default:
            break
        }
    }

    /// Present the region-selection overlay. The host app window stays open;
    /// it just gets covered by the translucent panel until the user finishes.
    public func pickRegion() async {
        let selector = RegionSelector()
        if let pick = await selector.present() {
            selectedRegion = pick
            sourceKind = .region
        }
    }

    // MARK: - Helpers

    private func currentSource() -> CaptureSource? {
        switch sourceKind {
        case .display:
            guard let id = selectedDisplayID else { return nil }
            return .display(id: id, region: nil)
        case .window:
            guard let id = selectedWindowID else { return nil }
            return .window(id: id)
        case .app:
            guard let pid = selectedAppPID,
                  let displayID = selectedDisplayID ?? displays.first?.id
            else { return nil }
            return .application(pid: pid, displayID: displayID)
        case .region:
            guard let pick = selectedRegion else { return nil }
            return .display(id: pick.displayID, region: pick.rect)
        }
    }

    private func currentGeometry(for source: CaptureSource) -> CaptureGeometry {
        let (w, h) = nativeSize(for: source)
        let outW = customWidth  ?? w
        let outH = customHeight ?? h
        return CaptureGeometry(outputWidth: outW, outputHeight: outH, fps: fps, showsCursor: showsCursor)
    }

    private func nativeSize(for source: CaptureSource) -> (Int, Int) {
        switch source {
        case .display(let id, let region):
            if let region { return (Int(region.width), Int(region.height)) }
            if let d = displays.first(where: { $0.id == id }) { return (d.width, d.height) }
            return (1920, 1080)
        case .window(let id):
            if let w = windows.first(where: { $0.id == id }) {
                return (Int(w.frame.width), Int(w.frame.height))
            }
            return (1920, 1080)
        case .application(_, let did):
            if let d = displays.first(where: { $0.id == did }) { return (d.width, d.height) }
            return (1920, 1080)
        }
    }

    private func freshOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: Date())
        return outputFolder.appendingPathComponent("Record_\(stamp).\(codec.fileExtension)")
    }
}

extension Notification.Name {
    public static let recorderWindowShouldBecomeKey = Notification.Name("recorderWindowShouldBecomeKey")
}

