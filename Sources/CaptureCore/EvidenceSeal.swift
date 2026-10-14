import CryptoKit
import EncoderKit
import Foundation
import MachO

/// Represents the cryptographic and environmental evidence seal generated for a recording.
/// Conforms to the `knowthankyew:evidence:v1` consumer defense governance standard.
public struct EvidenceManifest: Codable, Equatable, Sendable {

    public struct MediaFile: Codable, Equatable, Sendable {
        public let fileName: String
        public let fileSizeBytes: Int64
        public let sha256: String
        public let sha512: String

        public init(fileName: String, fileSizeBytes: Int64, sha256: String, sha512: String) {
            self.fileName = fileName
            self.fileSizeBytes = fileSizeBytes
            self.sha256 = sha256
            self.sha512 = sha512
        }
    }

    public struct TemporalIntegrity: Codable, Equatable, Sendable {
        public let startedAtUTC: String
        public let endedAtUTC: String
        public let durationSeconds: Double
        public let machContinuousStart: UInt64
        public let machContinuousEnd: UInt64
        public let machTimebaseNumerator: UInt32
        public let machTimebaseDenominator: UInt32

        public init(
            startedAtUTC: String,
            endedAtUTC: String,
            durationSeconds: Double,
            machContinuousStart: UInt64,
            machContinuousEnd: UInt64,
            machTimebaseNumerator: UInt32,
            machTimebaseDenominator: UInt32
        ) {
            self.startedAtUTC = startedAtUTC
            self.endedAtUTC = endedAtUTC
            self.durationSeconds = durationSeconds
            self.machContinuousStart = machContinuousStart
            self.machContinuousEnd = machContinuousEnd
            self.machTimebaseNumerator = machTimebaseNumerator
            self.machTimebaseDenominator = machTimebaseDenominator
        }
    }

    public struct CaptureContext: Codable, Equatable, Sendable {
        public let sourceKind: String
        public let targetDisplayID: UInt32?
        public let targetWindowID: UInt32?
        public let targetProcessID: Int32?
        public let outputWidth: Int
        public let outputHeight: Int
        public let fps: Int
        public let codec: String

        public init(
            sourceKind: String,
            targetDisplayID: UInt32? = nil,
            targetWindowID: UInt32? = nil,
            targetProcessID: Int32? = nil,
            outputWidth: Int,
            outputHeight: Int,
            fps: Int,
            codec: String
        ) {
            self.sourceKind = sourceKind
            self.targetDisplayID = targetDisplayID
            self.targetWindowID = targetWindowID
            self.targetProcessID = targetProcessID
            self.outputWidth = outputWidth
            self.outputHeight = outputHeight
            self.fps = fps
            self.codec = codec
        }
    }

    public struct AudioTelemetry: Codable, Equatable, Sendable {
        public let systemAudioEnabled: Bool
        public let microphoneEnabled: Bool
        public let microphoneDeviceID: String?

        public init(systemAudioEnabled: Bool, microphoneEnabled: Bool, microphoneDeviceID: String? = nil) {
            self.systemAudioEnabled = systemAudioEnabled
            self.microphoneEnabled = microphoneEnabled
            self.microphoneDeviceID = microphoneDeviceID
        }
    }

    public struct PresenterAndOverlays: Codable, Equatable, Sendable {
        public let webcamOverlayEnabled: Bool
        public let webcamCorner: String?
        public let webcamSize: String?
        public let webcamBackgroundMode: String?
        public let clickHighlightsEnabled: Bool
        public let keystrokeOverlayEnabled: Bool
        public let secureInputSuppressionActive: Bool

