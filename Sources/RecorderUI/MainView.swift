import AppKit
import CaptureCore
import DeviceKit
import EncoderKit
import SwiftUI

public struct MainView: View {
    @ObservedObject private var vm: RecordingViewModel
    @State private var showDeleteArtifactsSheet = false
    @State private var moveToTrash = true
    @State private var highlightOverlays = false

    public init(vm: RecordingViewModel) {
        self.vm = vm
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PermissionsBanner(monitor: vm.permissions)
            errorBanner
            PresetsBar(vm: vm)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sourceSection
                        audioSection
                        overlaysSection
                            .id("overlaysSection")
                        outputSection
                    }
                    .padding(20)
                }
                .onReceive(vm.highlightOverlaysSubject) { _ in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("overlaysSection", anchor: .center)
                        highlightOverlays = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            highlightOverlays = false
                        }
                    }
                }
            }
            Divider()
            controlBar
        }
        .frame(minWidth: 560, minHeight: 640)
        .background(WindowAccessor { [weak vm] window in
            vm?.recorderWindow = window
        })
        .onReceive(NotificationCenter.default.publisher(for: .recorderWindowShouldBecomeKey)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            vm.recorderWindow?.makeKeyAndOrderFront(nil)
            vm.recorderWindow?.deminiaturize(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.recentsStore.refresh()
            vm.library.pruneMissingFiles()
        }
        .task {
            await vm.loadAvailableContent()
            await vm.applyStartupDefaultOverlays()
        }
        .sheet(isPresented: $vm.showLibrary) {
            RecordingsListView(library: vm.library, settings: vm.settings, recentsStore: vm.recentsStore)
        }
        .sheet(isPresented: $showDeleteArtifactsSheet) {
            deleteArtifactsSheet
        }
        .sheet(item: $vm.activeTrimTarget) { target in
            VideoTrimModalView(
                target: target,
                library: vm.library,
                settings: vm.settings,
                onTrimSaved: { savedURL in
                    vm.updateFinishedRecording(savedURL)
                },
                onDiscard: {
                    vm.discardReviewedRecording(at: target.url)
                }
            )
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        switch vm.status {
        case .interrupted(let message, let partialURL):
            bannerCard(
                isInterruption: true,
                message: message,
                canReveal: partialURL != nil,
                canDeleteArtifacts: partialURL != nil
            )
        case .error(let message) where vm.permissions.hasScreenRecording:
            bannerCard(
                isInterruption: false,
                message: message,
                canReveal: false,
                canDeleteArtifacts: false
            )
        default:
            EmptyView()
        }
    }

    private func bannerCard(
        isInterruption: Bool,
        message: String,
        canReveal: Bool,
        canDeleteArtifacts: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isInterruption ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isInterruption ? "Recording Interrupted" : "Notice")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(spacing: 6) {
                    if canReveal {
                        Button("Show in Finder") {
                            vm.revealLastRecording()
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.35))
                    }
                    if canDeleteArtifacts {
                        Button("Delete Artifacts…") {
                            showDeleteArtifactsSheet = true
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.35))
                    }
                    Button("Dismiss") {
                        vm.dismissError()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.2))
                }
            }
        }
        .padding(14)
        .background(isInterruption ? Color.red.opacity(0.92) : Color.orange.opacity(0.92))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(isRecording ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Screen Record").font(.title2.bold())
                if case .recording(let started) = vm.status {
                    RecordingTimerView(startedAt: started)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.red)
                } else if case .paused = vm.status {
                    Text("Paused").font(.caption).foregroundStyle(.orange)
                } else if case .finished(let url) = vm.status {
                    SavedRecordingLinkView(url: url) {
                        vm.revealLastRecording()
                    }
                } else {
                    Text(statusLine).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                vm.triggerFacecamToggleAction()
            } label: {
                Image(systemName: vm.webcamEnabled ? "person.crop.square.fill" : "person.crop.square")
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(vm.webcamEnabled ? Color.accentColor : Color.secondary)
            .help(vm.webcamEnabled ? "Turn off Facecam PiP" : "Turn on Facecam PiP (uses default Facecam profile)")

            Button {
                vm.showLibrary = true
            } label: {
                Image(systemName: "film.stack")
            }
            .buttonStyle(.borderless)
            .help("Browse past recordings")
            Button {
                Task {
                    vm.devices.refresh()
                    await vm.loadAvailableContent()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh screens, windows, apps, and devices")
        }
        .padding(16)
    }

    // MARK: - Sections

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Source")
            Picker("", selection: $vm.sourceKind) {
                ForEach(RecordingViewModel.SourceKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch vm.sourceKind {
            case .display: displayPicker
            case .window:  windowPicker
            case .app:     appPicker
            case .region:  regionPicker
            }

            HStack {
                Toggle("Show cursor", isOn: $vm.showsCursor)
                Spacer()
                Stepper("FPS: \(vm.fps)", value: $vm.fps, in: 24...120, step: 1)
                    .frame(width: 160)
            }

            customResolutionRow
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Audio")
            Toggle("Capture system audio", isOn: $vm.captureSystemAudio)
            Toggle("Capture microphone", isOn: $vm.captureMicrophone)
            if vm.captureMicrophone {
                Picker("Microphone", selection: $vm.selectedMicID) {
                    Text("None").tag(String?.none)
                    ForEach(vm.devices.microphones) { mic in
                        Text(mic.localizedName).tag(String?.some(mic.id))
                    }
                }
            }
            if isRecording {
                if vm.captureSystemAudio { LevelMeterView(monitor: vm.levels, kind: .system) }
                if vm.captureMicrophone  { LevelMeterView(monitor: vm.levels, kind: .mic) }
            }
        }
    }

    private var overlaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Overlays")
                if highlightOverlays {
                    Text("• Camera, Clicks & Keystrokes Config")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity)
                }
            }

            // Webcam PiP
            HStack {
                Toggle("Webcam picture-in-picture", isOn: Binding(
                    get: { vm.webcamEnabled },
                    set: { _ in Task { await vm.toggleWebcam() } }
                ))
                Spacer()
            }
            if vm.webcamEnabled {
                Picker("Camera", selection: $vm.selectedWebcamDeviceID) {
                    ForEach(vm.devices.cameras) { c in
                        Text(c.localizedName).tag(String?.some(c.id))
                    }
                }
                .onChange(of: vm.selectedWebcamDeviceID) { newID in
                    if let id = newID { try? vm.webcam.setDevice(id) }
                }
                Picker("Position", selection: $vm.webcamCorner) {
                    ForEach(WebcamCorner.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Picker("Size", selection: $vm.webcamSize) {
                    ForEach(WebcamSize.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                Toggle("Mirror image (flip horizontally)", isOn: $vm.webcamMirrored)

                Picker("Background", selection: $vm.webcamBackgroundMode) {
                    ForEach(WebcamBackgroundMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                webcamBackgroundOptions

                Toggle("Show border ring", isOn: $vm.webcamShowBorder)
            }

            // Click highlights
            Toggle("Highlight mouse clicks", isOn: Binding(
                get: { vm.clickHighlightsEnabled },
                set: { _ in vm.toggleClickHighlights() }
            ))

            // Keystroke overlay
            Toggle("Show keystrokes", isOn: Binding(
                get: { vm.keystrokesEnabled },
                set: { _ in vm.toggleKeystrokes() }
            ))

            Text("Overlays appear in display + region recordings. Keystrokes need Input Monitoring permission to capture keys typed in other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(highlightOverlays ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlightOverlays ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(highlightOverlays ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.3), value: highlightOverlays)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Output")
            Picker("Codec", selection: $vm.codec) {
                ForEach(OutputCodec.allCases) { c in
                    Text(c.displayName).tag(c)
                }
            }
            Text("Saved to \((vm.settings.outputFolder.path as NSString).abbreviatingWithTildeInPath)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var webcamBackgroundOptions: some View {
        switch vm.webcamBackgroundMode {
        case .none, .cutout:
            EmptyView()
        case .blur:
            Picker("Blur strength", selection: $vm.webcamBlurStrength) {
                ForEach(WebcamBlurStrength.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
        case .preset:
            Picker("Virtual backdrop", selection: $vm.webcamBackgroundPreset) {
                ForEach(WebcamBackgroundPreset.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
        case .customImage:
            HStack(spacing: 8) {
                Text("Custom image")
                Spacer()
                if let url = vm.webcamCustomImageURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Change…") { vm.pickWebcamCustomImage() }
                        .controlSize(.small)
                    Button("Clear") { vm.clearWebcamCustomImage() }
                        .controlSize(.small)
                } else {
                    Button("Choose Image…") { vm.pickWebcamCustomImage() }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Pickers

    private var displayPicker: some View {
        Picker("Display", selection: $vm.selectedDisplayID) {
            ForEach(vm.displays) { d in
                Text(d.displayName).tag(CGDirectDisplayID?.some(d.id))
            }
        }
    }

    private var windowPicker: some View {
        Picker("Window", selection: $vm.selectedWindowID) {
            Text("Pick a window…").tag(CGWindowID?.none)
            ForEach(vm.windows) { w in
                Text(w.displayName).tag(CGWindowID?.some(w.id))
            }
        }
    }

    private var appPicker: some View {
        Picker("Application", selection: $vm.selectedAppPID) {
            Text("Pick an app…").tag(pid_t?.none)
            ForEach(vm.apps) { a in
                Text(a.displayName).tag(pid_t?.some(a.id))
            }
        }
    }

    private var regionPicker: some View {
        HStack(spacing: 12) {
            if let r = vm.selectedRegion {
                Label(
                    "\(Int(r.rect.width)) × \(Int(r.rect.height)) on display \(r.displayID)",
                    systemImage: "rectangle.dashed"
                )
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
            } else {
                Text("No region picked yet")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Select Region…") {
                Task { await vm.pickRegion() }
            }
        }
    }

    private var customResolutionRow: some View {
        HStack(spacing: 12) {
            Toggle("Custom output size", isOn: Binding(
                get: { vm.customWidth != nil },
                set: { on in
                    if on {
                        vm.customWidth  = vm.customWidth  ?? 1920
                        vm.customHeight = vm.customHeight ?? 1080
                    } else {
                        vm.customWidth = nil
                        vm.customHeight = nil
                    }
                }
            ))
            if vm.customWidth != nil {
                TextField("W", value: Binding($vm.customWidth, replacingNilWith: 1920), format: .number)
                    .frame(width: 70).textFieldStyle(.roundedBorder)
                Text("×")
                TextField("H", value: Binding($vm.customHeight, replacingNilWith: 1080), format: .number)
                    .frame(width: 70).textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            if case .finished(_) = vm.status {
                Button("Show in Finder") { vm.revealLastRecording() }
                if let url = vm.lastRecordingURL, LosslessTrimmer.isSupported(url: url) {
                    Button {
                        vm.trimLastRecording()
                    } label: {
                        Label("Trim…", systemImage: "scissors")
                    }
                    .buttonStyle(.bordered)
                }
                if vm.lastRecordingURL != nil {
                    Button("Delete Artifacts…") {
                        showDeleteArtifactsSheet = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isActive {
                Button {
                    vm.togglePause()
                } label: {
                    Label(isPaused ? "Resume" : "Pause",
                          systemImage: isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.headline)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
            Button {
                Task { await vm.toggleRecording() }
            } label: {
                Label(isActive ? "Stop Recording" : "Start Recording",
                      systemImage: isActive ? "stop.circle.fill" : "record.circle.fill")
                    .font(.headline)
                    .frame(minWidth: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(isActive ? .red : .accentColor)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var isRecording: Bool {
        if case .recording = vm.status { return true }
        return false
    }

    private var isPaused: Bool {
        if case .paused = vm.status { return true }
        return false
    }

    private var isActive: Bool { isRecording || isPaused }

    private var statusLine: String {
        switch vm.status {
        case .idle:                       return "Idle"
        case .loadingContent:             return "Loading available screens…"
        case .ready:                      return "Ready"
        case .recording(let started):
            let secs = Int(Date().timeIntervalSince(started))
            return String(format: "Recording — %02d:%02d", secs / 60, secs % 60)
        case .paused:                     return "Paused"
        case .stopping:                   return "Stopping…"
        case .finished(let url):          return "Saved \(url.lastPathComponent)"
        case .interrupted(let message, _): return message
        case .error(let message):         return message
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.headline).foregroundStyle(.secondary)
    }

    private var deleteArtifactsTargetURL: URL? {
        if case .interrupted(_, let partialURL) = vm.status {
            return partialURL
        }
        return vm.lastRecordingURL
    }

    private var deleteArtifactsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete Recording Artifacts").font(.headline)
                    if let url = deleteArtifactsTargetURL {
                        Text(url.lastPathComponent)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Move files to Trash", isOn: $moveToTrash)
                    .font(.body)
                Text(moveToTrash
                     ? "Files will be moved to the macOS Trash and can be restored if needed."
                     : "Files will be permanently deleted from disk immediately. This cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(moveToTrash ? Color.secondary : Color.red)
            }
            .padding(.vertical, 4)

            HStack {
                Spacer()
                Button("Cancel") {
                    showDeleteArtifactsSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(moveToTrash ? "Move to Trash" : "Permanently Delete", role: .destructive) {
                    vm.deleteLastRecordingArtifacts(moveToTrash: moveToTrash)
                    showDeleteArtifactsSheet = false
                }
                .keyboardShortcut(moveToTrash ? .defaultAction : nil)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            moveToTrash = true
        }
    }
}

// Convenience: bind an optional value through a TextField using a fallback default.
private extension Binding where Value == Int? {
    init(_ source: Binding<Int?>, replacingNilWith fallback: Int) {
        self.init(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0 }
        )
    }
}

private final class WindowAccessorView: NSView {
    var callback: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        callback?(window)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.callback = callback
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.callback = callback
    }
}

/// An interactive green link representing a newly completed or trimmed recording,
/// featuring an animated "capture click" style circular ripple callout that draws attention
/// to the saved artifact when it is first added to the window.
public struct SavedRecordingLinkView: View {
    public let url: URL
    public let onReveal: () -> Void

    @State private var isHovered = false
    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 0.0
    @State private var secondRippleScale: CGFloat = 0.4
    @State private var secondRippleOpacity: Double = 0.0
    @State private var glowOpacity: Double = 0.0

    public init(url: URL, onReveal: @escaping () -> Void) {
        self.url = url
        self.onReveal = onReveal
    }

    public var body: some View {
        Button {
            triggerCalloutAnimation()
            onReveal()
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    // Secondary echoing ripple ring
                    Circle()
                        .stroke(Color.green.opacity(0.65), lineWidth: 2)
                        .background(Circle().fill(Color.green.opacity(0.18)))
                        .frame(width: 16, height: 16)
                        .scaleEffect(secondRippleScale)
                        .opacity(secondRippleOpacity)

                    // Primary "capture click" ripple ring (0.5x -> 2.4x scale expansion with ease-out fade)
                    Circle()
                        .stroke(Color.green.opacity(0.9), lineWidth: 2.5)
                        .background(Circle().fill(Color.green.opacity(0.35)))
                        .frame(width: 16, height: 16)
                        .scaleEffect(rippleScale)
                        .opacity(rippleOpacity)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                }
                .frame(width: 18, height: 18)

                Text(url.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .underline(isHovered, color: .green)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320, alignment: .leading)

                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.85))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(isHovered ? 0.15 : glowOpacity))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered {
                NSCursor.pop()
                isHovered = false
            }
        }
        .help("Saved to \(url.path)\nClick to reveal in Finder")
        .accessibilityLabel("Saved recording: \(url.lastPathComponent), click to reveal in Finder")
        .onAppear {
            triggerCalloutAnimation()
        }
        .onChange(of: url) { _ in
            triggerCalloutAnimation()
        }
    }

    private func triggerCalloutAnimation() {
        // Reset to initial compact state
        rippleScale = 0.5
        rippleOpacity = 1.0
        secondRippleScale = 0.4
        secondRippleOpacity = 0.0
        glowOpacity = 0.30

        // Primary ripple explosion (mirroring ClickHighlightOverlay)
        withAnimation(.easeOut(duration: 0.6)) {
            rippleScale = 2.4
            rippleOpacity = 0.0
        }

        // Secondary echoing ripple
        withAnimation(.easeOut(duration: 0.65).delay(0.12)) {
            secondRippleScale = 2.0
            secondRippleOpacity = 0.75
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.28)) {
            secondRippleOpacity = 0.0
        }

        // Subtle background pill fade
        withAnimation(.easeOut(duration: 0.85)) {
            glowOpacity = 0.0
        }
    }
}

