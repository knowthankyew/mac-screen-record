import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import OSLog

/// Converts a recorded video file into an animated `.gif` using
/// `AVAssetImageGenerator` to extract frames and `CGImageDestination` to write
/// them. The result is always looped infinitely.
public enum GIFExporter {
    public struct Options: Sendable {
        public var fps: Int = 12
        public var maxWidth: Int = 600
        public var loops: Int = 0          // 0 = forever
        public init(fps: Int = 12, maxWidth: Int = 600, loops: Int = 0) {
            self.fps = max(1, min(fps, 60))
            self.maxWidth = max(100, maxWidth)
            self.loops = max(0, loops)
        }
    }

    public enum ExportError: Error, LocalizedError {
        case invalidSource
        case generatorFailed(String)
        case destinationCreationFailed
        case finalizeFailed
        public var errorDescription: String? {
            switch self {
            case .invalidSource:               return "Could not read the source video"
            case .generatorFailed(let msg):    return "Frame extraction failed: \(msg)"
            case .destinationCreationFailed:   return "Couldn't create the GIF file"
            case .finalizeFailed:              return "GIF could not be written"
            }
        }
    }

    public static func export(
        source: URL,
        destination: URL,
        options: Options = Options()
    ) async throws {
        let log = Logger(subsystem: "com.macscreenrecord.app", category: "GIFExporter")
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else {
            throw ExportError.invalidSource
        }

        let totalSeconds = duration.seconds
        let maxFrames = 600
        let frameCount = min(maxFrames, max(1, Int(totalSeconds * Double(options.fps))))
        let interval = totalSeconds / Double(frameCount)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: options.maxWidth, height: 0)

        let tempDest = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp.gif")
        defer {
            try? FileManager.default.removeItem(at: tempDest)
        }

        guard let dest = CGImageDestinationCreateWithURL(
            tempDest as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw ExportError.destinationCreationFailed
        }

        let gifProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: options.loops
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

        let frameProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: interval,
                kCGImagePropertyGIFUnclampedDelayTime as String: interval,
            ]
        ]

        for i in 0..<frameCount {
            let t = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            do {
                let cg = try await generator.image(at: t).image
                CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
            } catch {
                log.error("Frame \(i, privacy: .public) extraction failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.finalizeFailed
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempDest)
        } else {
            try FileManager.default.moveItem(at: tempDest, to: destination)
        }

        log.info("GIF written: \(destination.path, privacy: .public) (\(frameCount, privacy: .public) frames)")
    }
}
