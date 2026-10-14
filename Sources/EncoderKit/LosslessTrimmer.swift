@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Lossless media trimming engine using native `AVAssetExportPresetPassthrough`.
/// Performs sub-second, frame-accurate cuts on supported container bitstreams
/// (H.264, HEVC, ProRes) with zero re-encoding and zero quality degradation.
public enum LosslessTrimmer {

    private static let log = Logger(subsystem: "com.macscreenrecord.app", category: "LosslessTrimmer")

    /// File extensions supported by AVFoundation for passthrough export.
    public static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Returns `true` if the given file URL has a supported video extension.
    public static func isSupported(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Error types encountered during lossless trimming operations.
    public enum TrimError: Error, LocalizedError, Equatable {
        case fileNotFound(URL)
        case unsupportedFormat(String)
        case invalidAssetDuration
        case invalidTimeRange(start: Double, end: Double, duration: Double)
        case exportSessionCreationFailed
        case exportFailed(String)
        case exportCancelled

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "Video file not found at \(url.lastPathComponent)."
            case .unsupportedFormat(let ext):
                return "The format '.\(ext)' is not supported for lossless passthrough trimming. Supported: mp4, mov, m4v."
            case .invalidAssetDuration:
                return "Could not determine a valid duration for the video."
            case .invalidTimeRange(let start, let end, let duration):
                return String(format: "Invalid trim range (%.2fs – %.2fs) for asset duration of %.2fs.", start, end, duration)
            case .exportSessionCreationFailed:
                return "Could not initialize passthrough export session."
            case .exportFailed(let reason):
                return "Lossless export failed: \(reason)"
            case .exportCancelled:
                return "Trimming was cancelled."
            }
        }
    }

    /// Generates a standardized destination URL for a trimmed copy beside the source file.
    /// E.g. `Recording.mp4` -> `Recording_trimmed.mp4`.
    /// Automatically handles filename collisions by appending numeric counter `_trimmed (2).mp4`.
    public static func defaultTrimmedURL(for source: URL) -> URL {
        let parent = source.deletingLastPathComponent()
        let ext = source.pathExtension
        let baseName = source.deletingPathExtension().lastPathComponent

        let makeName = { (suffix: String) -> String in
            ext.isEmpty ? "\(baseName)\(suffix)" : "\(baseName)\(suffix).\(ext)"
        }

        var dest = parent.appendingPathComponent(makeName("_trimmed"))
        var counter = 2
        let fm = FileManager.default
        while fm.fileExists(atPath: dest.path) {
            dest = parent.appendingPathComponent(makeName("_trimmed (\(counter))"))
            counter += 1
        }
        return dest
    }

    /// Loads the duration of a video asset in seconds.
    public static func loadDuration(for source: URL) async throws -> Double {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw TrimError.fileNotFound(source)
        }
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0, duration.seconds.isFinite else {
            throw TrimError.invalidAssetDuration
        }
        return duration.seconds
    }

    /// Extracts `count` evenly-spaced frame thumbnails across the video's timeline for filmstrip display.
    public static func generateThumbnails(
        for source: URL,
        count: Int = 10,
        maxDimension: CGFloat = 160
    ) async throws -> [CGImage] {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw TrimError.fileNotFound(source)
        }
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0, duration.seconds.isFinite else {
            throw TrimError.invalidAssetDuration
        }

        let totalSecs = duration.seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let safeCount = max(2, min(count, 32))
        var images: [CGImage] = []
        let step = totalSecs / Double(safeCount)

        for i in 0..<safeCount {
            if Task.isCancelled { break }
            let targetSecs = min(totalSecs, Double(i) * step + (step / 2.0))
            let time = CMTime(seconds: targetSecs, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                images.append(cgImage)
            } catch {
                log.debug("Failed extracting thumbnail at \(targetSecs, privacy: .public)s: \(error.localizedDescription, privacy: .public)")
            }
        }
        return images
    }

    /// Trims a source video to the specified start and end timestamps using `AVAssetExportPresetPassthrough`.
    /// Preserves original bitstream encoding with zero generational loss.
    @discardableResult
    public static func trim(
        source: URL,
        destination: URL,
        startTime: Double,
        endTime: Double
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw TrimError.fileNotFound(source)
        }
        let ext = source.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw TrimError.unsupportedFormat(ext)
        }

        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0, duration.seconds.isFinite else {
            throw TrimError.invalidAssetDuration
        }

        let totalSecs = duration.seconds
        let minTrimDuration = 0.05
        guard startTime >= 0,
              endTime <= (totalSecs + 0.1),
              (endTime - startTime) >= minTrimDuration else {
            throw TrimError.invalidTimeRange(start: startTime, end: endTime, duration: totalSecs)
        }

        let clampedEnd = min(endTime, totalSecs)
        let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
        let durationCM = CMTime(seconds: clampedEnd - startTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCM, duration: durationCM)

        let fileType: AVFileType
        switch destination.pathExtension.lowercased() {
        case "mov": fileType = .mov
        case "m4v": fileType = .m4v
        default:    fileType = .mp4
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw TrimError.exportSessionCreationFailed
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = fileType
        exportSession.timeRange = timeRange

        let destDir = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        log.info("Starting passthrough trim: \(source.lastPathComponent, privacy: .public) [\(startTime, privacy: .public)s – \(clampedEnd, privacy: .public)s] -> \(destination.lastPathComponent, privacy: .public)")

        let box = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously { [weak box] in
                guard let session = box?.session else {
                    continuation.resume(throwing: TrimError.exportCancelled)
                    return
                }
                switch session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    let reason = session.error?.localizedDescription ?? "Unknown passthrough export failure"
                    continuation.resume(throwing: TrimError.exportFailed(reason))
                case .cancelled:
                    continuation.resume(throwing: TrimError.exportCancelled)
                default:
                    continuation.resume(throwing: TrimError.exportFailed("Export finished with unexpected status \(session.status.rawValue)"))
                }
            }
        }

        log.info("Passthrough trim completed successfully: \(destination.lastPathComponent, privacy: .public)")
        return destination
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
