import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: Int

    var description: String {
        "\((file as NSString).lastPathComponent):\(line) — \(message)"
    }
}

func checkEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String = "",
    file: String = #filePath,
    line: Int = #line
) throws {
    if actual != expected {
        let suffix = message.isEmpty ? "" : " (\(message))"
        throw TestFailure(message: "Expected \(expected), got \(actual)\(suffix)", file: file, line: line)
    }
}

func checkEqual(
    _ actual: Float,
    _ expected: Float,
    accuracy: Float,
    _ message: String = "",
    file: String = #filePath,
    line: Int = #line
) throws {
    if abs(actual - expected) > accuracy {
        let suffix = message.isEmpty ? "" : " (\(message))"
        throw TestFailure(
            message: "Expected \(expected) ± \(accuracy), got \(actual)\(suffix)",
            file: file,
            line: line
        )
    }
}

func checkNotEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    _ message: String = "",
    file: String = #filePath,
    line: Int = #line
) throws {
    if lhs == rhs {
        let suffix = message.isEmpty ? "" : " (\(message))"
        throw TestFailure(message: "Expected values to differ, both were \(lhs)\(suffix)", file: file, line: line)
    }
}

func checkTrue(
    _ condition: Bool,
    _ message: String = "Expected true, got false",
    file: String = #filePath,
    line: Int = #line
) throws {
    if !condition {
        throw TestFailure(message: message, file: file, line: line)
    }
}

func checkFalse(
    _ condition: Bool,
    _ message: String = "Expected false, got true",
    file: String = #filePath,
    line: Int = #line
) throws {
    if condition {
        throw TestFailure(message: message, file: file, line: line)
    }
}

func checkNil<T>(
    _ value: T?,
    _ message: String = "",
    file: String = #filePath,
    line: Int = #line
) throws {
    if let value {
        let suffix = message.isEmpty ? "" : " (\(message))"
        throw TestFailure(message: "Expected nil, got \(value)\(suffix)", file: file, line: line)
    }
}

func checkNotNil<T>(
    _ value: T?,
    _ message: String = "Expected non-nil value",
    file: String = #filePath,
    line: Int = #line
) throws {
    if value == nil {
        throw TestFailure(message: message, file: file, line: line)
    }
}

func unwrap<T>(
    _ value: T?,
    _ message: String = "Unexpected nil value when unwrapping",
    file: String = #filePath,
    line: Int = #line
) throws -> T {
    guard let value else {
        throw TestFailure(message: message, file: file, line: line)
    }
    return value
}

func checkThrowsError<T>(
    _ expression: @autoclosure () throws -> T,
    file: String = #filePath,
    line: Int = #line,
    _ errorHandler: (Error) throws -> Void = { _ in }
) throws {
    do {
        _ = try expression()
    } catch {
        try errorHandler(error)
        return
    }
    throw TestFailure(message: "Expected expression to throw an error, but it succeeded", file: file, line: line)
}

func checkThrowsAsyncError<T>(
    _ expression: () async throws -> T,
    file: String = #filePath,
    line: Int = #line,
    _ errorHandler: (Error) throws -> Void = { _ in }
) async throws {
    do {
        _ = try await expression()
    } catch {
        try errorHandler(error)
        return
    }
    throw TestFailure(message: "Expected expression to throw an error, but it succeeded", file: file, line: line)
}

