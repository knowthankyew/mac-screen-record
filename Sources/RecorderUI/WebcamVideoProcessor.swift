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
        var backgroundPreset: WebcamBackgroundPreset = .warmStudio
        var customImageURL: URL? = nil
        var mirrored: Bool = true
    }

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "WebcamProcessor")
    private let segmentationRequest: VNGeneratePersonSegmentationRequest
    private let lock = NSLock()

    // Guarded by lock
    private var config = Config()
    private var cachedCustomImage: CIImage?
    private var cachedCustomImageURL: URL?
    private var cachedPresetImage: CIImage?
    private var lastCachedPreset: WebcamBackgroundPreset?
    private var lastCachedPresetSize: CGSize = .zero

    // Thread-safe public properties
    public var backgroundMode: WebcamBackgroundMode {
        get { lock.lock(); defer { lock.unlock() }; return config.mode }
        set { lock.lock(); config.mode = newValue; lock.unlock() }
    }

    public var blurStrength: WebcamBlurStrength {
        get { lock.lock(); defer { lock.unlock() }; return config.blurStrength }
        set { lock.lock(); config.blurStrength = newValue; lock.unlock() }
    }

    public var backgroundPreset: WebcamBackgroundPreset {
        get { lock.lock(); defer { lock.unlock() }; return config.backgroundPreset }
        set { lock.lock(); config.backgroundPreset = newValue; lock.unlock() }
    }

    public var customImageURL: URL? {
        get { lock.lock(); defer { lock.unlock() }; return config.customImageURL }
        set { setCustomImageURL(newValue) }
    }

    public var mirrored: Bool {
        get { lock.lock(); defer { lock.unlock() }; return config.mirrored }
        set { lock.lock(); config.mirrored = newValue; lock.unlock() }
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
        lock.unlock()

        guard let targetURL = url else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let loaded = CIImage(contentsOf: targetURL) else {
                self.log.error("Failed to load custom background image from \(targetURL.path, privacy: .public)")
                return
            }
            self.lock.lock()
            // Verify URL hasn't changed while loading
            if self.config.customImageURL == targetURL {
                self.cachedCustomImage = loaded
                self.cachedCustomImageURL = targetURL
            }
            self.lock.unlock()
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceExtent = sourceImage.extent
        guard sourceExtent.width > 0 && sourceExtent.height > 0 else { return }

        let minDim = min(sourceExtent.width, sourceExtent.height)
        let cropRect = CGRect(
            x: (sourceExtent.width - minDim) / 2.0,
            y: (sourceExtent.height - minDim) / 2.0,
            width: minDim,
            height: minDim
        )

        // Snapshot all configuration and cached assets once at the top.
        // No further locks are acquired during frame processing or rendering.
        lock.lock()
        let snapConfig = self.config
        let snapCustomImage = self.cachedCustomImage
        let snapPresetImage = (self.lastCachedPreset == snapConfig.backgroundPreset &&
                               self.lastCachedPresetSize == CGSize(width: minDim, height: minDim)) ? self.cachedPresetImage : nil
        lock.unlock()

        let squareSource = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

        let finalImage: CIImage

        if snapConfig.mode == .none {
            // Passthrough with zero segmentation overhead
            finalImage = applyMirror(image: squareSource, width: minDim, mirrored: snapConfig.mirrored)
        } else {
            // Concurrency Note on Request Reuse:
            // `segmentationRequest` is sequentially reused across frames. This is safe
            // and supported by Vision because all `handler.perform` calls and subsequent
            // reads from `segmentationRequest.results` execute serially on `videoQueue`.
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([segmentationRequest])
            } catch {
                log.error("Person segmentation failed: \(error.localizedDescription, privacy: .public)")
                finalImage = applyMirror(image: squareSource, width: minDim, mirrored: snapConfig.mirrored)
                renderView?.update(image: finalImage)
                return
            }

            guard let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer else {
                finalImage = applyMirror(image: squareSource, width: minDim, mirrored: snapConfig.mirrored)
                renderView?.update(image: finalImage)
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
                squareSource: squareSource,
                size: CGSize(width: minDim, height: minDim)
            )

            // Blend foreground person over background using the matte mask
            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = squareSource
            blendFilter.backgroundImage = background
            blendFilter.maskImage = scaledMask

            let composited = blendFilter.outputImage ?? squareSource
            finalImage = applyMirror(image: composited, width: minDim, mirrored: snapConfig.mirrored)
        }

        renderView?.update(image: finalImage)
    }

    // MARK: - Helpers

    private func applyMirror(image: CIImage, width: CGFloat, mirrored: Bool) -> CIImage {
        guard mirrored else { return image }
        return image
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: width, y: 0))
    }

    /// Background resolver using snapshotted configuration and cached assets
    /// (lock-free on hot path; performs standalone lock write-back only on preset cache miss).
    private func resolveBackground(
        config: Config,
        cachedCustomImage: CIImage?,
        cachedPresetImage: CIImage?,
        squareSource: CIImage,
        size: CGSize
    ) -> CIImage {
        switch config.mode {
        case .none:
            return squareSource

        case .blur:
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = squareSource.clampedToExtent()
            blur.radius = Float(config.blurStrength.sigma)
            return blur.outputImage?.cropped(to: squareSource.extent) ?? squareSource

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
            if let cached = cachedCustomImage {
                let extent = cached.extent
                let scale = max(size.width / extent.width, size.height / extent.height)
                let scaled = cached
                    .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let cropOriginX = (scaled.extent.width - size.width) / 2.0
                let cropOriginY = (scaled.extent.height - size.height) / 2.0
                return scaled
                    .cropped(to: CGRect(x: cropOriginX, y: cropOriginY, width: size.width, height: size.height))
                    .transformed(by: CGAffineTransform(translationX: -cropOriginX, y: -cropOriginY))
            }
            // Fallback while custom image loads asynchronously in background
            return WebcamBackgroundPreset.warmStudio.makeImage(size: size)

        case .cutout:
            // Transparent background: Blend with mask will composite foreground person
            // over 0-alpha clear pixels, producing an alpha-channel silhouette.
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: squareSource.extent)
        }
    }
}
