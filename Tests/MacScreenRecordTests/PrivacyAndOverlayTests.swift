import CoreGraphics
import Foundation
@testable import RecorderUI

final class PrivacyAndOverlayTests {

    func testPrivacyClaimsZeroEgressInvariants() throws {
        let claims = PrivacyClaimsProvider.currentClaims()
        try checkTrue(claims.isLocalOnly)
        try checkEqual(claims.networkEgressPolicy, "deny")
        try checkEqual(claims.telemetryMode, "disabled")
        try checkEqual(claims.thirdPartyDependenciesCount, 0)
        try checkFalse(claims.externalCloudUpload)
        try checkTrue(claims.secureInputSuppressionEnabled)
        try checkEqual(claims.summaryBadge, "100% Local • Zero Network Egress")
    }

    @MainActor
    func testAppSettingsLocalNonUbiquitousFolderGuard() throws {
        let localTemp = FileManager.default.temporaryDirectory
        try checkTrue(AppSettings.isLocalNonUbiquitous(localTemp))

        let fakeICloudURL = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Recordings")
        try checkFalse(AppSettings.isLocalNonUbiquitous(fakeICloudURL))

        let fakeCloudStorageURL = URL(fileURLWithPath: "/Users/test/Library/CloudStorage/Dropbox/Recordings")
        try checkFalse(AppSettings.isLocalNonUbiquitous(fakeCloudStorageURL))
    }

    @MainActor
    func testKeystrokeSpecialKeyGlyphMapping() throws {
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 36), "↩")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 76), "↩")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 48), "⇥")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 49), "Space")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 51), "⌫")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 53), "⎋")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 117), "⌦")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 123), "←")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 124), "→")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 125), "↓")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 126), "↑")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 122), "F1")
        try checkEqual(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 111), "F12")
        try checkNil(KeystrokeOverlayController.specialKeyGlyph(forKeyCode: 0)) // ANSI 'A'
    }

    func testWebcamBackgroundPresetProceduralImageGeneration() throws {
        for preset in WebcamBackgroundPreset.allCases {
            let image = preset.makeImage(size: CGSize(width: 300, height: 300))
            try checkEqual(Float(image.extent.width), 300.0, accuracy: 0.01)
            try checkEqual(Float(image.extent.height), 300.0, accuracy: 0.01)

            // Defensive lower-bound check for zero/degenerate dimensions
            let degenerate = preset.makeImage(size: .zero)
            try checkEqual(Float(degenerate.extent.width), 100.0, accuracy: 0.01)
            try checkEqual(Float(degenerate.extent.height), 100.0, accuracy: 0.01)
        }

        try checkEqual(Float(WebcamBlurStrength.subtle.sigma), 10.0, accuracy: 0.01)
        try checkEqual(Float(WebcamBlurStrength.balanced.sigma), 20.0, accuracy: 0.01)
        try checkEqual(Float(WebcamBlurStrength.strong.sigma), 35.0, accuracy: 0.01)
    }
}
