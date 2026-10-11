import AVFoundation
import CoreMedia
@testable import CaptureCore
@testable import EncoderKit

final class EncoderAndCaptureTests {

    func testOutputCodecContainerAndMetadataMapping() throws {
        try checkEqual(OutputCodec.h264.fileExtension, "mp4")
        try checkEqual(OutputCodec.hevc.fileExtension, "mp4")
        try checkEqual(OutputCodec.proRes422.fileExtension, "mov")
        try checkEqual(OutputCodec.proRes4444.fileExtension, "mov")

        try checkEqual(OutputCodec.h264.avFileType, .mp4)
        try checkEqual(OutputCodec.hevc.avFileType, .mp4)
        try checkEqual(OutputCodec.proRes422.avFileType, .mov)
        try checkEqual(OutputCodec.proRes4444.avFileType, .mov)

        try checkEqual(OutputCodec.h264.avVideoCodec, .h264)
        try checkEqual(OutputCodec.hevc.avVideoCodec, .hevc)
        try checkEqual(OutputCodec.proRes422.avVideoCodec, .proRes422)
        try checkEqual(OutputCodec.proRes4444.avVideoCodec, .proRes4444)

        for codec in OutputCodec.allCases {
            try checkFalse(codec.displayName.isEmpty)
            let encoded = try JSONEncoder().encode(codec)
            let decoded = try JSONDecoder().decode(OutputCodec.self, from: encoded)
            try checkEqual(decoded, codec)
        }
    }

    func testRecordingSettingsEffectiveBitrateCalculation() throws {
        let outURL = URL(fileURLWithPath: "/tmp/test.mp4")

        // 1080p60 H.264: 1920 * 1080 * 60 * 0.10 = 12,441,600 bps
        let h264Settings = RecordingSettings(width: 1920, height: 1080, fps: 60, codec: .h264, outputURL: outURL)
        try checkEqual(h264Settings.effectiveBitrate, 12_441_600)

        // 1080p60 HEVC: 1920 * 1080 * 60 * 0.06 = 7,464,960 bps
        let hevcSettings = RecordingSettings(width: 1920, height: 1080, fps: 60, codec: .hevc, outputURL: outURL)
        try checkEqual(hevcSettings.effectiveBitrate, 7_464_960)

        // Small region clamps to 1,000,000 bps floor
        let tinySettings = RecordingSettings(width: 100, height: 100, fps: 30, codec: .hevc, outputURL: outURL)
        try checkEqual(tinySettings.effectiveBitrate, 1_000_000)

        // Explicit bitrate overrides heuristic
        let explicitSettings = RecordingSettings(
            width: 1920, height: 1080, fps: 60, codec: .h264, bitrate: 25_000_000, outputURL: outURL
        )
        try checkEqual(explicitSettings.effectiveBitrate, 25_000_000)
    }

    func testCaptureSourceAndGeometryDefaults() throws {
        let s1 = CaptureSource.display(id: 1, region: nil)
        let s2 = CaptureSource.display(id: 1, region: CGRect(x: 0, y: 0, width: 800, height: 600))
        let s3 = CaptureSource.window(id: 42)
        let s4 = CaptureSource.application(pid: 999, displayID: 1)

        try checkNotEqual(s1, s2)
        try checkNotEqual(s1, s3)
        try checkNotEqual(s3, s4)

        let geom = CaptureGeometry(outputWidth: 2560, outputHeight: 1440)
        try checkEqual(geom.fps, 60)
        try checkTrue(geom.showsCursor)
    }

    func testAudioLevelMonitorPeakAmplitudeFloat32AndInt16() throws {
        // 1. Float32 sample buffer with known peak 0.65
        let floatSamples: [Float32] = [0.0, -0.25, 0.65, -0.4, 0.1]
        let floatBuffer = try makeAudioSampleBuffer(floatSamples: floatSamples)
        let floatPeak = AudioLevelMonitor.peakAmplitude(from: floatBuffer)
        try checkEqual(floatPeak, 0.65, accuracy: 0.001)

        // 2. Float32 sample buffer exceeding 1.0 clamps to 1.0
        let clippedBuffer = try makeAudioSampleBuffer(floatSamples: [0.2, -1.8, 0.5])
        try checkEqual(AudioLevelMonitor.peakAmplitude(from: clippedBuffer), 1.0, accuracy: 0.001)

        // 3. Int16 sample buffer with half-scale amplitude
        let halfScale = Int16.max / 2
        let int16Buffer = try makeAudioSampleBuffer(int16Samples: [0, -halfScale, 100])
        let int16Peak = AudioLevelMonitor.peakAmplitude(from: int16Buffer)
        try checkEqual(int16Peak, Float(halfScale) / Float(Int16.max), accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeAudioSampleBuffer(floatSamples: [Float32]) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        return try floatSamples.withUnsafeBytes { rawBuffer in
            try makeSampleBuffer(asbd: &asbd, rawBytes: rawBuffer, frameCount: floatSamples.count)
        }
    }

    private func makeAudioSampleBuffer(int16Samples: [Int16]) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        return try int16Samples.withUnsafeBytes { rawBuffer in
            try makeSampleBuffer(asbd: &asbd, rawBytes: rawBuffer, frameCount: int16Samples.count)
        }
    }

    private func makeSampleBuffer(
        asbd: inout AudioStreamBasicDescription,
        rawBytes: UnsafeRawBufferPointer,
        frameCount: Int
    ) throws -> CMSampleBuffer {
        var formatDesc: CMAudioFormatDescription?
        let statusFD = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        try checkEqual(statusFD, noErr)
        let unwrappedFD = try unwrap(formatDesc)

        var blockBuffer: CMBlockBuffer?
        let byteLen = rawBytes.count
        let statusBB = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteLen,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteLen,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        try checkEqual(statusBB, kCMBlockBufferNoErr)
        let unwrappedBB = try unwrap(blockBuffer)

        if let baseAddress = rawBytes.baseAddress {
            let replaceStatus = CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: unwrappedBB,
                offsetIntoDestination: 0,
                dataLength: byteLen
            )
            try checkEqual(replaceStatus, kCMBlockBufferNoErr)
        }

        var sampleBuffer: CMSampleBuffer?
        let statusSB = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: unwrappedBB,
            formatDescription: unwrappedFD,
            sampleCount: frameCount,
            presentationTimeStamp: .zero,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        try checkEqual(statusSB, noErr)
        return try unwrap(sampleBuffer)
    }
}
