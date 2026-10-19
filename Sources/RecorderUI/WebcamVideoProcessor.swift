import AVFoundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import OSLog
import Vision

/// Processes real-time camera frames from `AVCaptureVideoDataOutput`,
/// executing Apple's native Neural Engine person segmentation, Core Image
/// compositing (blur, backdrop replacement, cutout), mirroring, and aspect cropping.
///
/// Architecture Note:
/// Synchronized via a non-recursive `NSLock` protecting a unified immutable `Config`
/// snapshot and image caches. In a future Swift 6 strict concurrency migration,
/// this state can be cleanly migrated to an actor.
public final class WebcamVideoProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private struct Config {
        var mode: WebcamBackgroundMode = .none
        var blurStrength: WebcamBlurStrength = .balanced
        var blurCustomImage: Bool = false
        var backgroundPreset: WebcamBackgroundPreset = .warmStudio
        var customImageURL: URL? = nil
        var brandingOverlayURL: URL? = nil
        var mirrored: Bool = true
        var aspectRatio: WebcamAspectRatio = .square
    }

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "WebcamProcessor")
    private let segmentationRequest: VNGeneratePersonSegmentationRequest
    private let prepareContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.macscreenrecord.webcam.processing", qos: .userInteractive)

    public var onAssetLoaded: (@Sendable () -> Void)?
    public var onFrameProcessed: (@Sendable (CIImage) -> Void)?

    // Guarded by lock
    private var config = Config()
    private var activeSource: WebcamSourceType = .camera
    private var frameInFlight = false
    private var cachedCustomImage: CIImage?
    private var cachedCustomImageURL: URL?
    private var cachedPreparedCustomImage: CIImage?
    private var lastPreparedCustomImageURL: URL?
    private var lastPreparedCustomImageSize: CGSize = .zero
    private var lastPreparedBlurCustomImage: Bool = false
    private var lastPreparedBlurStrength: WebcamBlurStrength = .balanced
    private var cachedBrandingImage: CIImage?
    private var cachedBrandingImageURL: URL?
    private var cachedPresetImage: CIImage?
    private var lastCachedPreset: WebcamBackgroundPreset?
    private var lastCachedPresetSize: CGSize = .zero

    // Thread-safe public properties
    public var acceptedSource: WebcamSourceType {
        get { lock.lock(); defer { lock.unlock() }; return activeSource }
        set { lock.lock(); activeSource = newValue; lock.unlock() }
    }

    public var backgroundMode: WebcamBackgroundMode {
        get { lock.lock(); defer { lock.unlock() }; return config.mode }
        set { lock.lock(); config.mode = newValue; lock.unlock() }
    }

    public var blurStrength: WebcamBlurStrength {
        get { lock.lock(); defer { lock.unlock() }; return config.blurStrength }
        set {
            lock.lock()
            config.blurStrength = newValue
            cachedPreparedCustomImage = nil
            lock.unlock()
        }
    }

    public var blurCustomImage: Bool {
        get { lock.lock(); defer { lock.unlock() }; return config.blurCustomImage }
        set {
            lock.lock()
            config.blurCustomImage = newValue
            cachedPreparedCustomImage = nil
            lock.unlock()
        }
    }

    public var backgroundPreset: WebcamBackgroundPreset {
        get { lock.lock(); defer { lock.unlock() }; return config.backgroundPreset }
        set {
            lock.lock()
            config.backgroundPreset = newValue
            cachedPresetImage = nil
            lock.unlock()
        }
    }

    public var customImageURL: URL? {
        get { lock.lock(); defer { lock.unlock() }; return config.customImageURL }
        set { setCustomImageURL(newValue) }
    }

    public var brandingOverlayURL: URL? {
        get { lock.lock(); defer { lock.unlock() }; return config.brandingOverlayURL }
        set { setBrandingOverlayURL(newValue) }
    }

    public var mirrored: Bool {
        get { lock.lock(); defer { lock.unlock() }; return config.mirrored }
        set { lock.lock(); config.mirrored = newValue; lock.unlock() }
    }

    public var aspectRatio: WebcamAspectRatio {
        get { lock.lock(); defer { lock.unlock() }; return config.aspectRatio }
        set {
            lock.lock()
            config.aspectRatio = newValue
            cachedPreparedCustomImage = nil
            cachedPresetImage = nil
            lock.unlock()
        }
    }

    public weak var renderView: WebcamMetalView?

    public override init() {
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        self.segmentationRequest = req
        super.init()
    }

    /// Updates the custom image URL and triggers eager, non-blocking asynchronous
    /// image loading on a background queue to keep `videoQueue` free of disk I/O.
    public func setCustomImageURL(_ url: URL?) {
        lock.lock()
        guard config.customImageURL != url else {
            lock.unlock()
            return
        }
        config.customImageURL = url
        cachedCustomImage = nil
        cachedCustomImageURL = nil
        cachedPreparedCustomImage = nil
        lastPreparedCustomImageURL = nil
        lock.unlock()

        guard let targetURL = url else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let loaded = CIImage(contentsOf: targetURL, options: [.applyOrientationProperty: true]) else {
                self.log.error("Failed to load custom background image from \(targetURL.lastPathComponent, privacy: .public)")
                return
            }
            self.lock.lock()
            // Verify URL hasn't changed while loading
            if self.config.customImageURL == targetURL {
                self.cachedCustomImage = loaded
                self.cachedCustomImageURL = targetURL
                self.cachedPreparedCustomImage = nil
            }
            self.lock.unlock()
            self.onAssetLoaded?()
        }
    }

    /// Updates the transparent branding overlay URL and triggers eager asynchronous loading.
    public func setBrandingOverlayURL(_ url: URL?) {
        lock.lock()
        guard config.brandingOverlayURL != url else {
            lock.unlock()
            return
        }
        config.brandingOverlayURL = url
        cachedBrandingImage = nil
        cachedBrandingImageURL = nil
        lock.unlock()

        guard let targetURL = url else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let loaded = CIImage(contentsOf: targetURL, options: [.applyOrientationProperty: true]) else {
                self.log.error("Failed to load branding overlay image from \(targetURL.lastPathComponent, privacy: .public)")
                return
            }
            self.lock.lock()
            if self.config.brandingOverlayURL == targetURL {
                self.cachedBrandingImage = loaded
                self.cachedBrandingImageURL = targetURL
            }
            self.lock.unlock()
            self.onAssetLoaded?()
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    // MARK: - Frame Processing Entry Points

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processPixelBuffer(pixelBuffer, from: .camera)
    }

    /// Process a frame directly from a CVPixelBuffer (e.g. from AVCaptureSession or looping video playback).
    public func processPixelBuffer(_ pixelBuffer: CVPixelBuffer, from source: WebcamSourceType = .camera) {
        lock.lock()
        guard activeSource == source else {
            lock.unlock()
            return
        }
        if frameInFlight {
            lock.unlock()
            return
        }
        frameInFlight = true
        lock.unlock()

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.frameInFlight = false
                self.lock.unlock()
            }
            self.lock.lock()
            let matchesSource = (self.activeSource == source)
            self.lock.unlock()
            guard matchesSource else { return }

            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
            self.processSource(sourceImage: sourceImage, pixelBufferForVision: pixelBuffer, source: source)
        }
    }

    /// Process a static image directly (e.g. user-selected static avatar/profile image).
    public func processImage(_ sourceImage: CIImage) {
        lock.lock()
        guard activeSource == .staticImage else {
            lock.unlock()
            return
        }
        lock.unlock()

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let matchesSource = (self.activeSource == .staticImage)
            self.lock.unlock()
            guard matchesSource else { return }

            self.processSource(sourceImage: sourceImage, pixelBufferForVision: nil, source: .staticImage)
        }
    }

    /// Clears the rendered frame on the serial processing queue, ensuring it runs strictly after any in-flight frames.
    public func clearCanvas(size: CGSize) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                .cropped(to: CGRect(origin: .zero, size: size))
            self.deliverFrame(clear)
        }
    }

    private func processSource(sourceImage: CIImage, pixelBufferForVision: CVPixelBuffer?, source: WebcamSourceType) {
        let sourceExtent = sourceImage.extent
        guard sourceExtent.width > 0 && sourceExtent.height > 0 else { return }

        // Snapshot all configuration and cached assets once at the top.
        // No further locks are acquired during frame processing or rendering.
        lock.lock()
        var snapConfig = self.config
        if source != .camera {
            snapConfig.mirrored = false
        }
        let snapCustomImage = self.cachedCustomImage
        let snapBrandingImage = self.cachedBrandingImage
        lock.unlock()

        let cropRect = Self.centeredCropRect(source: sourceExtent.size, ratio: snapConfig.aspectRatio.ratio)
        let cropSize = cropRect.size
        let finalCropWidth = cropRect.width

        lock.lock()
        let snapPresetImage = (self.lastCachedPreset == snapConfig.backgroundPreset &&
                               self.lastCachedPresetSize == cropSize) ? self.cachedPresetImage : nil
        let snapPreparedCustomImage = (self.lastPreparedCustomImageURL == snapConfig.customImageURL &&
                                       self.lastPreparedCustomImageSize == cropSize &&
                                       self.lastPreparedBlurCustomImage == snapConfig.blurCustomImage &&
                                       self.lastPreparedBlurStrength == snapConfig.blurStrength) ? self.cachedPreparedCustomImage : nil
        lock.unlock()

        let croppedSource = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

        var finalImage: CIImage

        if snapConfig.mode == .none {
            // Passthrough with zero segmentation overhead
            finalImage = applyMirror(image: croppedSource, width: finalCropWidth, mirrored: snapConfig.mirrored)
        } else {
            // Concurrency Note on Request Reuse:
            // `segmentationRequest` is sequentially reused across frames. This is safe
            // and supported by Vision because all `handler.perform` calls and subsequent
            // reads from `segmentationRequest.results` execute serially on `videoQueue`.
            let handler: VNImageRequestHandler
            if let pBuf = pixelBufferForVision {
                handler = VNImageRequestHandler(cvPixelBuffer: pBuf, options: [:])
            } else {
                handler = VNImageRequestHandler(ciImage: sourceImage, options: [:])
            }

            do {
                try handler.perform([segmentationRequest])
            } catch {
                log.error("Person segmentation failed: \(error.localizedDescription, privacy: .public)")
                finalImage = applyMirror(image: croppedSource, width: finalCropWidth, mirrored: snapConfig.mirrored)
                if let snapBranding = snapBrandingImage {
                    finalImage = applyBrandingOverlay(image: finalImage, overlay: snapBranding, size: cropSize)
                }
                deliverFrame(finalImage)
                return
            }

            guard let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer else {
                finalImage = applyMirror(image: croppedSource, width: finalCropWidth, mirrored: snapConfig.mirrored)
                if let snapBranding = snapBrandingImage {
                    finalImage = applyBrandingOverlay(image: finalImage, overlay: snapBranding, size: cropSize)
                }
                deliverFrame(finalImage)
                return
            }

            let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            let scaleX = sourceExtent.width / maskImage.extent.width
            let scaleY = sourceExtent.height / maskImage.extent.height
            let scaledMask = maskImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: cropRect)
                .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

            // Build target background using purely snapshotted state (lock-free)
            let background = resolveBackground(
                config: snapConfig,
                cachedCustomImage: snapCustomImage,
                cachedPresetImage: snapPresetImage,
                cachedPreparedCustomImage: snapPreparedCustomImage,
                source: croppedSource,
                size: cropSize
            )

            // Blend foreground person over background using the matte mask
            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = croppedSource
            blendFilter.backgroundImage = background
            blendFilter.maskImage = scaledMask

            let composited = blendFilter.outputImage ?? croppedSource
            finalImage = applyMirror(image: composited, width: finalCropWidth, mirrored: snapConfig.mirrored)
        }

        // Composite transparent branding overlay (if configured) on top of the mirrored presenter feed
        if let snapBranding = snapBrandingImage {
            finalImage = applyBrandingOverlay(image: finalImage, overlay: snapBranding, size: cropSize)
        }

        deliverFrame(finalImage)
    }

    private func deliverFrame(_ finalImage: CIImage) {
        renderView?.update(image: finalImage)
        onFrameProcessed?(finalImage)
    }

    private func applyBrandingOverlay(image: CIImage, overlay: CIImage, size: CGSize) -> CIImage {
        let extent = overlay.extent
        guard extent.width > 0 && extent.height > 0 && size.width > 0 && size.height > 0 else {
            return image
        }
        let scale = min(size.width / extent.width, size.height / extent.height)
        let scaled = overlay
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offsetX = max(0, (size.width - scaled.extent.width) / 2.0)
        let offsetY = max(0, (size.height - scaled.extent.height) / 2.0)
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        let filter = CIFilter.sourceOverCompositing()
        filter.inputImage = positioned
        filter.backgroundImage = image
        return filter.outputImage ?? image
    }

    // MARK: - Helpers

    /// Computes a centered crop rectangle fitting the desired aspect ratio within source dimensions.
    public static func centeredCropRect(source: CGSize, ratio targetRatio: CGFloat) -> CGRect {
        guard source.width > 0 && source.height > 0 && targetRatio > 0 else {
            return CGRect(origin: .zero, size: source)
        }
        let sourceRatio = source.width / source.height
        let cropWidth: CGFloat
        let cropHeight: CGFloat

        if sourceRatio > targetRatio {
            // Source is wider than target -> fit height, crop width
            cropHeight = source.height
            cropWidth = round(cropHeight * targetRatio)
        } else {
            // Source is taller than target -> fit width, crop height
            cropWidth = source.width
            cropHeight = round(cropWidth / targetRatio)
        }

        let finalCropWidth = min(cropWidth, source.width)
        let finalCropHeight = min(cropHeight, source.height)
        let cropOriginX = max(0, round((source.width - finalCropWidth) / 2.0))
        let cropOriginY = max(0, round((source.height - finalCropHeight) / 2.0))
        return CGRect(
            x: cropOriginX,
            y: cropOriginY,
            width: finalCropWidth,
            height: finalCropHeight
        )
    }

    private func applyMirror(image: CIImage, width: CGFloat, mirrored: Bool) -> CIImage {
        guard mirrored else { return image }
        return image
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: width, y: 0))
    }

    /// Background resolver using snapshotted configuration and cached assets
    /// (lock-free on hot path; performs standalone lock write-back only on cache miss).
    private func resolveBackground(
        config: Config,
        cachedCustomImage: CIImage?,
        cachedPresetImage: CIImage?,
        cachedPreparedCustomImage: CIImage?,
        source: CIImage,
        size: CGSize
    ) -> CIImage {
        switch config.mode {
        case .none:
            return source

        case .blur:
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = source.clampedToExtent()
            blur.radius = Float(config.blurStrength.sigma)
            return blur.outputImage?.cropped(to: source.extent) ?? source

        case .preset:
            if let cached = cachedPresetImage {
                return cached
            }
            let generated = config.backgroundPreset.makeImage(size: size)
            // Opportunistically cache for subsequent frames
            lock.lock()
            self.cachedPresetImage = generated
            self.lastCachedPreset = config.backgroundPreset
            self.lastCachedPresetSize = size
            lock.unlock()
            return generated

        case .customImage:
            if let cachedPrepared = cachedPreparedCustomImage {
                return cachedPrepared
            }
            if let cached = cachedCustomImage {
                let extent = cached.extent
                guard extent.width > 0 && extent.height > 0 else {
                    return fallbackWarmStudio(size: size)
                }
                let scale = max(size.width / extent.width, size.height / extent.height)
                let scaled = cached
                    .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let cropOriginX = max(0, (scaled.extent.width - size.width) / 2.0)
                let cropOriginY = max(0, (scaled.extent.height - size.height) / 2.0)
                let prepared = scaled
                    .cropped(to: CGRect(x: cropOriginX, y: cropOriginY, width: size.width, height: size.height))
                    .transformed(by: CGAffineTransform(translationX: -cropOriginX, y: -cropOriginY))

                let finalCustomBg: CIImage
                if config.blurCustomImage {
                    let blur = CIFilter.gaussianBlur()
                    blur.inputImage = prepared.clampedToExtent()
                    blur.radius = Float(config.blurStrength.sigma)
                    finalCustomBg = blur.outputImage?.cropped(to: CGRect(origin: .zero, size: size)) ?? prepared
                } else {
                    finalCustomBg = prepared
                }

                let targetRect = CGRect(origin: .zero, size: size)
                let materialized = prepareContext.createCGImage(finalCustomBg, from: targetRect)
                    .map { CIImage(cgImage: $0) } ?? finalCustomBg

                lock.lock()
                self.cachedPreparedCustomImage = materialized
                self.lastPreparedCustomImageURL = config.customImageURL
                self.lastPreparedCustomImageSize = size
                self.lastPreparedBlurCustomImage = config.blurCustomImage
                self.lastPreparedBlurStrength = config.blurStrength
                lock.unlock()
                return materialized
            }
            return fallbackWarmStudio(size: size)

        case .cutout:
            // Transparent background: Blend with mask will composite foreground person
            // over 0-alpha clear pixels, producing an alpha-channel silhouette.
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: source.extent)
        }
    }

    private func fallbackWarmStudio(size: CGSize) -> CIImage {
        lock.lock()
        if let fallback = self.cachedPresetImage,
           self.lastCachedPreset == .warmStudio,
           self.lastCachedPresetSize == size {
            lock.unlock()
            return fallback
        }
        lock.unlock()
        let generated = WebcamBackgroundPreset.warmStudio.makeImage(size: size)
        lock.lock()
        self.cachedPresetImage = generated
        self.lastCachedPreset = .warmStudio
        self.lastCachedPresetSize = size
        lock.unlock()
        return generated
    }
}
