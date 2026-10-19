import AVFoundation
import CaptureCore
import CoreMedia
import CoreVideo
import EncoderKit
import Foundation
@testable import RecorderUI

@MainActor
final class MenuBarAndSessionCompanionTests {

    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    func withLifecycle(_ body: () async throws -> Void) async throws {
        suiteName = "com.macscreenrecord.tests.companion.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        defer {
            if let suiteName {
                isolatedDefaults?.removePersistentDomain(forName: suiteName)
            }
        }
        try await body()
    }

    /// Verifies that MenuBarController exhibits zero status bar presence when idle,
    /// dynamically creates the status item upon recording/pause, and completely cleans up on termination.
    func testMenuBarEphemeralLifecycle() throws {
        let controller = MenuBarController()
        defer { controller.removeStatusItem() }

        // 1. Initially idle — must have ZERO status item
        try checkFalse(controller.hasStatusItem, "Status item does not exist while idle")

        // 2. Transition to recording — status item appears with duration
        let twoMinutesAgo = Date().addingTimeInterval(-125) // 02:05
        controller.update(for: .recording(startedAt: twoMinutesAgo))
        try checkTrue(controller.hasStatusItem, "Status item dynamically appears during recording")
        let recordingTitle = try unwrap(controller.currentButtonTitle)
        try checkTrue(recordingTitle.contains("02:05"), "Button title shows elapsed recording duration")

        // 3. Transition to paused — status item persists with (Paused) indicator
        let pauseTime = twoMinutesAgo.addingTimeInterval(120) // 02:00
        controller.update(for: .paused(startedAt: twoMinutesAgo, pausedAt: pauseTime))
        try checkTrue(controller.hasStatusItem, "Status item remains during pause")
        let pausedTitle = try unwrap(controller.currentButtonTitle)
        try checkTrue(pausedTitle.contains("02:00"), "Button title freezes at paused duration")
        try checkTrue(pausedTitle.contains("(Paused)"), "Button title includes (Paused) label")

        // 4. Transition to finished / idle — status item is completely removed (zero bloat)
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy.mp4")
        controller.update(for: .finished(dummyURL))
        try checkFalse(controller.hasStatusItem, "Status item is completely removed upon finishing")

        controller.update(for: .idle)
        try checkFalse(controller.hasStatusItem, "Status item remains absent in idle state")
    }

    /// Verifies duration string formatting across boundary conditions (MM:SS vs HH:MM:SS).
    func testDurationFormatting() throws {
        let controller = MenuBarController()
        defer { controller.removeStatusItem() }

        try checkEqual(controller.formatTime(seconds: 0), "00:00")
        try checkEqual(controller.formatTime(seconds: 59), "00:59")
        try checkEqual(controller.formatTime(seconds: 60), "01:00")
        try checkEqual(controller.formatTime(seconds: 3599), "59:59")
        try checkEqual(controller.formatTime(seconds: 3600), "01:00:00")
        try checkEqual(controller.formatTime(seconds: 7325), "02:02:05")
    }

    /// Verifies persistence and defaults of the distraction-free window auto-minimization setting.
    func testHideWindowDuringRecordingSetting() throws {
        let settings = AppSettings(defaults: isolatedDefaults)
        try checkFalse(settings.hideWindowDuringRecording, "hideWindowDuringRecording defaults to false")

        settings.hideWindowDuringRecording = true
        try checkTrue(settings.hideWindowDuringRecording, "hideWindowDuringRecording toggles to true")

        // Reload from defaults to verify persistence
        let reloaded = AppSettings(defaults: isolatedDefaults)
        try checkTrue(reloaded.hideWindowDuringRecording, "hideWindowDuringRecording persists to UserDefaults")
    }

    /// Verifies that burnRecording cleanly resets recording state back to ready/idle,
    /// clears lastRecordingURL, and unlinks the file from disk directly.
    func testBurnRecordingStateReset() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("BurnResetTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = AppSettings(defaults: isolatedDefaults)
        let vm = RecordingViewModel(settings: settings)

        // Setup a simulated in-progress recording file on disk
        let dummyFile = tempDir.appendingPathComponent("burn_test_target.mp4")
        try Data("dummy uncommitted recording data".utf8).write(to: dummyFile)
        try checkTrue(FileManager.default.fileExists(atPath: dummyFile.path), "Dummy recording file exists on disk")

        let now = Date()
        vm.setLastRecordingURLForTesting(dummyFile)
        vm.setStatusForTesting(.recording(startedAt: now))
        try checkEqual(vm.status, .recording(startedAt: now))
        try checkEqual(vm.lastRecordingURL, dummyFile)

        await vm.burnRecording()

        let expectedStatus = vm.displays.isEmpty ? RecordingViewModel.Status.idle : RecordingViewModel.Status.ready
        try checkEqual(vm.status, expectedStatus, "burnRecording resets status to ready or idle")
        try checkNil(vm.lastRecordingURL, "burnRecording clears lastRecordingURL")
        try checkFalse(FileManager.default.fileExists(atPath: dummyFile.path), "burnRecording immediately deletes uncommitted file from disk")
    }

    /// Verifies that VideoEncoder initializes output file on start, appends frame,
    /// and cancel() immediately cancels writing and unlinks the media file from disk.
    func testVideoEncoderCancelDeletesFileOnDisk() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("EncoderCancelTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputURL = tempDir.appendingPathComponent("test_cancel.mp4")
        let settings = RecordingSettings(width: 160, height: 120, fps: 30, outputURL: outputURL)
        let encoder = VideoEncoder(settings: settings)

        try encoder.start()
        try checkTrue(FileManager.default.fileExists(atPath: outputURL.path), "Writer creates output file on start")

        if let sample = makeSyntheticSampleBuffer(width: 160, height: 120, pts: .zero) {
            encoder.append(sample, kind: VideoEncoder.SampleKind.video)
        }

        encoder.cancel()
        try checkFalse(FileManager.default.fileExists(atPath: outputURL.path), "cancel() unlinks output file from disk")
    }

    /// Verifies that calling cancel() when writer has failed safely removes output file from disk.
    func testVideoEncoderCancelOnFailedWriterDeletesFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("EncoderFailedCancelTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputURL = tempDir.appendingPathComponent("test_failed_cancel.mp4")
        let settings = RecordingSettings(width: 160, height: 120, fps: 30, outputURL: outputURL)
        let encoder = VideoEncoder(settings: settings)

        try encoder.start()
        try checkTrue(FileManager.default.fileExists(atPath: outputURL.path), "Writer creates file")

        // Append a valid frame to start session
        if let sample = makeSyntheticSampleBuffer(width: 160, height: 120, pts: CMTime(value: 10, timescale: 30)) {
            encoder.append(sample, kind: VideoEncoder.SampleKind.video)
        }

        // Append a sample with mismatched dimensions (320x240) to force AVAssetWriter into .failed state
        if let mismatched = makeSyntheticSampleBuffer(width: 320, height: 240, pts: CMTime(value: 11, timescale: 30)) {
            encoder.append(mismatched, kind: VideoEncoder.SampleKind.video)
        }

        // Calling cancel() cleans up the file even when writer is in .failed state (not .writing)
        encoder.cancel()
        try checkFalse(FileManager.default.fileExists(atPath: outputURL.path), "cancel() unlinks file when writer is failed")
    }

    /// Verifies that updateFinishedRecording updates view model status and lastRecordingURL,
    /// enabling the prominent green link in the UI header, while protecting active recording states.
    func testSavedRecordingStateUpdateAndReveal() throws {
        let settings = AppSettings(defaults: isolatedDefaults)
        let vm = RecordingViewModel(settings: settings)

        let testURL = URL(fileURLWithPath: "/tmp/Sample_Recording_trimmed.mp4")
        vm.updateFinishedRecording(testURL)

        try checkEqual(vm.status, .finished(testURL), "status is updated to .finished with trimmed URL")
        try checkEqual(vm.lastRecordingURL, testURL, "lastRecordingURL is updated with trimmed URL")

        let linkView = SavedRecordingLinkView(url: testURL, onReveal: {})
        try checkEqual(linkView.url, testURL, "SavedRecordingLinkView accepts and holds target URL")

        // Guard test: active recording status must NOT be overwritten
        let now = Date()
        vm.setStatusForTesting(.recording(startedAt: now))
        let anotherURL = URL(fileURLWithPath: "/tmp/Another_trimmed.mp4")
        vm.updateFinishedRecording(anotherURL)
        try checkEqual(vm.status, .recording(startedAt: now), "updateFinishedRecording preserves active recording state")
    }

    // MARK: - Helpers

    private func makeSyntheticSampleBuffer(width: Int = 160, height: Int = 120, pts: CMTime = .zero) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            formatDescriptionOut: &formatDesc
        )
        guard let desc = formatDesc else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}