        public init(
            webcamOverlayEnabled: Bool,
            webcamCorner: String? = nil,
            webcamSize: String? = nil,
            webcamBackgroundMode: String? = nil,
            clickHighlightsEnabled: Bool,
            keystrokeOverlayEnabled: Bool,
            secureInputSuppressionActive: Bool
        ) {
            self.webcamOverlayEnabled = webcamOverlayEnabled
            self.webcamCorner = webcamCorner
            self.webcamSize = webcamSize
            self.webcamBackgroundMode = webcamBackgroundMode
            self.clickHighlightsEnabled = clickHighlightsEnabled
            self.keystrokeOverlayEnabled = keystrokeOverlayEnabled
            self.secureInputSuppressionActive = secureInputSuppressionActive
        }
    }

    public struct ProvenanceAndGovernance: Codable, Equatable, Sendable {
        public let schemaVersion: String
        public let bundleIdentifier: String
        public let appVersion: String
        public let governanceStandard: String
        public let networkEgressPolicy: String
        public let telemetryMode: String
        public let localOnly: Bool

        public init(
            schemaVersion: String = "knowthankyew:evidence:v1",
            bundleIdentifier: String = "com.macscreenrecord.app",
            appVersion: String = "0.3.0",
            governanceStandard: String = "knowthankyew:consumer-safe:zero-egress",
            networkEgressPolicy: String = "deny",
            telemetryMode: String = "disabled",
            localOnly: Bool = true
        ) {
            self.schemaVersion = schemaVersion
            self.bundleIdentifier = bundleIdentifier
            self.appVersion = appVersion
            self.governanceStandard = governanceStandard
            self.networkEgressPolicy = networkEgressPolicy
            self.telemetryMode = telemetryMode
            self.localOnly = localOnly
        }
    }

    public let schema: String
    public let mediaFile: MediaFile
    public let temporalIntegrity: TemporalIntegrity
    public let captureContext: CaptureContext
    public let audioTelemetry: AudioTelemetry
    public let presenterAndOverlays: PresenterAndOverlays
    public let provenanceAndGovernance: ProvenanceAndGovernance

    public init(
        schema: String = "knowthankyew:evidence:v1",
        mediaFile: MediaFile,
        temporalIntegrity: TemporalIntegrity,
        captureContext: CaptureContext,
        audioTelemetry: AudioTelemetry,
        presenterAndOverlays: PresenterAndOverlays,
        provenanceAndGovernance: ProvenanceAndGovernance = ProvenanceAndGovernance()
    ) {
        self.schema = schema
        self.mediaFile = mediaFile
        self.temporalIntegrity = temporalIntegrity
        self.captureContext = captureContext
        self.audioTelemetry = audioTelemetry
        self.presenterAndOverlays = presenterAndOverlays
        self.provenanceAndGovernance = provenanceAndGovernance
    }
}

/// Computes SHA-256 and SHA-512 cryptographic hashes and writes companion `.evidence.json` manifests.
public enum EvidenceSeal {

    public struct HashResult: Equatable, Sendable {
        public let sha256: String
        public let sha512: String
        public let fileSizeBytes: Int64

        public init(sha256: String, sha512: String, fileSizeBytes: Int64) {
            self.sha256 = sha256
            self.sha512 = sha512
            self.fileSizeBytes = fileSizeBytes
        }
    }

    /// Computes hardware-accelerated SHA-256 and SHA-512 hashes using streaming 64 KB buffers,
    /// avoiding memory exhaustion even on multi-gigabyte recordings.
    public static func computeHashes(for fileURL: URL) throws -> HashResult {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var sha256 = SHA256()
        var sha512 = SHA512()
        var totalBytes: Int64 = 0
        let chunkSize = 64 * 1024

        while true {
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            totalBytes += Int64(data.count)
            sha256.update(data: data)
            sha512.update(data: data)
        }

        let sha256Digest = sha256.finalize()
        let sha512Digest = sha512.finalize()

        let sha256Hex = sha256Digest.map { String(format: "%02x", $0) }.joined()
        let sha512Hex = sha512Digest.map { String(format: "%02x", $0) }.joined()

        return HashResult(sha256: sha256Hex, sha512: sha512Hex, fileSizeBytes: totalBytes)
    }

