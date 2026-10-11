import AVFoundation
import CoreMedia
import EncoderKit
import Foundation
import OSLog
import ScreenCaptureKit

/// Drives an `SCStream` and forwards its `CMSampleBuffer`s to a `VideoEncoder`.
/// Optionally also drives an `AVCaptureSession` for microphone input — that
/// path is wired up in `MicrophoneCapture.swift`.
///
/// Reference: Apple's "Capturing screen content in macOS" sample code
/// (https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
/// and WWDC22 session 10156 "Meet ScreenCaptureKit".
public final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    public enum State: Sendable, Equatable {
        case idle, starting, recording, paused, stopping, finished, failed(String)
    }

    public enum CaptureError: LocalizedError {
        case sourceNotFound
        case streamFailed(String)
        case encoderFailed(String)
        case microphoneFailed(String)

        public var errorDescription: String? {
            switch self {
            case .sourceNotFound:           return "The selected source is no longer available — refresh and try again."
            case .streamFailed(let msg):    return "Recording failed: \(msg)"
            case .encoderFailed(let msg):   return "Couldn't start the encoder: \(msg)"
            case .microphoneFailed(let msg): return "Microphone error: \(msg)"
            }
        }
    }

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "CaptureSession")

    private let ourBundleID: String
    private var stream: SCStream?
    private var encoder: VideoEncoder?
    private var micCapture: MicrophoneCapture?
    public let levels: AudioLevelMonitor

    private let videoQueue = DispatchQueue(label: "com.macscreenrecord.capture.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.macscreenrecord.capture.audio", qos: .userInitiated)

    private let stateLock = NSLock()
    private var _state: State = .idle
    public private(set) var state: State {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _state }
        set { stateLock.lock(); _state = newValue; stateLock.unlock() }
    }
    public var onFailure: (@Sendable (String) -> Void)?

    public init(ourBundleID: String, levels: AudioLevelMonitor = AudioLevelMonitor()) {
        self.ourBundleID = ourBundleID
        self.levels = levels
        super.init()
    }

    // MARK: - Lifecycle

    public func start(
        source: CaptureSource,
        geometry: CaptureGeometry,
        settings: RecordingSettings,
        exceptingWindowIDs: [CGWindowID] = []
    ) async throws {
        let canStart: Bool = stateLock.withLock {
            switch _state {
            case .idle, .finished, .failed:
                _state = .starting
                return true
            default:
                return false
            }
        }
        guard canStart else {
            throw CaptureError.streamFailed("CaptureSession is already running")
        }

        let filter: SCContentFilter
        do {
            filter = try await Self.buildFilter(
                for: source,
                excludingBundleID: ourBundleID,
                exceptingWindowIDs: exceptingWindowIDs
            )
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
        let config = Self.buildConfiguration(geometry: geometry, source: source, settings: settings)

        // Encoder starts first so we have a place to send frames.
        let encoder = VideoEncoder(settings: settings)
        encoder.onError = { [weak self] error in
            let msg = error.localizedDescription
            self?.log.error("Encoder reported error: \(msg, privacy: .public)")
            self?.reportAsyncFailure(msg)
        }
        do {
            try encoder.start()
        } catch {
            state = .failed(error.localizedDescription)
            throw CaptureError.encoderFailed(error.localizedDescription)
        }
        self.encoder = encoder

        // Microphone capture (uses AVCaptureSession, independent of SCStream).
        if settings.captureMicrophone, let micID = settings.microphoneDeviceID {
            do {
                let mic = try MicrophoneCapture(deviceUniqueID: micID) { [weak self] buf in
                    guard let self else { return }
                    self.encoder?.append(buf, kind: .microphone)
                    self.levels.ingestMicrophone(buf)
                }
                try mic.start()
                self.micCapture = mic
            } catch {
                self.encoder?.cancel()
                self.encoder = nil
                state = .failed(error.localizedDescription)
                throw CaptureError.microphoneFailed(error.localizedDescription)
            }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            if settings.captureSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            }
        } catch {
            state = .failed(error.localizedDescription)
            self.micCapture?.stop()
            self.micCapture = nil
            self.encoder?.cancel()
            self.encoder = nil
            throw CaptureError.streamFailed(error.localizedDescription)
        }
        self.stream = stream

        do {
            try await stream.startCapture()
            state = .recording
            log.info("Capture started")
        } catch {
            state = .failed(error.localizedDescription)
            self.micCapture?.stop()
            self.micCapture = nil
            self.encoder?.cancel()
            self.encoder = nil
            self.stream = nil
            throw CaptureError.streamFailed(error.localizedDescription)
        }
    }

    public func pause() {
        let didPause: Bool = stateLock.withLock {
            guard case .recording = _state else { return false }
            _state = .paused
            return true
        }
        if didPause {
            encoder?.pause()
        }
    }

    public func resume() {
        let didResume: Bool = stateLock.withLock {
            guard case .paused = _state else { return false }
            _state = .recording
            return true
        }
        if didResume {
            encoder?.resume()
        }
    }

    @discardableResult
    public func stop() async throws -> URL {
        let canStop: Bool = stateLock.withLock {
            switch _state {
            case .recording, .paused, .failed:
                _state = .stopping
                return true
            default:
                return false
            }
        }
        guard canStop else {
            throw CaptureError.streamFailed("Not recording")
        }

        do { try await stream?.stopCapture() } catch {
            log.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
        }
        micCapture?.stop()
        micCapture = nil

        guard let encoder else {
            state = .failed("encoder missing")
            throw CaptureError.streamFailed("encoder missing")
        }

        do {
            let url = try await encoder.finish()
            self.encoder = nil
            self.stream = nil
            state = .idle
            return url
        } catch {
            self.encoder = nil
            self.stream = nil
            state = .idle
            throw error
        }
    }

    // MARK: - SCStreamOutput

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }

        switch outputType {
        case .screen:
            // Only forward "complete" frames — SCK also emits "idle" / "blank"
            // frames when nothing changed; including them confuses the encoder.
            guard
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                let attach = attachments.first,
                let statusRaw = attach[.status] as? Int,
                let status = SCFrameStatus(rawValue: statusRaw),
                status == .complete
            else { return }
            encoder?.append(sampleBuffer, kind: .video)

        case .audio:
            encoder?.append(sampleBuffer, kind: .systemAudio)
            levels.ingestSystemAudio(sampleBuffer)

        case .microphone:
            // macOS 15+ provides mic frames directly through SCStream. We don't
            // opt in to that here (we use AVCaptureSession instead) but pass it
            // through if it ever shows up.
            encoder?.append(sampleBuffer, kind: .microphone)
            levels.ingestMicrophone(sampleBuffer)

        @unknown default:
            return
        }
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        let msg = error.localizedDescription
        log.error("Stream stopped with error: \(msg, privacy: .public)")
        reportAsyncFailure(msg)
    }

    private func reportAsyncFailure(_ msg: String) {
        stateLock.lock()
        let shouldNotify: Bool
        switch _state {
        case .starting, .recording, .paused:
            _state = .failed(msg)
            shouldNotify = true
        default:
            shouldNotify = false
        }
        stateLock.unlock()
        guard shouldNotify else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?(msg)
        }
    }

    // MARK: - Helpers

    private static func buildFilter(
        for source: CaptureSource,
        excludingBundleID ourBundleID: String,
        exceptingWindowIDs: [CGWindowID]
    ) async throws -> SCContentFilter {
        let content = try await SCShareableContent.current
        let ourApp = content.applications.first { $0.bundleIdentifier == ourBundleID }
        let exclude = ourApp.map { [$0] } ?? []
        // Resolve windowIDs → SCWindow so we can pass them as exceptions to the
        // SCK filter (these are our overlay windows we WANT to capture).
        let exceptions = content.windows.filter { exceptingWindowIDs.contains($0.windowID) }

        switch source {
        case .display(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw CaptureError.sourceNotFound }
            return SCContentFilter(display: display, excludingApplications: exclude, exceptingWindows: exceptions)

        case .window(let windowID):
            // `desktopIndependentWindow` has no exception API. Webcam / click
            // overlays will not appear in window captures — known limitation.
            guard let window = content.windows.first(where: { $0.windowID == windowID })
            else { throw CaptureError.sourceNotFound }
            return SCContentFilter(desktopIndependentWindow: window)

        case .application(let pid, let displayID):
            guard let app = content.applications.first(where: { $0.processID == pid }),
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw CaptureError.sourceNotFound }
            // Include both the user's app AND our app so the overlay windows
            // can pass through as exceptions; everything else of ours is excluded.
            var includes = [app]
            if let ourApp { includes.append(ourApp) }
            return SCContentFilter(display: display, including: includes, exceptingWindows: ourWindowsToExclude(content: content, ourBundleID: ourBundleID, keep: Set(exceptingWindowIDs)))
        }
    }

    /// All windows belonging to our own app *except* the ones we want to keep
    /// (webcam/click overlays). Used in app-capture mode where SCK includes
    /// our app to allow overlays to pass through.
    private static func ourWindowsToExclude(
        content: SCShareableContent,
        ourBundleID: String,
        keep: Set<CGWindowID>
    ) -> [SCWindow] {
        content.windows.filter {
            $0.owningApplication?.bundleIdentifier == ourBundleID && !keep.contains($0.windowID)
        }
    }

    private static func buildConfiguration(
        geometry: CaptureGeometry,
        source: CaptureSource,
        settings: RecordingSettings
    ) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = geometry.outputWidth
        config.height = geometry.outputHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(geometry.fps))
        config.queueDepth = 6
        config.showsCursor = geometry.showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        if settings.captureSystemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
        }

        // Optional source crop for display capture.
        if case .display(_, let region?) = source {
            config.sourceRect = region
            // When sourceRect is set, output dimensions should match the crop.
            config.width = Int(region.width)
            config.height = Int(region.height)
        }

        return config
    }
}

