import Combine
import Foundation

/// Manages a persistent list of recent recording and trimmed video URLs.
/// Strict Invariant: Ghost entries are never returned — all entries are dynamically verified
/// against disk existence on every access and pruned from persistence if removed from disk.
@MainActor
public final class RecentRecordingsStore: ObservableObject {
    public static let maxRecentsCount = 10
    private static let userDefaultsKey = "com.macscreenrecord.recentRecordings"

    private let defaults: UserDefaults
    private let fileManager: FileManager

    @Published public private(set) var recents: [URL] = []

    /// Dynamically verified list of recents present on disk at this exact instant.
    /// Guarantees that ghost entries for files moved or deleted outside the application are never exposed.
    public var existingRecents: [URL] {
        recents.filter { fileManager.fileExists(atPath: $0.path) }
    }

    public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.recents = loadAndPrune()
    }

    /// Appends or moves a URL to the top of the recent recordings list, persisting only if valid and present on disk.
    public func addRecent(url: URL) {
        let normalized = url.standardizedFileURL
        guard fileManager.fileExists(atPath: normalized.path) else { return }

        var current = loadAndPrune()
        current.removeAll { $0.standardizedFileURL == normalized }
        current.insert(normalized, at: 0)
        if current.count > Self.maxRecentsCount {
            current = Array(current.prefix(Self.maxRecentsCount))
        }
        save(current)
        self.recents = current
    }

    /// Removes a URL from the recents list.
    public func remove(url: URL) {
        let normalized = url.standardizedFileURL
        var current = loadAndPrune()
        current.removeAll { $0.standardizedFileURL == normalized }
        save(current)
        self.recents = current
    }

    /// Clears all recent recordings.
    public func clear() {
        save([])
        self.recents = []
    }

    /// Refreshes the recents list, dynamically pruning any entries no longer present on disk.
    public func refresh() {
        self.recents = loadAndPrune()
    }

    private func loadAndPrune() -> [URL] {
        guard let savedPaths = defaults.stringArray(forKey: Self.userDefaultsKey) else {
            return []
        }
        var validURLs: [URL] = []
        var needsSave = false

        for path in savedPaths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if fileManager.fileExists(atPath: url.path) {
                if !validURLs.contains(where: { $0.standardizedFileURL == url }) {
                    validURLs.append(url)
                }
            } else {
                needsSave = true
            }
        }

        if needsSave || validURLs.count != savedPaths.count {
            save(validURLs)
        }
        return validURLs
    }

    private func save(_ urls: [URL]) {
        let paths = urls.map { $0.standardizedFileURL.path }
        defaults.set(paths, forKey: Self.userDefaultsKey)
    }
}
