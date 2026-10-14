import EncoderKit
import Foundation
@testable import RecorderUI

@MainActor
final class PresetsAndLibraryTests {

    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!
    private var tempDir: URL!

    func withLifecycle(_ body: () async throws -> Void) async throws {
        suiteName = "com.macscreenrecord.tests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("MacScreenRecordTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            if let suiteName {
                isolatedDefaults?.removePersistentDomain(forName: suiteName)
            }
            if let tempDir {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
        try await body()
    }

    func testPresetCodableAndLegacyRawEnumFallback() throws {
        let original = Preset(
            name: "Studio Tutorial",
            sourceKindRaw: "Display",
            codec: .hevc,
            fps: 60,
            showsCursor: true,
            captureSystemAudio: true,
            captureMicrophone: true,
            customWidth: 1920,
            customHeight: 1080,
            webcamEnabled: true,
            useForFacecam: true,
            clickHighlightsEnabled: true,
            keystrokesEnabled: true,
            webcamCorner: .bottomLeft,
            webcamSize: .large,
            webcamBackgroundMode: .blur
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        try checkEqual(decoded, original)

        // Verify backward-compatible decoding when only legacy *Raw keys are present
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy Preset",
          "sourceKindRaw": "Display",
          "codec": "h264",
          "fps": 30,
          "showsCursor": true,
          "captureSystemAudio": false,
          "captureMicrophone": true,
          "webcamEnabled": true,
          "webcamCornerRaw": "topRight",
          "webcamSizeRaw": "small",
          "webcamBackgroundModeRaw": "cutout"
        }
        """.data(using: .utf8)!

        let fromLegacy = try JSONDecoder().decode(Preset.self, from: legacyJSON)
        try checkEqual(fromLegacy.webcamCorner, .topRight)
        try checkEqual(fromLegacy.webcamSize, .small)
        try checkEqual(fromLegacy.webcamBackgroundMode, .cutout)
    }

    func testPresetsStoreFacecamNormalizationAndDefaultLifecycle() throws {
        let store = PresetsStore(defaults: isolatedDefaults)
        try checkTrue(store.presets.isEmpty)

        // 1. Adding the first PIP preset auto-designates it as useForFacecam
        let p1 = Preset(
            name: "PiP One",
            sourceKindRaw: "Display",
            codec: .h264,
            fps: 60,
            showsCursor: true,
            captureSystemAudio: true,
            captureMicrophone: true,
            customWidth: nil,
            customHeight: nil,
            webcamEnabled: true,
            useForFacecam: false
        )
        store.add(p1)
        try checkEqual(store.presets.count, 1)
        try checkTrue(store.presets[0].useForFacecam)
        try checkEqual(store.facecamPreset?.id, p1.id)

        // 2. Adding a second PIP preset explicitly marked useForFacecam clears the first
        let p2 = Preset(
            name: "PiP Two",
            sourceKindRaw: "Display",
            codec: .hevc,
            fps: 60,
            showsCursor: true,
            captureSystemAudio: true,
            captureMicrophone: true,
            customWidth: nil,
            customHeight: nil,
            webcamEnabled: true,
            useForFacecam: true
        )
        store.add(p2)
        try checkEqual(store.facecamPreset?.id, p2.id)
        try checkEqual(store.presets.filter(\.useForFacecam).count, 1)

        // 3. Setting default preset and deleting p2 clears default and auto-promotes remaining p1 back to facecam
        store.setDefault(id: p2.id)
        try checkEqual(store.defaultPreset?.id, p2.id)
        store.delete(id: p2.id)
        try checkNil(store.defaultPresetID)
        try checkEqual(store.facecamPreset?.id, p1.id)
    }

    func testPresetsStoreLegacyMigration() throws {
        let preset = Preset(
            name: "Migrated Profile",
            sourceKindRaw: "Display",
            codec: .h264,
            fps: 60,
            showsCursor: true,
            captureSystemAudio: true,
            captureMicrophone: false,
            customWidth: nil,
            customHeight: nil
        )
        let encoded = try JSONEncoder().encode([preset])
        isolatedDefaults.set(encoded, forKey: "FreeMacScreenRecorder.presets.v1")
        isolatedDefaults.set(preset.id.uuidString, forKey: "FreeMacScreenRecorder.defaultPresetID.v1")

        let store = PresetsStore(defaults: isolatedDefaults)
        try checkEqual(store.presets.count, 1)
        try checkEqual(store.defaultPresetID, preset.id)

        // Legacy keys should be cleaned up and migrated to MacScreenRecord.* keys
        try checkNil(isolatedDefaults.data(forKey: "FreeMacScreenRecorder.presets.v1"))
        try checkNil(isolatedDefaults.string(forKey: "FreeMacScreenRecorder.defaultPresetID.v1"))
        try checkNotNil(isolatedDefaults.data(forKey: "MacScreenRecord.presets.v1"))
        try checkEqual(isolatedDefaults.string(forKey: "MacScreenRecord.defaultPresetID.v1"), preset.id.uuidString)
    }

    func testRecordingFileFormattingAndLibraryOperations() async throws {
        let fileURL = tempDir.appendingPathComponent("capture.mp4")
        try Data("fake-mp4-bytes".utf8).write(to: fileURL)

        // Create associated partial sidecar and an unrelated recording
        let partialURL = tempDir.appendingPathComponent("capture-partial.tmp")
        try Data("partial".utf8).write(to: partialURL)
        let otherURL = tempDir.appendingPathComponent("other.mov")
        try Data("other-mov".utf8).write(to: otherURL)

        let recFile = RecordingFile(
            url: fileURL,
            name: "capture.mp4",
            createdAt: Date(),
            sizeBytes: 1_048_576,
            duration: 3665
        )
        try checkEqual(recFile.formattedDuration, "01:01:05")
        try checkFalse(recFile.formattedSize.isEmpty)

        let nilDurationFile = RecordingFile(
            url: fileURL, name: "capture.mp4", createdAt: Date(), sizeBytes: 100, duration: nil
        )
        try checkEqual(nilDurationFile.formattedDuration, "—")

        let library = RecordingsLibrary(folder: tempDir)
        await library.reload()
        try checkEqual(library.files.count, 2)

        // Rename validation checks
        let targetEntry = try unwrap(library.files.first(where: { $0.name == "other.mov" }))
        try await checkThrowsAsyncError({ try await library.rename(targetEntry, to: "   ") }) { error in
            try checkEqual(error as? RecordingsLibrary.RenameError, .emptyName)
        }
        try await checkThrowsAsyncError({ try await library.rename(targetEntry, to: ".hidden") }) { error in
            try checkEqual(error as? RecordingsLibrary.RenameError, .leadingDot)
        }
        try await checkThrowsAsyncError({ try await library.rename(targetEntry, to: "bad/name") }) { error in
            try checkEqual(error as? RecordingsLibrary.RenameError, .invalidCharacters)
        }

        // Valid rename
        try await library.rename(targetEntry, to: "renamed-clip")
        try checkTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("renamed-clip.mov").path))

        // Delete primary recording and verify associated -partial.tmp sidecar is removed while renamed-clip.mov remains
        let captureEntry = try unwrap(library.files.first(where: { $0.name == "capture.mp4" }))
        let err = library.delete(captureEntry, moveToTrash: false)
        try checkNil(err)
        try checkFalse(FileManager.default.fileExists(atPath: fileURL.path))
        try checkFalse(FileManager.default.fileExists(atPath: partialURL.path))
        try checkTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("renamed-clip.mov").path))
    }
}
