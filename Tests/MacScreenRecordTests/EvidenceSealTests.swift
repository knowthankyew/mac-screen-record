import CaptureCore
import CryptoKit
import EncoderKit
import Foundation
@testable import RecorderUI

@MainActor
final class EvidenceSealTests {

    private var tempDir: URL!

    func withLifecycle(_ body: () async throws -> Void) async throws {
        tempDir = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("EvidenceSealTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            if let tempDir {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
        try await body()
    }

    /// Verifies hardware-accelerated streaming hashing against NIST standard test vectors.
    func testStreamingHashKnownVectors() throws {
        let nistVectorURL = tempDir.appendingPathComponent("nist-test.txt")
        let testString = "The quick brown fox jumps over the lazy dog"
        try testString.data(using: .utf8)!.write(to: nistVectorURL)

        let result = try EvidenceSeal.computeHashes(for: nistVectorURL)
        try checkEqual(result.fileSizeBytes, Int64(testString.utf8.count), "File size in bytes")
        try checkEqual(
            result.sha256,
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
            "SHA-256 standard test vector"
        )
        try checkEqual(
            result.sha512,
            "07e547d9586f6a73f73fbac0435ed76951218fb7d0c8d788a309d785436bbb642e93a252a954f23912547d1e8a3b5ed6e1bfd7097821233fa0538f3db854fee6",
            "SHA-512 standard test vector"
        )

        // Verify empty file vector
        let emptyURL = tempDir.appendingPathComponent("empty.txt")
        try Data().write(to: emptyURL)
        let emptyResult = try EvidenceSeal.computeHashes(for: emptyURL)
        try checkEqual(emptyResult.fileSizeBytes, 0)
        try checkEqual(
            emptyResult.sha256,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "SHA-256 empty file"
        )

        // Verify multi-chunk streaming consistency across 64 KB boundary (160 KB payload)
        let largeData = Data((0..<(160 * 1024)).map { UInt8($0 % 251) })
        let largeURL = tempDir.appendingPathComponent("large.bin")
        try largeData.write(to: largeURL)
        let streamResult = try EvidenceSeal.computeHashes(for: largeURL)

        let directSHA256 = SHA256.hash(data: largeData).map { String(format: "%02x", $0) }.joined()
        let directSHA512 = SHA512.hash(data: largeData).map { String(format: "%02x", $0) }.joined()
        try checkEqual(streamResult.sha256, directSHA256, "Multi-chunk SHA-256 streaming parity")
        try checkEqual(streamResult.sha512, directSHA512, "Multi-chunk SHA-512 streaming parity")
    }

    /// Verifies deterministic serialization and compliance with knowthankyew:evidence:v1 schema.
    func testEvidenceManifestEncodingDecodingAndSchemaCompliance() throws {
        let dummyVideoURL = tempDir.appendingPathComponent("Record_2026-10-14_10-00-00.mp4")
        let payload = "Dummy video bitstream contents".data(using: .utf8)!
        try payload.write(to: dummyVideoURL)

        let startDate = Date(timeIntervalSince1970: 1776182400)
        let endDate = startDate.addingTimeInterval(42.5)

        let manifest = try EvidenceSeal.writeManifest(
            for: dummyVideoURL,
            startDate: startDate,
            endDate: endDate,
            machStart: 10_000_000,
            machEnd: 52_500_000,
            source: .display(id: 1),
            geometry: CaptureGeometry(outputWidth: 1920, outputHeight: 1080, fps: 60),
            codec: .hevc,
            captureMicrophone: true,
            captureSystemAudio: true,
            microphoneDeviceID: "built-in-mic-1",
            webcamEnabled: true,
            webcamCorner: "Bottom Right",
            webcamSize: "Medium",
            webcamBackgroundMode: "Blur",
            clickHighlightsEnabled: true,
            keystrokesEnabled: true,
            secureInputActive: false,
            appVersion: "0.3.0"
        )

        try checkEqual(manifest.schema, "knowthankyew:evidence:v1")
        try checkEqual(manifest.mediaFile.fileName, "Record_2026-10-14_10-00-00.mp4")
        try checkEqual(manifest.mediaFile.fileSizeBytes, Int64(payload.count))
        try checkEqual(manifest.captureContext.codec, "hevc")
        try checkEqual(manifest.captureContext.outputWidth, 1920)
        try checkEqual(manifest.captureContext.outputHeight, 1080)
        try checkEqual(manifest.audioTelemetry.systemAudioEnabled, true)
        try checkEqual(manifest.audioTelemetry.microphoneEnabled, true)
        try checkEqual(manifest.presenterAndOverlays.webcamOverlayEnabled, true)
        try checkEqual(manifest.presenterAndOverlays.webcamBackgroundMode, "Blur")
        try checkEqual(manifest.provenanceAndGovernance.governanceStandard, "knowthankyew:consumer-safe:zero-egress")
        try checkEqual(manifest.provenanceAndGovernance.networkEgressPolicy, "deny")

        // Verify JSON file exists at expected companion URL
        let companionURL = EvidenceSeal.manifestURL(for: dummyVideoURL)
        try checkTrue(FileManager.default.fileExists(atPath: companionURL.path), "Manifest written to disk")

        let diskData = try Data(contentsOf: companionURL)
        let decoded = try JSONDecoder().decode(EvidenceManifest.self, from: diskData)
        try checkEqual(decoded, manifest, "Roundtrip JSON deserialization parity")
    }

    /// Verifies companion `.evidence.json` discovery, rename sync, and deletion in RecordingsLibrary.
    func testCompanionManifestLifecycleInLibrary() async throws {
        let mediaURL = tempDir.appendingPathComponent("Capture.mp4")
        try "video frames".data(using: .utf8)!.write(to: mediaURL)

        try EvidenceSeal.writeManifest(
            for: mediaURL,
            startDate: Date(),
            endDate: Date().addingTimeInterval(5.0),
            machStart: 1000,
            machEnd: 2000,
            source: .display(id: 1),
            geometry: CaptureGeometry(outputWidth: 1280, outputHeight: 720, fps: 30),
            codec: .h264,
            captureMicrophone: false,
            captureSystemAudio: true,
            microphoneDeviceID: nil,
            webcamEnabled: false,
            webcamCorner: nil,
            webcamSize: nil,
            webcamBackgroundMode: nil,
            clickHighlightsEnabled: false,
            keystrokesEnabled: false,
            secureInputActive: false
        )

        let library = RecordingsLibrary(folder: tempDir)
        await library.reload()

        try checkEqual(library.files.count, 1)
        let file = try unwrap(library.files.first)
        try checkTrue(file.hasEvidenceSeal, "Library recognized companion evidence seal")
        let sha = try unwrap(library.sha256Hex(for: file))
        try checkFalse(sha.isEmpty, "Retrieved valid SHA-256 hex from library")

        // Test rename updates companion file and internal fileName
        try await library.rename(file, to: "RenamedCapture")
        let oldCompanion = EvidenceSeal.manifestURL(for: mediaURL)
        try checkFalse(FileManager.default.fileExists(atPath: oldCompanion.path), "Old companion cleaned up")

        let renamedFile = try unwrap(library.files.first)
        try checkTrue(renamedFile.hasEvidenceSeal, "Renamed file retains evidence seal")
        let newCompanion = EvidenceSeal.manifestURL(for: renamedFile.url)
        try checkTrue(FileManager.default.fileExists(atPath: newCompanion.path), "New companion exists")

        let updatedManifest = try unwrap(library.manifest(for: renamedFile))
        try checkEqual(updatedManifest.mediaFile.fileName, renamedFile.url.lastPathComponent, "Manifest fileName updated")

        // Test delete artifacts deletes both media and companion manifest
        let deleteErr = library.deleteArtifacts(at: renamedFile.url, moveToTrash: false)
        try checkNil(deleteErr)
        try checkFalse(FileManager.default.fileExists(atPath: renamedFile.url.path), "Media file deleted")
        try checkFalse(FileManager.default.fileExists(atPath: newCompanion.path), "Evidence manifest deleted")
        try checkEqual(library.files.count, 0)
    }
}
