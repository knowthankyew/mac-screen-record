import AVFoundation
import AVKit
import AppKit
import EncoderKit
import OSLog
import SwiftUI

/// Interactive modal sheet for post-capture and posthumous lossless video trimming.
/// Provides frame-accurate In/Out selection over an asynchronous filmstrip preview,
/// backed by native `AVAssetExportPresetPassthrough` for sub-second zero-loss export.
public struct VideoTrimModalView: View {

    public let target: RecordingViewModel.TrimTarget
    public let library: RecordingsLibrary
    public let settings: AppSettings
    public var onTrimSaved: ((URL) -> Void)?
    public var onDiscard: (() -> Void)?
    public var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var duration: Double = 0.0
    @State private var currentTime: Double = 0.0
    @State private var startTime: Double = 0.0
    @State private var endTime: Double = 0.0
    @State private var isPlaying: Bool = false

    @State private var thumbnails: [CGImage] = []
    @State private var isLoadingThumbnails: Bool = true
    @State private var isExporting: Bool = false
    @State private var errorMessage: String?
    @State private var showReplaceConfirmation: Bool = false

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "VideoTrimModalView")

    public init(
        target: RecordingViewModel.TrimTarget,
        library: RecordingsLibrary,
        settings: AppSettings,
        onTrimSaved: ((URL) -> Void)? = nil,
        onDiscard: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.target = target
        self.library = library
        self.settings = settings
        self.onTrimSaved = onTrimSaved
        self.onDiscard = onDiscard
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                if let player = player {
                    VideoPlayerCanvas(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .padding(.vertical, 8)
                } else {
                    ProgressView("Loading Video…")
                        .progressViewStyle(.circular)
                        .foregroundStyle(.white)
                }

                if isExporting {
                    exportProgressOverlay
                }
            }
            .frame(minHeight: 260, maxHeight: 420)

            Divider()
            timelineControls
            Divider()
            bottomActionBar
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .allowAppTerminationWhenModal()
        .alert("Trimming Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Replace Original Recording?",
            isPresented: $showReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Original (Trash-Safe)", role: .destructive) {
                performTrim(mode: .replaceOriginal)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original recording will be moved to the macOS Trash and replaced with the trimmed video. This action cannot be undone from the app.")
        }
        .task {
            await initializeVideo()
        }
        .onDisappear {
            teardownPlayer()
            onDismiss?()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "scissors")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.isPostCaptureReview ? "Review & Trim Recording" : "Lossless Video Trimmer")
                    .font(.headline)
                Text(target.url.lastPathComponent)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if duration > 0 {
                HStack(spacing: 6) {
                    Text("Original:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTimestamp(duration))
                        .font(.caption.bold().monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
    }

    // MARK: - Timeline & Filmstrip Controls

    private var timelineControls: some View {
        VStack(spacing: 12) {
            // Playback and timestamp readouts
            HStack(spacing: 16) {
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.space, modifiers: [])
                .help("Play / Pause Selection (Space)")

                VStack(alignment: .leading, spacing: 1) {
                    Text("In (Start)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatTimestamp(startTime))
                        .font(.callout.bold().monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                VStack(spacing: 1) {
                    Text("Trimmed Duration")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatTimestamp(max(0, endTime - startTime)))
                        .font(.callout.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Out (End)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatTimestamp(endTime))
                        .font(.callout.bold().monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Filmstrip with draggable trim handles
            FilmstripTimelineView(
                duration: duration,
                currentTime: $currentTime,
                startTime: $startTime,
                endTime: $endTime,
                thumbnails: thumbnails,
                isLoading: isLoadingThumbnails,
                onSeek: { targetSecs in
                    seek(to: targetSecs)
                }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            if target.isPostCaptureReview {
                Button("Discard Recording", role: .destructive) {
                    if let onDiscard {
                        onDiscard()
                    } else {
                        library.deleteArtifacts(at: target.url, moveToTrash: true)
                    }
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Keep Full Video") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Trim & Save") {
                    performTrim(mode: .replaceOriginal)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || (endTime - startTime) < 0.05)
            } else {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                if isLibraryFile {
                    Button("Replace Original…") {
                        showReplaceConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExporting || (endTime - startTime) < 0.05)
                }

                Button("Save Trimmed Copy") {
                    performTrim(mode: .saveCopy)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || (endTime - startTime) < 0.05)
            }
        }
        .padding(16)
    }

    // MARK: - Progress Overlay

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                Text("Exporting Lossless Passthrough…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Preserving bitstream encoding without generational loss")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor).opacity(0.95)))
            .shadow(radius: 16)
        }
    }

    // MARK: - Video Initialization & Playback

    private var isLibraryFile: Bool {
        target.url.deletingLastPathComponent().standardizedFileURL == library.folder.standardizedFileURL
    }

    private func initializeVideo() async {
        guard FileManager.default.fileExists(atPath: target.url.path) else {
            errorMessage = "File does not exist at \(target.url.lastPathComponent)."
            return
        }

        do {
            let dur = try await LosslessTrimmer.loadDuration(for: target.url)
            self.duration = dur
            self.startTime = 0.0
            self.endTime = dur

            let avPlayer = AVPlayer(url: target.url)
            avPlayer.actionAtItemEnd = .none
            self.player = avPlayer

            // Setup periodic observer for time and playhead bounds
            let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
            self.timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
                guard let avPlayer = avPlayer else { return }
                let current = time.seconds
                self.currentTime = current

                // Loop playback inside the trimmed range
                if self.isPlaying && current >= self.endTime {
                    avPlayer.seek(to: CMTime(seconds: self.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }

            // Load thumbnails asynchronously
            loadThumbnails()
        } catch {
            errorMessage = "Could not load video: \(error.localizedDescription)"
        }
    }

    private func loadThumbnails() {
        isLoadingThumbnails = true
        let url = target.url
        Task.detached(priority: .userInitiated) {
            do {
                let thumbs = try await LosslessTrimmer.generateThumbnails(for: url, count: 12, maxDimension: 120)
                await MainActor.run {
                    self.thumbnails = thumbs
                    self.isLoadingThumbnails = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingThumbnails = false
                    self.log.debug("Thumbnail generation finished with note: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime < startTime || currentTime >= endTime {
                seek(to: startTime)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        guard let player = player else { return }
        let clamped = max(0, min(seconds, duration))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func teardownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }

    // MARK: - Trimming Execution

    private func performTrim(mode: RecordingsLibrary.TrimDestinationMode) {
        isExporting = true
        player?.pause()
        isPlaying = false

        Task {
            do {
                let savedURL: URL
                if let originalFile = target.originalFile {
                    savedURL = try await library.trimRecording(
                        file: originalFile,
                        startTime: startTime,
                        endTime: endTime,
                        mode: mode
                    )
                } else if isLibraryFile {
                    // Post-capture or library recording without cached RecordingFile
                    let recFile = RecordingFile(
                        url: target.url,
                        name: target.url.lastPathComponent,
                        createdAt: (try? target.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date(),
                        sizeBytes: Int64((try? target.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0),
                        duration: duration
                    )
                    savedURL = try await library.trimRecording(
                        file: recFile,
                        startTime: startTime,
                        endTime: endTime,
                        mode: mode
                    )
                } else {
                    // External file from outside library folder
                    savedURL = try await library.trimExternalFile(
                        at: target.url,
                        startTime: startTime,
                        endTime: endTime
                    )
                }

                await MainActor.run {
                    isExporting = false
                    onTrimSaved?(savedURL)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = "Trim failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func formatTimestamp(_ secs: Double) -> String {
        guard secs.isFinite && secs >= 0 else { return "00:00.00" }
        let minutes = Int(secs) / 60
        let seconds = Int(secs) % 60
        let hundredths = Int((secs.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }
}

// MARK: - VideoPlayerCanvas NSViewRepresentable

private struct VideoPlayerCanvas: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - Filmstrip Timeline View

private struct FilmstripTimelineView: View {
    let duration: Double
    @Binding var currentTime: Double
    @Binding var startTime: Double
    @Binding var endTime: Double
    let thumbnails: [CGImage]
    let isLoading: Bool
    let onSeek: (Double) -> Void

    private let handleWidth: CGFloat = 16
    private let trackHeight: CGFloat = 54

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let safeDuration = max(0.01, duration)

            let startX = CGFloat(startTime / safeDuration) * totalWidth
            let endX = CGFloat(endTime / safeDuration) * totalWidth
            let playheadX = CGFloat(currentTime / safeDuration) * totalWidth

            ZStack(alignment: .leading) {
                // Background thumbnail filmstrip
                HStack(spacing: 2) {
                    if thumbnails.isEmpty {
                        ForEach(0..<8, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(maxWidth: .infinity, maxHeight: trackHeight)
                        }
                    } else {
                        ForEach(0..<thumbnails.count, id: \.self) { i in
                            Image(decorative: thumbnails[i], scale: 1.0)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: trackHeight)
                                .clipped()
                        }
                    }
                }
                .frame(width: totalWidth, height: trackHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Dimmed region before In point
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: max(0, startX), height: trackHeight)
                    .clipShape(RoundedCornerShape(radius: 6, corners: [.topLeft, .bottomLeft]))

                // Dimmed region after Out point
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .offset(x: endX)
                    .frame(width: max(0, totalWidth - endX), height: trackHeight)
                    .clipShape(RoundedCornerShape(radius: 6, corners: [.topRight, .bottomRight]))

                // Active selection border
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .offset(x: startX)
                    .frame(width: max(handleWidth * 2, endX - startX), height: trackHeight)

                // Left In Handle
                handleView(isLeft: true)
                    .offset(x: max(0, startX - handleWidth / 2))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newX = value.location.x
                                let newSecs = max(0, min(Double(newX / totalWidth) * safeDuration, endTime - 0.05))
                                startTime = newSecs
                                onSeek(newSecs)
                            }
                    )

                // Right Out Handle
                handleView(isLeft: false)
                    .offset(x: min(totalWidth - handleWidth, endX - handleWidth / 2))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newX = value.location.x
                                let newSecs = min(safeDuration, max(Double(newX / totalWidth) * safeDuration, startTime + 0.05))
                                endTime = newSecs
                                onSeek(newSecs)
                            }
                    )

                // Current playhead needle
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: trackHeight + 8)
                    .shadow(radius: 2)
                    .offset(x: max(0, min(playheadX - 1, totalWidth - 2)), y: -4)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clickSecs = max(0, min(Double(value.location.x / totalWidth) * safeDuration, safeDuration))
                        onSeek(clickSecs)
                    }
            )
        }
        .frame(height: trackHeight)
    }

    private func handleView(isLeft: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor)
                .frame(width: handleWidth, height: trackHeight)
                .shadow(radius: 2)

            Image(systemName: isLeft ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .contentShape(Rectangle().size(width: handleWidth * 2, height: trackHeight))
    }
}

// MARK: - Rounded Corner Helper

private struct RoundedCornerShape: Shape {
    var radius: CGFloat = .infinity
    var corners: Set<Corner> = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 { path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        path.closeSubpath()
        return path
    }
}