@main
@MainActor
struct MacScreenRecordTestRunner {
    static func main() async {
        var passed = 0
        var failed = 0

        func run(_ suite: String, _ name: String, _ block: () async throws -> Void) async {
            let start = Date()
            do {
                try await block()
                let elapsed = Date().timeIntervalSince(start)
                print(String(format: "  ✓ [%@] %@ (%.3fs)", suite, name, elapsed))
                passed += 1
            } catch {
                print("  ✗ [\(suite)] \(name) FAILED: \(error)")
                failed += 1
            }
        }

        print("==> Running MacScreenRecord Unit Test Suite...")

        let encoderSuite = EncoderAndCaptureTests()
        await run("EncoderAndCaptureTests", "testOutputCodecContainerAndMetadataMapping") {
            try encoderSuite.testOutputCodecContainerAndMetadataMapping()
        }
        await run("EncoderAndCaptureTests", "testRecordingSettingsEffectiveBitrateCalculation") {
            try encoderSuite.testRecordingSettingsEffectiveBitrateCalculation()
        }
        await run("EncoderAndCaptureTests", "testCaptureSourceAndGeometryDefaults") {
            try encoderSuite.testCaptureSourceAndGeometryDefaults()
        }
        await run("EncoderAndCaptureTests", "testAudioLevelMonitorPeakAmplitudeFloat32AndInt16") {
            try encoderSuite.testAudioLevelMonitorPeakAmplitudeFloat32AndInt16()
        }

        let presetsSuite = PresetsAndLibraryTests()
        await run("PresetsAndLibraryTests", "testPresetCodableAndLegacyRawEnumFallback") {
            try await presetsSuite.withLifecycle {
                try presetsSuite.testPresetCodableAndLegacyRawEnumFallback()
            }
        }
        await run("PresetsAndLibraryTests", "testPresetsStoreFacecamNormalizationAndDefaultLifecycle") {
            try await presetsSuite.withLifecycle {
                try presetsSuite.testPresetsStoreFacecamNormalizationAndDefaultLifecycle()
            }
        }
        await run("PresetsAndLibraryTests", "testPresetsStoreLegacyMigration") {
            try await presetsSuite.withLifecycle {
                try presetsSuite.testPresetsStoreLegacyMigration()
            }
        }
        await run("PresetsAndLibraryTests", "testRecordingFileFormattingAndLibraryOperations") {
            try await presetsSuite.withLifecycle {
                try await presetsSuite.testRecordingFileFormattingAndLibraryOperations()
            }
        }

        let privacySuite = PrivacyAndOverlayTests()
        await run("PrivacyAndOverlayTests", "testPrivacyClaimsZeroEgressInvariants") {
            try privacySuite.testPrivacyClaimsZeroEgressInvariants()
        }
        await run("PrivacyAndOverlayTests", "testAppSettingsLocalNonUbiquitousFolderGuard") {
            try privacySuite.testAppSettingsLocalNonUbiquitousFolderGuard()
        }
        await run("PrivacyAndOverlayTests", "testKeystrokeSpecialKeyGlyphMapping") {
            try privacySuite.testKeystrokeSpecialKeyGlyphMapping()
        }
        await run("PrivacyAndOverlayTests", "testWebcamBackgroundPresetProceduralImageGeneration") {
            try privacySuite.testWebcamBackgroundPresetProceduralImageGeneration()
        }

        let evidenceSuite = EvidenceSealTests()
        await run("EvidenceSealTests", "testStreamingHashKnownVectors") {
            try await evidenceSuite.withLifecycle {
                try evidenceSuite.testStreamingHashKnownVectors()
            }
        }
        await run("EvidenceSealTests", "testEvidenceManifestEncodingDecodingAndSchemaCompliance") {
            try await evidenceSuite.withLifecycle {
                try evidenceSuite.testEvidenceManifestEncodingDecodingAndSchemaCompliance()
            }
        }
        await run("EvidenceSealTests", "testCompanionManifestLifecycleInLibrary") {
            try await evidenceSuite.withLifecycle {
                try await evidenceSuite.testCompanionManifestLifecycleInLibrary()
            }
        }

        let hotkeySuite = HotkeyTests()
        await run("HotkeyTests", "testDefaultHotkeyBindingsAndDisplayStrings") {
            try await hotkeySuite.withLifecycle {
                try hotkeySuite.testDefaultHotkeyBindingsAndDisplayStrings()
            }
        }
        await run("HotkeyTests", "testHotkeyBindingCustomizationAndPersistence") {
            try await hotkeySuite.withLifecycle {
                try hotkeySuite.testHotkeyBindingCustomizationAndPersistence()
            }
        }
        await run("HotkeyTests", "testGlobalHotkeyControllerLifecycle") {
            try await hotkeySuite.withLifecycle {
                try hotkeySuite.testGlobalHotkeyControllerLifecycle()
            }
        }

        let trimSuite = TrimTests()
        await run("TrimTests", "testLosslessTrimmerSupportedFormats") {
            try await trimSuite.withLifecycle {
                try trimSuite.testLosslessTrimmerSupportedFormats()
            }
        }
        await run("TrimTests", "testLosslessTrimmerDefaultTrimmedURL") {
            try await trimSuite.withLifecycle {
                try trimSuite.testLosslessTrimmerDefaultTrimmedURL()
            }
        }
        await run("TrimTests", "testLosslessTrimmerTimeRangeValidation") {
            try await trimSuite.withLifecycle {
                try await trimSuite.testLosslessTrimmerTimeRangeValidation()
            }
        }
        await run("TrimTests", "testLosslessTrimmerExecutionWithSyntheticMovie") {
            try await trimSuite.withLifecycle {
                try await trimSuite.testLosslessTrimmerExecutionWithSyntheticMovie()
            }
        }
        await run("TrimTests", "testRecordingsLibraryTrimIntegration") {
            try await trimSuite.withLifecycle {
                try await trimSuite.testRecordingsLibraryTrimIntegration()
            }
        }

        let companionSuite = MenuBarAndSessionCompanionTests()
        await run("MenuBarAndSessionCompanionTests", "testMenuBarEphemeralLifecycle") {
            try await companionSuite.withLifecycle {
                try companionSuite.testMenuBarEphemeralLifecycle()
            }
        }
        await run("MenuBarAndSessionCompanionTests", "testDurationFormatting") {
            try await companionSuite.withLifecycle {
                try companionSuite.testDurationFormatting()
            }
        }
        await run("MenuBarAndSessionCompanionTests", "testHideWindowDuringRecordingSetting") {
            try await companionSuite.withLifecycle {
                try companionSuite.testHideWindowDuringRecordingSetting()
            }
        }
        await run("MenuBarAndSessionCompanionTests", "testBurnRecordingStateReset") {
            try await companionSuite.withLifecycle {
                try await companionSuite.testBurnRecordingStateReset()
            }
        }
        await run("MenuBarAndSessionCompanionTests", "testVideoEncoderCancelDeletesFileOnDisk") {
            try await companionSuite.withLifecycle {
                try await companionSuite.testVideoEncoderCancelDeletesFileOnDisk()
            }
        }
        await run("MenuBarAndSessionCompanionTests", "testVideoEncoderCancelOnFailedWriterDeletesFile") {
            try await companionSuite.withLifecycle {
                try await companionSuite.testVideoEncoderCancelOnFailedWriterDeletesFile()
            }
        }
        await run("MenuBarAndSessionCompanionTests", "testSavedRecordingStateUpdateAndReveal") {
            try await companionSuite.withLifecycle {
                try companionSuite.testSavedRecordingStateUpdateAndReveal()
            }
        }

        print("")
        if failed > 0 {
            print("✗ Unit Test Suite FAILED (\(failed) failed, \(passed) passed)")
            Foundation.exit(1)
        } else {
            print("✓ All \(passed) unit tests passed across 7 test suites.")
        }
    }
}
