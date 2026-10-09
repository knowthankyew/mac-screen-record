import AVFoundation
import AppKit
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

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Point the library at a new folder (e.g. when the user changes the
    /// output destination in Settings) and reload the file list.
    public func relocate(to newFolder: URL) {
        guard newFolder != folder else { return }
        try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        folder = newFolder
        Task { await reload() }
    }

    public func reload() async {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            files = []
            return
        }
        let supportedExts: Set<String> = ["mp4", "mov", "m4v", "gif"]
        let candidates = items.filter { supportedExts.contains($0.pathExtension.lowercased()) }

        // Lightweight metadata first so the list renders immediately.
        let initial = candidates.map { url -> RecordingFile in
            let attrs = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            return RecordingFile(
                url: url,
                name: url.lastPathComponent,
                createdAt: attrs?.creationDate ?? Date.distantPast,
                sizeBytes: Int64(attrs?.fileSize ?? 0),
                duration: nil
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
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
                if let idx = files.firstIndex(where: { $0.url == url }) {
                    let f = files[idx]
                    files[idx] = RecordingFile(
                        url: f.url, name: f.name, createdAt: f.createdAt,
                        sizeBytes: f.sizeBytes, duration: secs
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
    public func delete(_ file: RecordingFile, moveToTrash: Bool = true) {
        deleteArtifacts(at: file.url, moveToTrash: moveToTrash)
    }

    /// Deletes the primary recording file and any matching sidecars or partial fragments.
    public func deleteArtifacts(at url: URL, moveToTrash: Bool = true) {
        let fm = FileManager.default
        var primaryDeleted = false
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
                log.error("Failed to delete recording at \(url.path): \(error.localizedDescription, privacy: .public)")
            }
        } else {
            primaryDeleted = true
        }

        // Clean up only known partial fragment and temporary sidecars with exact baseName matching
        let dir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let knownArtifactSuffixes = ["-partial", "-fragment", ".tmp", ".part"]
        if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in contents where item != url {
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
                    log.error("Failed to delete artifact at \(item.path): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if primaryDeleted {
            files.removeAll { $0.url == url }
        }
    }

    /// Rename a recording on disk (preserves extension) and refresh the entry.
    public func rename(_ file: RecordingFile, to newBaseName: String) throws {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              trimmed != ".",
              trimmed != ".." else { return }

        let ext = file.url.pathExtension
        let parent = file.url.deletingLastPathComponent()
        let targetName = ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
        if targetName == file.url.lastPathComponent {
            return
        }

        var dest = parent.appendingPathComponent(trimmed).appendingPathExtension(ext)
        // If a name collision exists, append a numeric suffix.
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) && dest != file.url {
            dest = parent.appendingPathComponent("\(trimmed) (\(counter))").appendingPathExtension(ext)
            counter += 1
        }
        try FileManager.default.moveItem(at: file.url, to: dest)
        if let i = files.firstIndex(where: { $0.url == file.url }) {
            files[i] = RecordingFile(
                url: dest, name: dest.lastPathComponent, createdAt: file.createdAt,
                sizeBytes: file.sizeBytes, duration: file.duration
            )
        }
    }

    /// Export a recording as an animated GIF beside the source file.
    @discardableResult
    public func exportGIF(_ file: RecordingFile, options: GIFExporter.Options = .init()) async throws -> URL {
        let dest = file.url.deletingPathExtension().appendingPathExtension("gif")
        try await GIFExporter.export(source: file.url, destination: dest, options: options)
        await reload()
        return dest
    }
}
