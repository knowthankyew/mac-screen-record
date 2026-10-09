import AVFoundation
import CoreMedia
import Foundation
import OSLog

/// Wraps `AVAssetWriter` to consume `CMSampleBuffer`s from ScreenCaptureKit
/// and from `AVCaptureSession` audio inputs, and produce a single output file.
///
/// Pattern follows Apple's "Capturing screen content in macOS" sample:
/// https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
public final class VideoEncoder: @unchecked Sendable {
    public enum EncoderError: Error {
        case writerInitFailed(String)
        case notStarted
        case alreadyStarted
        case finishFailed(String)
    }

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "VideoEncoder")
    private let settings: RecordingSettings

    public var onError: (@Sendable (Error) -> Void)?
    private var hasReportedError = false
    private var errorLock = os_unfair_lock()

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?

    private var sessionStarted = false
    private var sessionStartPTS: CMTime?
    private let queue = DispatchQueue(label: "com.macscreenrecord.encoder", qos: .userInitiated)

    // Pause / resume: track total paused duration so PTS can be rewritten and
    // the recording excises pause intervals rather than freezing on a frame.
    private var paused = false
    private var pauseStartPTS: CMTime?
    private var totalPausedDuration: CMTime = .zero
    private var pauseWindows: [(start: CMTime, end: CMTime)] = []
    private var lastAppendedPTS: [SampleKind: CMTime] = [:]

    public init(settings: RecordingSettings) {
        self.settings = settings
    }

    public var isPaused: Bool {
        queue.sync { paused }
    }

    public func pause() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        queue.sync {
            guard !paused else { return }
            paused = true
            pauseStartPTS = now
        }
    }

    public func resume() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        queue.sync {
            guard paused, let start = pauseStartPTS else { paused = false; return }
            // Add the gap between when we paused and "now" to the offset so the
            // next frame appears immediately after the last appended one.
            let gap = CMTimeSubtract(now, start)
            totalPausedDuration = CMTimeAdd(totalPausedDuration, gap)
            pauseWindows.append((start: start, end: now))
            paused = false
            pauseStartPTS = nil
        }
    }

    public func start() throws {
        guard writer == nil else { throw EncoderError.alreadyStarted }

        // Make sure the parent directory exists and remove any stale file.
        let url = settings.outputURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: settings.codec.avFileType)
        } catch {
            throw EncoderError.writerInitFailed(error.localizedDescription)
        }

        // Enable movie fragment writing for MP4 and MOV containers.
        // This writes movie fragments (moof boxes) every 10 seconds, which:
        // 1. Prevents buffering enormous index structures in RAM on long (e.g. 15+ min) recordings.
        // 2. Flushes media data directly to disk periodically.
        // 3. Guarantees that if a crash, hardware reset, or mid-stream error occurs,
        //    all completed fragments up to the point of failure remain playable on disk.
        if settings.codec.avFileType == .mp4 || settings.codec.avFileType == .mov {
            writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        } else {
            writer.shouldOptimizeForNetworkUse = true
        }

        // ── Video input ────────────────────────────────────────────────────
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.codec.avVideoCodec,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
        ]
        switch settings.codec {
        case .h264, .hevc:
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: settings.effectiveBitrate,
                AVVideoExpectedSourceFrameRateKey: settings.fps,
                AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
                AVVideoAllowFrameReorderingKey: false,
            ]
        case .proRes422, .proRes4444:
            // ProRes is intra-frame; no bitrate / GOP knobs.
            break
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw EncoderError.writerInitFailed("Writer rejected video input")
        }
        writer.add(videoInput)
        self.videoInput = videoInput

        // ── Audio inputs (mic + system audio as separate tracks) ──────────
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 192_000,
        ]
        if settings.captureMicrophone {
            let mic = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            mic.expectsMediaDataInRealTime = true
            if writer.canAdd(mic) {
                writer.add(mic)
                self.micInput = mic
            }
        }
        if settings.captureSystemAudio {
            let sys = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            sys.expectsMediaDataInRealTime = true
            if writer.canAdd(sys) {
                writer.add(sys)
                self.systemAudioInput = sys
            }
        }

        guard writer.startWriting() else {
            throw EncoderError.writerInitFailed(
                writer.error?.localizedDescription ?? "startWriting() returned false"
            )
        }
        self.writer = writer
        log.info("Encoder started: \(url.path, privacy: .public)")
    }

    public enum SampleKind: Hashable, Sendable {
        case video
        case microphone
        case systemAudio
    }

    /// Append a sample buffer. Called from the SCStream / AVCaptureSession
    /// delegate threads — internally serialized onto the encoder queue.
    public func append(_ sampleBuffer: CMSampleBuffer, kind: SampleKind) {
        queue.async { [weak self] in
            guard let self, let writer = self.writer else { return }

            if writer.status == .failed {
                self.reportFailureIfNeeded(writer.error ?? EncoderError.finishFailed("Encoder asset writer has failed"))
                return
            }

            let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard originalPTS.isValid else { return }

            // Drop samples captured while paused or during a completed pause window
            if self.paused, let start = self.pauseStartPTS, originalPTS >= start {
                return
            }
            if self.pauseWindows.contains(where: { originalPTS >= $0.start && originalPTS < $0.end }) {
                return
            }

            // Start the session at the timestamp of the first video frame —
            // this is what ScreenCaptureKit recommends to keep video/audio
            // tracks aligned.
            if !self.sessionStarted {
                guard kind == .video else { return }   // wait for first video frame
                writer.startSession(atSourceTime: originalPTS)
                self.sessionStarted = true
                self.sessionStartPTS = originalPTS
                self.log.info("Encoder session started @\(originalPTS.seconds, privacy: .public)s")
            }

            // Drop any sample buffer captured prior to session start
            if let startPTS = self.sessionStartPTS, originalPTS < startPTS {
                return
            }

            let input: AVAssetWriterInput?
            switch kind {
            case .video:        input = self.videoInput
            case .microphone:   input = self.micInput
            case .systemAudio:  input = self.systemAudioInput
            }
            guard let input, input.isReadyForMoreMediaData else { return }

            // Calculate pause offset applicable to this sample
            let offset: CMTime = {
                if self.pauseWindows.isEmpty { return self.totalPausedDuration }
                return self.pauseWindows
                    .filter { $0.end <= originalPTS }
                    .reduce(CMTime.zero) { CMTimeAdd($0, CMTimeSubtract($1.end, $1.start)) }
            }()

            // Rewrite PTS to subtract any time spent paused before this sample
            let buffer: CMSampleBuffer
            var finalPTS = originalPTS
            if offset > .zero {
                var timingCount: CMItemCount = 0
                var status = CMSampleBufferGetSampleTimingInfoArray(
                    sampleBuffer,
                    entryCount: 0,
                    arrayToFill: nil,
                    entriesNeededOut: &timingCount
                )
                if status == noErr, timingCount > 0 {
                    var timings = [CMSampleTimingInfo](
                        repeating: CMSampleTimingInfo(
                            duration: .invalid,
                            presentationTimeStamp: .invalid,
                            decodeTimeStamp: .invalid
                        ),
                        count: timingCount
                    )
                    status = timings.withUnsafeMutableBufferPointer { timingBuffer in
                        CMSampleBufferGetSampleTimingInfoArray(
                            sampleBuffer,
                            entryCount: timingCount,
                            arrayToFill: timingBuffer.baseAddress,
                            entriesNeededOut: &timingCount
                        )
                    }
                    if status == noErr {
                        for index in timings.indices
                            where timings[index].presentationTimeStamp.isValid {
                            timings[index].presentationTimeStamp = CMTimeSubtract(
                                timings[index].presentationTimeStamp,
                                offset
                            )
                        }
                        if let firstValid = timings.first(where: { $0.presentationTimeStamp.isValid }) {
                            finalPTS = firstValid.presentationTimeStamp
                        }
                        var rewritten: CMSampleBuffer?
                        status = CMSampleBufferCreateCopyWithNewTiming(
                            allocator: kCFAllocatorDefault,
                            sampleBuffer: sampleBuffer,
                            sampleTimingEntryCount: timings.count,
                            sampleTimingArray: timings,
                            sampleBufferOut: &rewritten
                        )
                        guard status == noErr, let rewritten else { return }
                        buffer = rewritten
                    } else {
                        return
                    }
                } else {
                    let adjustedPTS = CMTimeSubtract(originalPTS, offset)
                    finalPTS = adjustedPTS
                    let timing = CMSampleTimingInfo(
                        duration: CMSampleBufferGetDuration(sampleBuffer),
                        presentationTimeStamp: adjustedPTS,
                        decodeTimeStamp: .invalid
                    )
                    var rewritten: CMSampleBuffer?
                    let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
                        allocator: kCFAllocatorDefault,
                        sampleBuffer: sampleBuffer,
                        sampleTimingEntryCount: 1,
                        sampleTimingArray: [timing],
                        sampleBufferOut: &rewritten
                    )
                    guard copyStatus == noErr, let rewritten else { return }
                    buffer = rewritten
                }
            } else {
                buffer = sampleBuffer
            }

            // Enforce strictly monotonic presentation timestamps per input track
            if let lastPTS = self.lastAppendedPTS[kind], finalPTS <= lastPTS {
                return
            }

            let success = input.append(buffer)
            if success {
                self.lastAppendedPTS[kind] = finalPTS
            } else if writer.status == .failed {
                self.log.error("Failed to append buffer of kind \(String(describing: kind)): writer status \(writer.status.rawValue)")
                self.reportFailureIfNeeded(writer.error ?? EncoderError.finishFailed("Asset writer failed during append"))
            }
        }
    }

    private func reportFailureIfNeeded(_ error: Error) {
        os_unfair_lock_lock(&errorLock)
        guard !hasReportedError else {
            os_unfair_lock_unlock(&errorLock)
            return
        }
        hasReportedError = true
        os_unfair_lock_unlock(&errorLock)

        log.error("Encoder encountered fatal error: \(error.localizedDescription, privacy: .public)")
        onError?(error)
    }

    public func cancel() {
        queue.sync {
            guard let writer = self.writer else { return }
            if writer.status == .writing {
                writer.cancelWriting()
            }
            try? FileManager.default.removeItem(at: writer.outputURL)
            self.writer = nil
            self.videoInput = nil
            self.micInput = nil
            self.systemAudioInput = nil
        }
    }

    public func finish() async throws -> URL {
        guard let writer = self.writer else { throw EncoderError.notStarted }

        // Drain queued appends before finalizing.
        await withCheckedContinuation { cont in
            queue.async { cont.resume() }
        }

        videoInput?.markAsFinished()
        micInput?.markAsFinished()
        systemAudioInput?.markAsFinished()

        await writer.finishWriting()

        if writer.status == .failed {
            let err = writer.error ?? EncoderError.finishFailed("unknown writer failure")
            reportFailureIfNeeded(err)
            throw EncoderError.finishFailed(err.localizedDescription)
        }
        log.info("Encoder finished: \(writer.outputURL.path, privacy: .public)")
        return writer.outputURL
    }
}
