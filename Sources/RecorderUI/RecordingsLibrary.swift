import AVFoundation
import AppKit
import CaptureCore
import Combine
import EncoderKit
import Foundation
import OSLog

public struct RecordingFile: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let createdAt: Date
    public let sizeBytes: Int64
    public let duration: Double?       // seconds, nil if not yet known
    public let hasEvidenceSeal: Bool

    public init(
        url: URL,
        name: String,
        createdAt: Date,
        sizeBytes: Int64,
        duration: Double?,
        hasEvidenceSeal: Bool = false
    ) {
        self.url = url
        self.name = name
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.duration = duration
        self.hasEvidenceSeal = hasEvidenceSeal
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var formattedDuration: String {
        guard let d = duration, d.isFinite, d > 0 else { return "—" }
        let total = Int(d)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

@MainActor
public final class RecordingsLibrary: ObservableObject {
    @Published public private(set) var files: [RecordingFile] = []
    @Published public private(set) var folder: URL

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "RecordingsLibrary")
    private var reloadTask: Task<Void, Never>?
    private static let supportedExts: Set<String> = ["mp4", "mov", "m4v", "gif"]

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Point the library at a new folder (e.g. when the user changes the
    /// output destination in Settings) and reload the file list.
    public func relocate(to newFolder: URL) {
        guard newFolder != folder else { return }
        reloadTask?.cancel()
        try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        folder = newFolder
        files = []
        reloadTask = Task { [weak self] in
            await self?.reload()
        }
    }

    public func reload() async {
        let targetFolder = folder
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: targetFolder,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            if folder == targetFolder { files = [] }
            return
        }
        let candidates = items.filter { Self.supportedExts.contains($0.pathExtension.lowercased()) }

        // Lightweight metadata first so the list renders immediately.
        let initial = candidates.map { url -> RecordingFile in
            let attrs = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let evidenceURL = EvidenceSeal.manifestURL(for: url)
            let hasSeal = fm.fileExists(atPath: evidenceURL.path)
            return RecordingFile(
                url: url,
                name: url.lastPathComponent,
                createdAt: attrs?.creationDate ?? Date.distantPast,
                sizeBytes: Int64(attrs?.fileSize ?? 0),
                duration: nil,
                hasEvidenceSeal: hasSeal
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
        guard !Task.isCancelled, folder == targetFolder else { return }
        files = initial

        // Then load durations asynchronously and merge in.
        await withTaskGroup(of: (URL, Double?).self) { group in
            for f in initial {
                group.addTask {
                    if f.url.pathExtension.lowercased() == "gif" {
                        return (f.url, nil)
                    }
                    let asset = AVURLAsset(url: f.url)
                    let dur = try? await asset.load(.duration)
                    return (f.url, dur.map { CMTimeGetSeconds($0) })
                }
            }
            for await (url, secs) in group {
                guard !Task.isCancelled, folder == targetFolder else { return }
                if let idx = files.firstIndex(where: { $0.url == url }) {
                    let f = files[idx]
                    files[idx] = RecordingFile(
                        url: f.url, name: f.name, createdAt: f.createdAt,
                        sizeBytes: f.sizeBytes, duration: secs,
                        hasEvidenceSeal: f.hasEvidenceSeal
                    )
                }
            }
        }
    }

    public func revealInFinder(_ file: RecordingFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    public func open(_ file: RecordingFile) {
        NSWorkspace.shared.open(file.url)
    }

    /// Deletes a recording entry from the library. Alias for `deleteArtifacts(at:moveToTrash:)`.
    @discardableResult
    public func delete(_ file: RecordingFile, moveToTrash: Bool = true) -> Error? {
        deleteArtifacts(at: file.url, moveToTrash: moveToTrash)
    }

    /// Deletes the primary recording file and any matching sidecars or partial fragments.
    @discardableResult
    public func deleteArtifacts(at url: URL, moveToTrash: Bool = true) -> Error? {
        let fm = FileManager.default
        var primaryDeleted = false
        var primaryError: Error? = nil
        if fm.fileExists(atPath: url.path) {
            do {
                if moveToTrash {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    log.info("Moved recording to trash: \(url.lastPathComponent, privacy: .public)")
                } else {
                    try fm.removeItem(at: url)
                    log.info("Permanently deleted recording: \(url.lastPathComponent, privacy: .public)")
                }
                primaryDeleted = true
            } catch {
                primaryError = error
                log.error("Failed to delete recording at \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        } else {
            primaryDeleted = true
        }

        // Clean up companion evidence seal if present
        let evidenceURL = EvidenceSeal.manifestURL(for: url)
        if fm.fileExists(atPath: evidenceURL.path) {
            do {
                if moveToTrash {
                    try fm.trashItem(at: evidenceURL, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: evidenceURL)
                }
                log.info("Deleted companion evidence seal: \(evidenceURL.lastPathComponent, privacy: .public)")
            } catch {
                log.error("Failed to delete companion evidence seal at \(evidenceURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Clean up only known partial fragment and temporary sidecars with exact baseName matching
        let dir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let knownArtifactSuffixes = ["-partial", "-fragment", ".tmp", ".part"]
        let targetStdURL = url.standardizedFileURL
        if primaryDeleted, let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in contents where item.standardizedFileURL != targetStdURL {
                if Self.supportedExts.contains(item.pathExtension.lowercased()) { continue }
                let itemName = item.lastPathComponent
                let itemBase = item.deletingPathExtension().lastPathComponent
                let isAssociatedArtifact = knownArtifactSuffixes.contains { suffix in
                    itemBase == (baseName + suffix) || itemName == (baseName + suffix)
                }
                guard isAssociatedArtifact else { continue }
                do {
                    if moveToTrash {
                        try fm.trashItem(at: item, resultingItemURL: nil)
                    } else {
                        try fm.removeItem(at: item)
                    }
                    log.info("Deleted associated artifact: \(item.lastPathComponent, privacy: .public)")
                } catch {
                    log.error("Failed to delete artifact at \(item.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if primaryDeleted {
            files.removeAll { $0.url.standardizedFileURL == targetStdURL }
        }
        return primaryError
    }

    public enum RenameError: LocalizedError {
        case emptyName
        case leadingDot
        case invalidCharacters

        public var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Recording name cannot be empty."
            case .leadingDot:
                return "Recording name cannot start with a period ('.'), as macOS hides dot-files."
            case .invalidCharacters:
                return "Recording name cannot contain path separators ('/' or '\\')."
            }
        }
    }

    /// Rename a recording on disk (preserves extension) and refresh the entry.
    public func rename(_ file: RecordingFile, to newBaseName: String) throws {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RenameError.emptyName }
        guard !trimmed.hasPrefix(".") else { throw RenameError.leadingDot }
        guard !trimmed.contains("/") && !trimmed.contains("\\") else { throw RenameError.invalidCharacters }

        let ext = file.url.pathExtension
        let parent = file.url.deletingLastPathComponent()
        let makeFileName = { (stem: String) -> String in
            ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        let targetName = makeFileName(trimmed)
        if targetName == file.url.lastPathComponent {
            return
        }

        var dest = parent.appendingPathComponent(targetName)
        let isCaseOnlyRename = targetName.lowercased() == file.url.lastPathComponent.lowercased()
        // If a name collision exists with a different file, append a numeric suffix.
        if !isCaseOnlyRename {
            var counter = 2
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = parent.appendingPathComponent(makeFileName("\(trimmed) (\(counter))"))
                counter += 1
            }
        }
        try FileManager.default.moveItem(at: file.url, to: dest)
        let sourceStdURL = file.url.standardizedFileURL

        // Rename companion evidence manifest if present and update its internal fileName
        let oldEvidenceURL = EvidenceSeal.manifestURL(for: file.url)
        let newEvidenceURL = EvidenceSeal.manifestURL(for: dest)
        var hasEvidenceSeal = false
        if FileManager.default.fileExists(atPath: oldEvidenceURL.path) {
            do {
                try FileManager.default.moveItem(at: oldEvidenceURL, to: newEvidenceURL)
                hasEvidenceSeal = true
                if let data = try? Data(contentsOf: newEvidenceURL),
                   let oldManifest = try? JSONDecoder().decode(EvidenceManifest.self, from: data) {
                    let updated = EvidenceManifest(
                        schema: oldManifest.schema,
                        mediaFile: EvidenceManifest.MediaFile(
                            fileName: dest.lastPathComponent,
                            fileSizeBytes: oldManifest.mediaFile.fileSizeBytes,
                            sha256: oldManifest.mediaFile.sha256,
                            sha512: oldManifest.mediaFile.sha512
                        ),
                        temporalIntegrity: oldManifest.temporalIntegrity,
                        captureContext: oldManifest.captureContext,
                        audioTelemetry: oldManifest.audioTelemetry,
                        presenterAndOverlays: oldManifest.presenterAndOverlays,
                        provenanceAndGovernance: oldManifest.provenanceAndGovernance
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    if let updatedData = try? encoder.encode(updated) {
                        try? updatedData.write(to: newEvidenceURL, options: .atomic)
                    }
                }
                log.info("Renamed companion evidence seal to \(newEvidenceURL.lastPathComponent, privacy: .public)")
            } catch {
                log.error("Failed to rename companion evidence seal: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            hasEvidenceSeal = FileManager.default.fileExists(atPath: newEvidenceURL.path)
        }

        if let i = files.firstIndex(where: { $0.url.standardizedFileURL == sourceStdURL }) {
            files[i] = RecordingFile(
                url: dest, name: dest.lastPathComponent, createdAt: file.createdAt,
                sizeBytes: file.sizeBytes, duration: file.duration,
                hasEvidenceSeal: hasEvidenceSeal
            )
        }
    }

    /// Export a recording as an animated GIF beside the source file.
    @discardableResult
    public func exportGIF(_ file: RecordingFile, options: GIFExporter.Options = .init()) async throws -> URL {
        let parent = file.url.deletingLastPathComponent()
        let baseName = file.url.deletingPathExtension().lastPathComponent
        var dest = parent.appendingPathComponent(baseName).appendingPathExtension("gif")
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = parent.appendingPathComponent("\(baseName) (\(counter))").appendingPathExtension("gif")
            counter += 1
        }
        try await GIFExporter.export(source: file.url, destination: dest, options: options)
        await reload()
        return dest
    }

    /// Reads and decodes the companion evidence manifest for a recording if present.
    public func manifest(for file: RecordingFile) -> EvidenceManifest? {
        let manifestURL = EvidenceSeal.manifestURL(for: file.url)
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(EvidenceManifest.self, from: data)
    }

    /// Returns the SHA-256 hex digest string from the companion evidence manifest if present.
    public func sha256Hex(for file: RecordingFile) -> String? {
        manifest(for: file)?.mediaFile.sha256
    }
}
