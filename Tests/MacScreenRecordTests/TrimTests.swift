import AVFoundation
import CoreMedia
import CoreVideo
import EncoderKit
import Foundation
@testable import RecorderUI

@MainActor
final class TrimTests {

    private var tempDir: URL!

    func withLifecycle(_ body: () async throws -> Void) async throws {
        tempDir = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("TrimTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            if let tempDir {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
        try await body()
    }

    /// Verifies format recognition for lossless passthrough trimming.
    func testLosslessTrimmerSupportedFormats() throws {
        let mp4URL = URL(fileURLWithPath: "/tmp/sample.mp4")
        let movURL = URL(fileURLWithPath: "/tmp/sample.MOV")
        let m4vURL = URL(fileURLWithPath: "/tmp/sample.M4V")
        let gifURL = URL(fileURLWithPath: "/tmp/sample.gif")
        let txtURL = URL(fileURLWithPath: "/tmp/sample.txt")
        let aviURL = URL(fileURLWithPath: "/tmp/sample.avi")

        try checkTrue(LosslessTrimmer.isSupported(url: mp4URL), "mp4 supported")
        try checkTrue(LosslessTrimmer.isSupported(url: movURL), "MOV supported")
        try checkTrue(LosslessTrimmer.isSupported(url: m4vURL), "M4V supported")
        try checkFalse(LosslessTrimmer.isSupported(url: gifURL), "gif rejected")
        try checkFalse(LosslessTrimmer.isSupported(url: txtURL), "txt rejected")
        try checkFalse(LosslessTrimmer.isSupported(url: aviURL), "avi rejected")
    }

    /// Verifies default trimmed file URL naming and collision suffixing.
    func testLosslessTrimmerDefaultTrimmedURL() throws {
        let baseFile = tempDir.appendingPathComponent("Recording.mp4")
        try Data("dummy".utf8).write(to: baseFile)

        let trimmed1 = LosslessTrimmer.defaultTrimmedURL(for: baseFile)
        try checkEqual(trimmed1.lastPathComponent, "Recording_trimmed.mp4")

        // Simulate collision by creating the file
        try Data("dummy".utf8).write(to: trimmed1)
        let trimmed2 = LosslessTrimmer.defaultTrimmedURL(for: baseFile)
        try checkEqual(trimmed2.lastPathComponent, "Recording_trimmed (2).mp4")
    }

    /// Verifies parameter validation on start/end timestamps.
    func testLosslessTrimmerTimeRangeValidation() async throws {
        let testVideo = tempDir.appendingPathComponent("short.mp4")
        try await createSyntheticMovie(at: testVideo, frameCount: 30, fps: 30) // 1.0s video

        let dest = tempDir.appendingPathComponent("out.mp4")

        // Negative start time
        do {
            try await LosslessTrimmer.trim(source: testVideo, destination: dest, startTime: -1.0, endTime: 0.5)
            try checkTrue(false, "Should have thrown for negative start")
        } catch let err as LosslessTrimmer.TrimError {
            switch err {
            case .invalidTimeRange: break
            default: try checkTrue(false, "Unexpected error: \(err)")
            }
        }

        // End time exceeds duration
        do {
            try await LosslessTrimmer.trim(source: testVideo, destination: dest, startTime: 0.0, endTime: 5.0)
            try checkTrue(false, "Should have thrown for end time past duration")
        } catch let err as LosslessTrimmer.TrimError {
            switch err {
            case .invalidTimeRange: break
            default: try checkTrue(false, "Unexpected error: \(err)")
            }
        }

        // Start >= End
        do {
            try await LosslessTrimmer.trim(source: testVideo, destination: dest, startTime: 0.8, endTime: 0.2)
            try checkTrue(false, "Should have thrown for start >= end")
        } catch let err as LosslessTrimmer.TrimError {
            switch err {
            case .invalidTimeRange: break
            default: try checkTrue(false, "Unexpected error: \(err)")
            }
        }
    }

    /// Verifies frame-accurate lossless trimming with actual AVAssetExportPresetPassthrough.
    func testLosslessTrimmerExecutionWithSyntheticMovie() async throws {
        let sourceVideo = tempDir.appendingPathComponent("source-2s.mp4")
        // Create 2.0s video (60 frames at 30 fps)
        try await createSyntheticMovie(at: sourceVideo, frameCount: 60, fps: 30)

        let initialDuration = try await LosslessTrimmer.loadDuration(for: sourceVideo)
        try checkTrue(abs(initialDuration - 2.0) < 0.2, "Initial duration ~2.0s")

        let destVideo = tempDir.appendingPathComponent("trimmed-1s.mp4")
        let resultURL = try await LosslessTrimmer.trim(
            source: sourceVideo,
            destination: destVideo,
            startTime: 0.5,
            endTime: 1.5
        )

        try checkEqual(resultURL, destVideo)
        try checkTrue(FileManager.default.fileExists(atPath: destVideo.path), "Trimmed output exists")

        let trimmedDuration = try await LosslessTrimmer.loadDuration(for: destVideo)
        try checkTrue(trimmedDuration > 0.8 && trimmedDuration < 1.2, "Trimmed duration ~1.0s (got \(trimmedDuration))")

        let attrs = try FileManager.default.attributesOfItem(atPath: destVideo.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        try checkTrue(size > 500, "Output file has non-trivial video content (got \(size) bytes)")
    }

    /// Verifies RecordingsLibrary trim integration for both copy and trash-safe replacement.
    func testRecordingsLibraryTrimIntegration() async throws {
        let libraryFolder = tempDir.appendingPathComponent("Library", isDirectory: true)
        let library = RecordingsLibrary(folder: libraryFolder)

        let testVideo = libraryFolder.appendingPathComponent("Record 2026-10-14.mp4")
        try await createSyntheticMovie(at: testVideo, frameCount: 60, fps: 30)
        await library.reload()

        try checkEqual(library.files.count, 1)
        let initialFile = library.files[0]

        // 1. Save Copy mode
        let copyURL = try await library.trimRecording(
            file: initialFile,
            startTime: 0.2,
            endTime: 1.2,
            mode: .saveCopy
        )
        try checkTrue(FileManager.default.fileExists(atPath: copyURL.path))
        try checkEqual(library.files.count, 2, "Library now contains original + trimmed copy")

        // 2. Replace Original mode
        let replacedURL = try await library.trimRecording(
            file: initialFile,
            startTime: 0.3,
            endTime: 0.8,
            mode: .replaceOriginal
        )
        try checkEqual(replacedURL, initialFile.url)
        try checkTrue(FileManager.default.fileExists(atPath: replacedURL.path))
        let newDuration = try await LosslessTrimmer.loadDuration(for: replacedURL)
        try checkTrue(newDuration < 0.8, "Replaced file has shorter duration")
    }

    // MARK: - Synthetic Movie Generation Helper

    private func createSyntheticMovie(at url: URL, frameCount: Int = 30, fps: Int = 30) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160,
            AVVideoHeightKey: 120
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 160,
                kCVPixelBufferHeightKey as String: 120
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            160, 120,
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )

        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let presentationTime = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            if let pb = pixelBuffer {
                adaptor.append(pb, withPresentationTime: presentationTime)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
