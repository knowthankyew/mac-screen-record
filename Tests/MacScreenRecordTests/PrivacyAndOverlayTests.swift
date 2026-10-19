import AppKit
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

    func testWebcamShapeAndAspectRatioFramingDimensions() throws {
        // Enums & display names
        try checkEqual(WebcamShape.circle.displayName, "Circle")
        try checkEqual(WebcamShape.roundedRect.displayName, "Rounded Rectangle")

        try checkEqual(WebcamAspectRatio.square.displayName, "1:1 Square")
        try checkEqual(WebcamAspectRatio.widescreen.displayName, "16:9 Widescreen")
        try checkEqual(WebcamAspectRatio.classic.displayName, "4:3 Classic")

        try checkEqual(Float(WebcamAspectRatio.square.ratio), 1.0, accuracy: 0.001)
        try checkEqual(Float(WebcamAspectRatio.widescreen.ratio), 16.0 / 9.0, accuracy: 0.001)
        try checkEqual(Float(WebcamAspectRatio.classic.ratio), 4.0 / 3.0, accuracy: 0.001)

        // Circle shape must always preserve square 1:1 dimensions
        for size in WebcamSize.allCases {
            let circleDims = size.dimensions(shape: .circle, aspectRatio: .widescreen)
            try checkEqual(circleDims.width, circleDims.height, "Circle is always 1:1 square")
            try checkEqual(circleDims.width, size.pixels.width, "Circle matches size.pixels")
        }

        // Rounded rectangle square (1:1)
        try checkEqual(WebcamSize.small.dimensions(shape: .roundedRect, aspectRatio: .square), CGSize(width: 160, height: 160))
        try checkEqual(WebcamSize.medium.dimensions(shape: .roundedRect, aspectRatio: .square), CGSize(width: 220, height: 220))
        try checkEqual(WebcamSize.large.dimensions(shape: .roundedRect, aspectRatio: .square), CGSize(width: 300, height: 300))

        // Rounded rectangle widescreen (16:9)
        let smallWide = WebcamSize.small.dimensions(shape: .roundedRect, aspectRatio: .widescreen)
        try checkEqual(smallWide, CGSize(width: 240, height: 135))
        try checkEqual(Float(smallWide.width / smallWide.height), Float(16.0 / 9.0), accuracy: 0.001)

        let medWide = WebcamSize.medium.dimensions(shape: .roundedRect, aspectRatio: .widescreen)
        try checkEqual(medWide, CGSize(width: 320, height: 180))
        try checkEqual(Float(medWide.width / medWide.height), Float(16.0 / 9.0), accuracy: 0.001)

        let largeWide = WebcamSize.large.dimensions(shape: .roundedRect, aspectRatio: .widescreen)
        try checkEqual(largeWide, CGSize(width: 400, height: 225))
        try checkEqual(Float(largeWide.width / largeWide.height), Float(16.0 / 9.0), accuracy: 0.001)

        // Rounded rectangle classic (4:3)
        let smallClassic = WebcamSize.small.dimensions(shape: .roundedRect, aspectRatio: .classic)
        try checkEqual(smallClassic, CGSize(width: 200, height: 150))
        try checkEqual(Float(smallClassic.width / smallClassic.height), Float(4.0 / 3.0), accuracy: 0.001)

        let medClassic = WebcamSize.medium.dimensions(shape: .roundedRect, aspectRatio: .classic)
        try checkEqual(medClassic, CGSize(width: 280, height: 210))
        try checkEqual(Float(medClassic.width / medClassic.height), Float(4.0 / 3.0), accuracy: 0.001)

        let largeClassic = WebcamSize.large.dimensions(shape: .roundedRect, aspectRatio: .classic)
        try checkEqual(largeClassic, CGSize(width: 360, height: 270))
        try checkEqual(Float(largeClassic.width / largeClassic.height), Float(4.0 / 3.0), accuracy: 0.001)
    }

    func testHexColorConversionsAndBorderAttributes() throws {
        // Standard 6-char hex conversion
        let whiteCG = try unwrap(CGColor.fromHex("#FFFFFF"))
        try checkEqual(whiteCG.hexString.uppercased(), "#FFFFFF")

        let greenCG = try unwrap(CGColor.fromHex("#34C759"))
        try checkEqual(greenCG.hexString.uppercased(), "#34C759")

        // Hex without '#' prefix
        let blueCG = try unwrap(CGColor.fromHex("007AFF"))
        try checkEqual(blueCG.hexString.uppercased(), "#007AFF")

        // 8-char hex with alpha
        let semiRedCG = try unwrap(CGColor.fromHex("#FF000080"))
        try checkEqual(semiRedCG.hexString.uppercased(), "#FF000080")

        // Invalid hex strings return nil defensively
        try checkNil(CGColor.fromHex("invalid-color"))
        try checkNil(CGColor.fromHex("#12345"))
        try checkNil(CGColor.fromHex("#123456789"))
        try checkNil(CGColor.fromHex("#12G456"), "Rejects strings containing non-hex characters")
        try checkNil(CGColor.fromHex("#ZZZZZZ"), "Rejects all non-hex alphabetic characters")

        // NSColor wrapper equivalence
        let nsGreen = try unwrap(NSColor(hex: "#34C759"))
        try checkEqual(nsGreen.hexString.uppercased(), "#34C759")
    }

    func testPresetWebcamFramingAndBorderPersistence() throws {
        let preset = Preset(
            name: "Phase 11 Custom Facecam",
            sourceKindRaw: "display",
            codec: .hevc,
            fps: 60,
            showsCursor: true,
            captureSystemAudio: true,
            captureMicrophone: true,
            customWidth: nil,
            customHeight: nil,
            webcamEnabled: true,
            useForFacecam: true,
            clickHighlightsEnabled: true,
            keystrokesEnabled: false,
            webcamCorner: .bottomRight,
            webcamSize: .large,
            webcamBackgroundMode: .customImage,
            webcamBlurStrength: .strong,
            webcamShape: .roundedRect,
            webcamAspectRatio: .widescreen,
            webcamBlurCustomImage: true,
            webcamShowBorder: true,
            webcamBorderColorHex: "#34C759",
            webcamBorderWidth: 4.5
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(preset)
        let decoded = try decoder.decode(Preset.self, from: data)

        try checkEqual(decoded.name, preset.name)
        try checkEqual(decoded.webcamBlurStrength, .strong)
        try checkEqual(decoded.webcamShape, .roundedRect)
        try checkEqual(decoded.webcamAspectRatio, .widescreen)
        try checkEqual(decoded.webcamBlurCustomImage, true)
        try checkEqual(decoded.webcamShowBorder, true)
        try checkEqual(decoded.webcamBorderColorHex, "#34C759")
        try checkEqual(decoded.webcamBorderWidth, 4.5)

        // Backward compatibility: Decode legacy JSON without new Phase 11 keys
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Preset",
            "sourceKindRaw": "display",
            "codec": "h264",
            "fps": 30,
            "showsCursor": true,
            "captureSystemAudio": false,
            "captureMicrophone": false,
            "webcamEnabled": true,
            "webcamCorner": "topLeft",
            "webcamSize": "small"
        }
        """.data(using: .utf8)!

        let decodedLegacy = try decoder.decode(Preset.self, from: legacyJSON)
        try checkEqual(decodedLegacy.name, "Legacy Preset")
        try checkEqual(decodedLegacy.webcamCorner, .topLeft)
        try checkEqual(decodedLegacy.webcamSize, .small)
        try checkNil(decodedLegacy.webcamBlurStrength, "Missing blur strength decodes as nil in legacy presets")
        try checkNil(decodedLegacy.webcamShape, "Missing shape decodes as nil in legacy presets")
        try checkNil(decodedLegacy.webcamAspectRatio, "Missing aspect ratio decodes as nil in legacy presets")
        try checkNil(decodedLegacy.webcamBlurCustomImage, "Missing blur custom image decodes as nil in legacy presets")
        try checkNil(decodedLegacy.webcamShowBorder, "Missing show border decodes as nil in legacy presets")
        try checkNil(decodedLegacy.webcamBorderColorHex, "Missing border color decodes as nil in legacy presets")
        try checkNil(decodedLegacy.webcamBorderWidth, "Missing border width decodes as nil in legacy presets")
    }

    func testWebcamVideoProcessorAspectRatioAndBlurCaching() throws {
        let processor = WebcamVideoProcessor()
        try checkEqual(processor.aspectRatio, .square)
        try checkFalse(processor.blurCustomImage)
        try checkEqual(processor.blurStrength, .balanced)

        processor.aspectRatio = .widescreen
        try checkEqual(processor.aspectRatio, .widescreen)

        processor.aspectRatio = .classic
        try checkEqual(processor.aspectRatio, .classic)

        processor.blurCustomImage = true
        try checkTrue(processor.blurCustomImage)

        processor.blurStrength = .strong
        try checkEqual(processor.blurStrength, .strong)
    }

    func testWebcamVideoProcessorCenteredCropRectMath() throws {
        // 640x480 (4:3) with 16:9 target ratio -> source is taller than 16:9 -> fit width, crop height
        let crop640x480to16x9 = WebcamVideoProcessor.centeredCropRect(source: CGSize(width: 640, height: 480), ratio: 16.0 / 9.0)
        try checkEqual(crop640x480to16x9.width, 640.0)
        try checkEqual(crop640x480to16x9.height, 360.0)
        try checkEqual(crop640x480to16x9.origin.x, 0.0)
        try checkEqual(crop640x480to16x9.origin.y, 60.0)

        // 1280x720 (16:9) with 4:3 target ratio -> source is wider than 4:3 -> fit height, crop width
        let crop1280x720to4x3 = WebcamVideoProcessor.centeredCropRect(source: CGSize(width: 1280, height: 720), ratio: 4.0 / 3.0)
        try checkEqual(crop1280x720to4x3.width, 960.0)
        try checkEqual(crop1280x720to4x3.height, 720.0)
        try checkEqual(crop1280x720to4x3.origin.x, 160.0)
        try checkEqual(crop1280x720to4x3.origin.y, 0.0)

        // Portrait source 1080x1920 with 1:1 square target ratio -> fit width, crop height
        let portraitToSquare = WebcamVideoProcessor.centeredCropRect(source: CGSize(width: 1080, height: 1920), ratio: 1.0)
        try checkEqual(portraitToSquare.width, 1080.0)
        try checkEqual(portraitToSquare.height, 1080.0)
        try checkEqual(portraitToSquare.origin.x, 0.0)
        try checkEqual(portraitToSquare.origin.y, 420.0)

        // 1x1 degenerate source
        let degenerate = WebcamVideoProcessor.centeredCropRect(source: CGSize(width: 1, height: 1), ratio: 16.0 / 9.0)
        try checkEqual(degenerate.width, 1.0)
        try checkEqual(degenerate.height, 1.0)
        try checkEqual(degenerate.origin, .zero)

        // Zero / invalid dimensions
        let zeroCrop = WebcamVideoProcessor.centeredCropRect(source: .zero, ratio: 1.0)
        try checkEqual(zeroCrop, .zero)
    }

    func testWebcamShapePathGenerationAndAspectSupport() throws {
        let testBounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        for shape in WebcamShape.allCases {
            let path = shape.path(in: testBounds)
            let pathBounds = path.boundingBox
            try checkFalse(path.isEmpty, "\(shape.rawValue) path should not be empty")
            try checkTrue(pathBounds.width > 0, "\(shape.rawValue) path width should be positive")
            try checkTrue(pathBounds.height > 0, "\(shape.rawValue) path height should be positive")
            try checkTrue(pathBounds.maxX <= testBounds.maxX + 1.0, "\(shape.rawValue) path should fit inside bounds")
            try checkTrue(pathBounds.maxY <= testBounds.maxY + 1.0, "\(shape.rawValue) path should fit inside bounds")
        }

        // supportsAspectRatio
        try checkTrue(WebcamShape.roundedRect.supportsAspectRatio)
        try checkTrue(WebcamShape.oval.supportsAspectRatio)
        try checkFalse(WebcamShape.circle.supportsAspectRatio)
        try checkFalse(WebcamShape.hexagon.supportsAspectRatio)
        try checkFalse(WebcamShape.diamond.supportsAspectRatio)
        try checkFalse(WebcamShape.heart.supportsAspectRatio)
        try checkFalse(WebcamShape.star.supportsAspectRatio)

        // Degenerate bounds
        let degeneratePath = WebcamShape.hexagon.path(in: .zero)
        try checkEqual(degeneratePath.boundingBox, .zero)
    }

    func testWebcamSourceTypeCodableAndIcons() throws {
        try checkEqual(WebcamSourceType.camera.displayName, "Camera")
        try checkEqual(WebcamSourceType.staticImage.displayName, "Static Image")
        try checkEqual(WebcamSourceType.videoClip.displayName, "Video Loop")

        try checkEqual(WebcamSourceType.camera.systemImage, "camera")
        try checkEqual(WebcamSourceType.staticImage.systemImage, "photo")
        try checkEqual(WebcamSourceType.videoClip.systemImage, "play.rectangle")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for source in WebcamSourceType.allCases {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(WebcamSourceType.self, from: data)
            try checkEqual(decoded, source)
        }
    }

    func testPresetWebcamSourceAndBrandingPersistence() throws {
        let preset = Preset(
            name: "Phase 13 Preset",
            sourceKindRaw: "display",
            codec: .hevc,
            fps: 60,
            showsCursor: true,
            captureSystemAudio: true,
            captureMicrophone: true,
            customWidth: 1920,
            customHeight: 1080,
            webcamEnabled: true,
            webcamShape: .hexagon,
            webcamSourceType: .staticImage,
            webcamStaticImageURL: "/tmp/avatar.png",
            webcamVideoClipURL: "/tmp/loop.mp4",
            webcamBrandingOverlayURL: "/tmp/watermark.png"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(preset)
        let decoded = try decoder.decode(Preset.self, from: data)

        try checkEqual(decoded.webcamSourceType, .staticImage)
        try checkEqual(decoded.webcamShape, .hexagon)
        try checkEqual(decoded.webcamStaticImageURL, "/tmp/avatar.png")
        try checkEqual(decoded.webcamVideoClipURL, "/tmp/loop.mp4")
        try checkEqual(decoded.webcamBrandingOverlayURL, "/tmp/watermark.png")

        // Legacy JSON without Phase 13 fields decodes cleanly as nil
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Preset Phase 11",
            "sourceKindRaw": "display",
            "codec": "h264",
            "fps": 30,
            "showsCursor": true,
            "captureSystemAudio": false,
            "captureMicrophone": false,
            "webcamEnabled": true
        }
        """.data(using: .utf8)!

        let decodedLegacy = try decoder.decode(Preset.self, from: legacyJSON)
        try checkNil(decodedLegacy.webcamSourceType, "Missing sourceType decodes as nil")
        try checkNil(decodedLegacy.webcamStaticImageURL, "Missing static image decodes as nil")
        try checkNil(decodedLegacy.webcamVideoClipURL, "Missing video clip decodes as nil")
        try checkNil(decodedLegacy.webcamBrandingOverlayURL, "Missing branding overlay decodes as nil")
    }

    private final class Box<T>: @unchecked Sendable {
        private var val: T
        private let lock = NSLock()
        init(_ val: T) { self.val = val }
        func set(_ val: T) { lock.lock(); self.val = val; lock.unlock() }
        func get() -> T { lock.lock(); defer { lock.unlock() }; return val }
    }

    func testWebcamVideoProcessorProcessImageAndMediaSwitching() throws {
        let processor = WebcamVideoProcessor()

        // Negative check: when acceptedSource is .camera, processImage drops the frame
        let deliveredFrames = Box<[CIImage]>([])
        processor.onFrameProcessed = { frame in
            var current = deliveredFrames.get()
            current.append(frame)
            deliveredFrames.set(current)
        }
        processor.acceptedSource = .camera
        let testImage = CIImage(color: CIColor.red).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        processor.processImage(testImage)
        try checkTrue(deliveredFrames.get().isEmpty, "Camera mode should drop static image frame")

        // Positive check: static image is processed and delivered
        let sema1 = DispatchSemaphore(value: 0)
        processor.onFrameProcessed = { _ in sema1.signal() }
        processor.acceptedSource = .staticImage
        processor.backgroundMode = .none
        processor.processImage(testImage)

        let result1 = sema1.wait(timeout: .now() + 2.0)
        try checkTrue(result1 == .success, "Static image should be processed and delivered")

        // Test with background preset and verify delivery
        let sema2 = DispatchSemaphore(value: 0)
        let lastRendered = Box<CIImage?>(nil)
        processor.onFrameProcessed = { frame in
            lastRendered.set(frame)
            sema2.signal()
        }
        processor.backgroundMode = .preset
        processor.backgroundPreset = .warmStudio
        processor.processImage(testImage)

        let result2 = sema2.wait(timeout: .now() + 2.0)
        try checkTrue(result2 == .success, "Preset background frame should be processed and delivered")
        let renderedOpt = lastRendered.get()
        try checkNotNil(renderedOpt, "Processed frame must be observable")
        if let rendered = renderedOpt {
            try checkTrue(rendered.extent.width > 0 && rendered.extent.height > 0, "Rendered frame must have valid dimensions")
        }
    }

    func testPresenterBackdropOverlayAndSnapPositions() throws {
        let overlay = PresenterBackdropOverlay()
        try checkFalse(overlay.isEnabled)
        try checkNil(overlay.imageURL)
        try checkTrue(overlay.isGrouped)

        overlay.isEnabled = true
        overlay.isGrouped = false
        try checkTrue(overlay.isEnabled)
        try checkFalse(overlay.isGrouped)

        let testURL = URL(fileURLWithPath: "/tmp/backdrop.png")
        overlay.imageURL = testURL
        try checkEqual(overlay.imageURL, testURL)

        overlay.relativeRect = CGRect(x: -40, y: -30, width: 300, height: 280)
        try checkEqual(overlay.relativeRect.origin.x, -40)
        try checkEqual(overlay.relativeRect.width, 300)

        // Verify all snap positions map to valid normalized points (0...1)
        for pos in PresenterSnapPosition.allCases {
            let pt = pos.normalizedPoint
            try checkTrue(pt.x >= 0.0 && pt.x <= 1.0, "Snap \(pos) X must be in 0...1")
            try checkTrue(pt.y >= 0.0 && pt.y <= 1.0, "Snap \(pos) Y must be in 0...1")
        }
        try checkEqual(PresenterSnapPosition.bottomRight.normalizedPoint, CGPoint(x: 1.0, y: 0.0))
        try checkEqual(PresenterSnapPosition.topLeft.normalizedPoint, CGPoint(x: 0.0, y: 1.0))
        try checkEqual(PresenterSnapPosition.center.normalizedPoint, CGPoint(x: 0.5, y: 0.5))
    }

    func testPresetPresenterBackdropAndNormalizedLayoutPersistence() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let preset = Preset(
            name: "Staging Test Profile",
            sourceKindRaw: "display",
            codec: .hevc,
            fps: 60,
            showsCursor: true,
            captureSystemAudio: false,
            captureMicrophone: false,
            customWidth: nil,
            customHeight: nil,
            webcamEnabled: true,
            pipNormalizedX: 0.85,
            pipNormalizedY: 0.15,
            backdropEnabled: true,
            backdropImageURL: "/tmp/custom-plate.png",
            backdropIsGrouped: true,
            backdropRelativeX: -35.0,
            backdropRelativeY: -25.0,
            backdropRelativeWidth: 280.0,
            backdropRelativeHeight: 260.0
        )

        let data = try encoder.encode(preset)
        let decoded = try decoder.decode(Preset.self, from: data)

        try checkEqual(decoded.pipNormalizedX, 0.85)
        try checkEqual(decoded.pipNormalizedY, 0.15)
        try checkEqual(decoded.backdropEnabled, true)
        try checkEqual(decoded.backdropImageURL, "/tmp/custom-plate.png")
        try checkEqual(decoded.backdropIsGrouped, true)
        try checkEqual(decoded.backdropRelativeX, -35.0)
        try checkEqual(decoded.backdropRelativeY, -25.0)
        try checkEqual(decoded.backdropRelativeWidth, 280.0)
        try checkEqual(decoded.backdropRelativeHeight, 260.0)

        // Backward compatibility: legacy preset with webcamCorner falls back to normalizedPoint
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Preset",
            "sourceKindRaw": "display",
            "codec": "hevc",
            "fps": 30,
            "showsCursor": true,
            "captureSystemAudio": false,
            "captureMicrophone": false,
            "webcamEnabled": true,
            "webcamCorner": "topLeft"
        }
        """.data(using: .utf8)!

        let decodedLegacy = try decoder.decode(Preset.self, from: legacyJSON)
        try checkNil(decodedLegacy.pipNormalizedX)
        try checkNil(decodedLegacy.pipNormalizedY)
        try checkEqual(decodedLegacy.effectivePipNormalizedPosition, CGPoint(x: 0.0, y: 1.0))
        try checkNil(decodedLegacy.backdropEnabled)
    }
}