    /// Returns the standard companion URL for a given recording media file:
    /// e.g. `/path/to/Record.mp4` -> `/path/to/Record.evidence.json`.
    public static func manifestURL(for mediaURL: URL) -> URL {
        let dir = mediaURL.deletingLastPathComponent()
        let base = mediaURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(base).evidence.json")
    }

    /// Queries the system Mach continuous timebase info.
    public static func machTimebase() -> (numer: UInt32, denom: UInt32) {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return (info.numer, info.denom)
    }

    /// Generates and persists the `.evidence.json` manifest beside the finalized recording.
    @discardableResult
    public static func writeManifest(
        for mediaURL: URL,
        startDate: Date,
        endDate: Date,
        machStart: UInt64,
        machEnd: UInt64,
        source: CaptureSource,
        geometry: CaptureGeometry,
        codec: OutputCodec,
        captureMicrophone: Bool,
        captureSystemAudio: Bool,
        microphoneDeviceID: String?,
        webcamEnabled: Bool,
        webcamCorner: String?,
        webcamSize: String?,
        webcamBackgroundMode: String?,
        clickHighlightsEnabled: Bool,
        keystrokesEnabled: Bool,
        secureInputActive: Bool,
        appVersion: String = "0.3.0"
    ) throws -> EvidenceManifest {
        let hashes = try computeHashes(for: mediaURL)
        let timebase = machTimebase()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let duration = max(0, endDate.timeIntervalSince(startDate))

        let sourceKind: String
        var displayID: UInt32?
        var windowID: UInt32?
        var pid: Int32?

        switch source {
        case .display(let id, _):
            sourceKind = "display"
            displayID = id
        case .window(let id):
            sourceKind = "window"
            windowID = id
        case .application(let appPid, let dispID):
            sourceKind = "application"
            pid = appPid
            displayID = dispID
        }

        let manifest = EvidenceManifest(
            mediaFile: EvidenceManifest.MediaFile(
                fileName: mediaURL.lastPathComponent,
                fileSizeBytes: hashes.fileSizeBytes,
                sha256: hashes.sha256,
                sha512: hashes.sha512
            ),
            temporalIntegrity: EvidenceManifest.TemporalIntegrity(
                startedAtUTC: isoFormatter.string(from: startDate),
                endedAtUTC: isoFormatter.string(from: endDate),
                durationSeconds: duration,
                machContinuousStart: machStart,
                machContinuousEnd: machEnd,
                machTimebaseNumerator: timebase.numer,
                machTimebaseDenominator: timebase.denom
            ),
            captureContext: EvidenceManifest.CaptureContext(
                sourceKind: sourceKind,
                targetDisplayID: displayID,
                targetWindowID: windowID,
                targetProcessID: pid,
                outputWidth: geometry.outputWidth,
                outputHeight: geometry.outputHeight,
                fps: geometry.fps,
                codec: codec.rawValue
            ),
            audioTelemetry: EvidenceManifest.AudioTelemetry(
                systemAudioEnabled: captureSystemAudio,
                microphoneEnabled: captureMicrophone,
                microphoneDeviceID: microphoneDeviceID
            ),
            presenterAndOverlays: EvidenceManifest.PresenterAndOverlays(
                webcamOverlayEnabled: webcamEnabled,
                webcamCorner: webcamCorner,
                webcamSize: webcamSize,
                webcamBackgroundMode: webcamBackgroundMode,
                clickHighlightsEnabled: clickHighlightsEnabled,
                keystrokeOverlayEnabled: keystrokesEnabled,
                secureInputSuppressionActive: secureInputActive
            ),
            provenanceAndGovernance: EvidenceManifest.ProvenanceAndGovernance(
                appVersion: appVersion
            )
        )

        let manifestURL = manifestURL(for: mediaURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)

        return manifest
    }
}
