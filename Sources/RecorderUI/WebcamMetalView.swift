import AppKit
import CoreGraphics
import CoreImage
import Metal
import MetalKit

/// A high-performance, layer-backed Metal view that renders `CIImage` frames
/// with zero CPU copies and hardware transparency support.
public final class WebcamMetalView: MTKView, MTKViewDelegate {

    private var ciContext: CIContext?
    private var commandQueue: MTLCommandQueue?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var currentImage: CIImage?
    private let lock = NSLock()

    public init(frame: NSRect) {
        let defaultDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: frame, device: defaultDevice)
        setup()
    }

    public required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let dev = device ?? MTLCreateSystemDefaultDevice() else { return }
        self.device = dev
        self.commandQueue = dev.makeCommandQueue()
        self.ciContext = CIContext(mtlDevice: dev, options: [
            .cacheIntermediates: false,
            .priorityRequestLow: false
        ])

        self.delegate = self
        self.framebufferOnly = false
        self.enableSetNeedsDisplay = false
        self.isPaused = true
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.wantsLayer = true
        self.layer?.isOpaque = false
    }

    private var isDrawPending = false

    /// Feeds a new composited `CIImage` frame to be rendered.
    public func update(image: CIImage) {
        lock.lock()
        currentImage = image
        if isDrawPending {
            lock.unlock()
            return
        }
        isDrawPending = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.isDrawPending = false
            self.lock.unlock()
            self.draw()
        }
    }

    // MARK: - MTKViewDelegate

    private let inFlightSemaphore = DispatchSemaphore(value: 3)

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        lock.lock()
        guard let image = currentImage else {
            lock.unlock()
            return
        }
        lock.unlock()

        let targetSize = view.drawableSize
        guard targetSize.width > 0 && targetSize.height > 0 else { return }

        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 else { return }

        guard inFlightSemaphore.wait(timeout: .now()) == .success else {
            return
        }

        guard let currentDrawable = view.currentDrawable,
              let commandQueue = self.commandQueue,
              let ciContext = self.ciContext,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        // Scale image to match the view's backing drawable dimensions
        let scaleX = targetSize.width / extent.width
        let scaleY = targetSize.height / extent.height
        let scaledImage = image
            .transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        ciContext.render(
            scaledImage,
            to: currentDrawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: targetSize),
            colorSpace: colorSpace
        )

        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
