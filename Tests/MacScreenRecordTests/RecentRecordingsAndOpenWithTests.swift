import AVFoundation
import CaptureCore
import EncoderKit
import Foundation
@testable import RecorderUI

@MainActor
final class RecentRecordingsAndOpenWithTests {

    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!
    private var tempDir: URL!

    func withLifecycle(_ body: () async throws -> Void) async throws {
        suiteName = "com.macscreenrecord.tests.recents.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recents_tests_\(UUID().uuidString)", isDirectory: true)
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

    private func createTempFile(name: String) throws -> URL {
        let fileURL = tempDir.appendingPathComponent(name)
        try "dummy video content".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Verifies MRU ordering, deduplication, and moving re-added files to index 0.
    func testRecentsStoreMRUOrderingAndDeduplication() throws {
        let store = RecentRecordingsStore(defaults: isolatedDefaults)
        let file1 = try createTempFile(name: "video1.mp4")
        let file2 = try createTempFile(name: "video2.mov")
        let file3 = try createTempFile(name: "video3.m4v")

        store.addRecent(url: file1)
        store.addRecent(url: file2)
        store.addRecent(url: file3)

        try checkEqual(store.recents.count, 3, "All 3 files added to recents")
        try checkEqual(store.recents[0].standardizedFileURL, file3.standardizedFileURL, "file3 is top of recents")
        try checkEqual(store.recents[1].standardizedFileURL, file2.standardizedFileURL, "file2 is second")
        try checkEqual(store.recents[2].standardizedFileURL, file1.standardizedFileURL, "file1 is third")

        // Re-add file1; should move to index 0 with no duplicates
        store.addRecent(url: file1)
        try checkEqual(store.recents.count, 3, "Count unchanged after re-adding existing file")
        try checkEqual(store.recents[0].standardizedFileURL, file1.standardizedFileURL, "file1 promoted to top")
        try checkEqual(store.recents[1].standardizedFileURL, file3.standardizedFileURL, "file3 shifted to second")
        try checkEqual(store.recents[2].standardizedFileURL, file2.standardizedFileURL, "file2 shifted to third")
    }

    /// Verifies that recents list strictly caps at maxRecentsCount (10).
    func testRecentsStoreMaxCapacityCap() throws {
        let store = RecentRecordingsStore(defaults: isolatedDefaults)
        var files: [URL] = []
        for i in 1...12 {
            files.append(try createTempFile(name: "clip_\(i).mp4"))
        }

        for file in files {
            store.addRecent(url: file)
        }

        try checkEqual(store.recents.count, RecentRecordingsStore.maxRecentsCount, "Count is capped at maxRecentsCount (10)")
        try checkEqual(store.recents[0].standardizedFileURL, files[11].standardizedFileURL, "Most recently added is at index 0")
        try checkEqual(store.recents[9].standardizedFileURL, files[2].standardizedFileURL, "Tenth item is file 3")
        try checkFalse(store.recents.contains(where: { $0.standardizedFileURL == files[0].standardizedFileURL }), "Oldest files dropped")
        try checkFalse(store.recents.contains(where: { $0.standardizedFileURL == files[1].standardizedFileURL }), "Oldest files dropped")
    }

    /// Verifies strict zero-ghost invariant: deleted files on disk are immediately omitted by existingRecents
    /// and pruned from persistence on refresh.
    func testZeroGhostInvariantOnDiskDeletion() throws {
        let store = RecentRecordingsStore(defaults: isolatedDefaults)
        let file1 = try createTempFile(name: "keep.mp4")
        let file2 = try createTempFile(name: "delete_me.mov")

        store.addRecent(url: file1)
        store.addRecent(url: file2)
        try checkEqual(store.existingRecents.count, 2, "Both files exist initially")

        // Delete file2 from disk externally
        try FileManager.default.removeItem(at: file2)

        // existingRecents must NEVER return a ghost file even before refresh() is called
        try checkEqual(store.existingRecents.count, 1, "Ghost file immediately excluded from existingRecents")
        try checkEqual(store.existingRecents[0].standardizedFileURL, file1.standardizedFileURL, "Only living file returned")

        // refresh() synchronizes in-memory recents and persistence
        store.refresh()
        try checkEqual(store.recents.count, 1, "recents pruned after refresh")
        try checkEqual(store.recents[0].standardizedFileURL, file1.standardizedFileURL, "Only living file persisted")
    }

    /// Verifies that attempting to add a non-existent file is completely ignored.
    func testRecentsStoreRejectsNonExistentFileOnAdd() throws {
        let store = RecentRecordingsStore(defaults: isolatedDefaults)
        let phantom = tempDir.appendingPathComponent("ghost.mp4")

        store.addRecent(url: phantom)
        try checkEqual(store.recents.count, 0, "Non-existent file rejected from recents")
    }

    /// Verifies remove(url:) and clear() behavior.
    func testRecentsStoreRemoveAndClear() throws {
        let store = RecentRecordingsStore(defaults: isolatedDefaults)
        let file1 = try createTempFile(name: "alpha.mp4")
        let file2 = try createTempFile(name: "beta.mp4")

        store.addRecent(url: file1)
        store.addRecent(url: file2)
        try checkEqual(store.recents.count, 2, "2 items in store")

        store.remove(url: file1)
        try checkEqual(store.recents.count, 1, "1 item after remove")
        try checkEqual(store.recents[0].standardizedFileURL, file2.standardizedFileURL, "Only file2 remains")

        store.clear()
        try checkEqual(store.recents.count, 0, "Store empty after clear")
    }

    /// Verifies RecordingViewModel.openVideoForTrimming validation, recents tracking, and capture-session guarding.
    func testRecordingViewModelOpenVideoForTrimming() throws {
        let settings = AppSettings(defaults: isolatedDefaults)
        let vm = RecordingViewModel(bundleID: "com.macscreenrecord.tests.openwith", settings: settings)

        let mp4 = try createTempFile(name: "good.mp4")
        let txt = try createTempFile(name: "bad.txt")
        let nonExistent = tempDir.appendingPathComponent("missing.mp4")

        // 1. Non-existent file
        let openedMissing = vm.openVideoForTrimming(url: nonExistent)
        try checkFalse(openedMissing, "Non-existent file fails openVideoForTrimming")
        try checkNil(vm.activeTrimTarget, "No trim target set for non-existent file")
        if case .error(let msg) = vm.status {
            try checkTrue(msg.contains("file does not exist"), "Error message explains missing file")
        } else {
            throw TestFailure(message: "Expected .error status, got \(vm.status)", file: #filePath, line: #line)
        }

        // 2. Unsupported extension
        let openedTxt = vm.openVideoForTrimming(url: txt)
        try checkFalse(openedTxt, "Unsupported extension fails openVideoForTrimming")
        try checkNil(vm.activeTrimTarget, "No trim target set for unsupported file")
        if case .error(let msg) = vm.status {
            try checkTrue(msg.contains("Unsupported video format"), "Error message explains unsupported format")
        } else {
            throw TestFailure(message: "Expected .error status, got \(vm.status)", file: #filePath, line: #line)
        }

        // 3. Supported valid file
        let openedMP4 = vm.openVideoForTrimming(url: mp4)
        try checkTrue(openedMP4, "Supported file successfully opened")
        let target = try unwrap(vm.activeTrimTarget)
        try checkEqual(target.url.standardizedFileURL, mp4.standardizedFileURL, "Active trim target URL matches")
        try checkFalse(target.isPostCaptureReview, "External open is not post-capture review")
        try checkTrue(vm.recentsStore.recents.contains(where: { $0.standardizedFileURL == mp4.standardizedFileURL }), "Added to recents")

        // 4. Capture session guard (cannot open video while recording is active)
        vm.setStatusForTesting(.recording(startedAt: Date()))
        let mov = try createTempFile(name: "another.mov")
        let openedWhileRecording = vm.openVideoForTrimming(url: mov)
        try checkFalse(openedWhileRecording, "openVideoForTrimming rejected while session is capturing")
    }

    /// Verifies RecordingsLibrary.pruneMissingFiles removes files that were deleted on disk.
    func testRecordingsLibraryPruneMissingFiles() async throws {
        let file1 = try createTempFile(name: "record1.mp4")
        let file2 = try createTempFile(name: "record2.mp4")

        let library = RecordingsLibrary(folder: tempDir)
        await library.reload()
        try checkEqual(library.files.count, 2, "Library initially contains 2 files")

        // Remove file1 from disk
        try FileManager.default.removeItem(at: file1)

        library.pruneMissingFiles()
        try checkEqual(library.files.count, 1, "Library pruned to 1 file")
        try checkEqual(library.files[0].url.standardizedFileURL, file2.standardizedFileURL, "Only file2 remains in library")
    }
}
