import AppKit
import Combine
import EncoderKit
import Foundation

/// User preferences persisted to `UserDefaults`. Read once at init, written
/// on every change via Combine.
@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private struct Keys {
        static let codec = "FMSR.defaults.codec"
        static let fps = "FMSR.defaults.fps"
        static let cursor = "FMSR.defaults.cursor"
        static let systemAudio = "FMSR.defaults.systemAudio"
        static let folderPath = "FMSR.defaults.outputFolderPath"
    }

    @Published public var defaultCodec: OutputCodec {
        didSet { UserDefaults.standard.set(defaultCodec.rawValue, forKey: Keys.codec) }
    }
    @Published public var defaultFPS: Int {
        didSet { UserDefaults.standard.set(defaultFPS, forKey: Keys.fps) }
    }
    @Published public var defaultShowsCursor: Bool {
        didSet { UserDefaults.standard.set(defaultShowsCursor, forKey: Keys.cursor) }
    }
    @Published public var defaultCaptureSystemAudio: Bool {
        didSet { UserDefaults.standard.set(defaultCaptureSystemAudio, forKey: Keys.systemAudio) }
    }
    @Published public var outputFolder: URL {
        didSet { UserDefaults.standard.set(outputFolder.path, forKey: Keys.folderPath) }
    }

    public init() {
        let d = UserDefaults.standard
        self.defaultCodec = OutputCodec(rawValue: d.string(forKey: Keys.codec) ?? "") ?? .h264
        let storedFPS = d.integer(forKey: Keys.fps)
        self.defaultFPS = storedFPS == 0 ? 60 : min(max(storedFPS, 24), 120)
        // Provide explicit default so missing key isn't read as `false`.
        self.defaultShowsCursor = d.object(forKey: Keys.cursor) as? Bool ?? true
        self.defaultCaptureSystemAudio = d.object(forKey: Keys.systemAudio) as? Bool ?? true

        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser
        let fallback = movies.appendingPathComponent("Mac Screen Record", isDirectory: true)
        if let stored = d.string(forKey: Keys.folderPath), !stored.isEmpty {
            let storedURL = URL(fileURLWithPath: stored, isDirectory: true)
            let legacyFallback = movies.appendingPathComponent("Free Mac Screen Recorder", isDirectory: true)
            // If stored path points to legacy default and no files are there, migrate to new default
            if storedURL.path == legacyFallback.path && !FileManager.default.fileExists(atPath: storedURL.path) {
                self.outputFolder = fallback
            } else if Self.isLocalNonUbiquitous(storedURL) {
                self.outputFolder = storedURL
            } else {
                self.outputFolder = fallback
            }
        } else {
            self.outputFolder = fallback
        }
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    }

    public static func isLocalNonUbiquitous(_ url: URL) -> Bool {
        let checkURL = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        guard let values = try? checkURL.resourceValues(forKeys: [.volumeIsLocalKey, .isUbiquitousItemKey]) else {
            return false
        }
        let isLocal = values.volumeIsLocal ?? false
        let isUbiquitous = values.isUbiquitousItem ?? false
        let path = url.path
        if path.contains("/Library/Mobile Documents/") || path.contains("/Library/CloudStorage/") {
            return false
        }
        return isLocal && !isUbiquitous
    }

    public func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputFolder
        panel.message = "Choose where Mac Screen Record saves records (local drive required)"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            if Self.isLocalNonUbiquitous(url) {
                outputFolder = url
            } else {
                NSSound.beep()
            }
        }
    }
}
