@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import OSLog
import QuartzCore
import UniformTypeIdentifiers

/// Position of the webcam overlay on the chosen display.
public enum WebcamCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// One of three preset sizes for the webcam picture-in-picture window.
public enum WebcamSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }
    public var pixels: CGSize {
        switch self {
        case .small:  return CGSize(width: 160, height: 160)
        case .medium: return CGSize(width: 220, height: 220)
        case .large:  return CGSize(width: 300, height: 300)
        }
    }
    public var displayName: String { rawValue.capitalized }

    /// Frame dimensions calculated from chosen shape and aspect ratio.
    public func dimensions(shape: WebcamShape, aspectRatio: WebcamAspectRatio = .square) -> CGSize {
        guard shape == .roundedRect else {
            return pixels
        }
        switch aspectRatio {
        case .square:
            return pixels
        case .widescreen:
            switch self {
            case .small:  return CGSize(width: 240, height: 135)
            case .medium: return CGSize(width: 320, height: 180)
            case .large:  return CGSize(width: 400, height: 225)
            }
        case .classic:
            switch self {
            case .small:  return CGSize(width: 200, height: 150)
            case .medium: return CGSize(width: 280, height: 210)
            case .large:  return CGSize(width: 360, height: 270)
            }
        }
    }
}

/// A floating, rounded, draggable picture-in-picture preview of a chosen
/// `AVCaptureDevice`. Lives independently of the recording lifecycle — the
/// recorder asks for `windowID` and excepts it from its SCContentFilter so the
/// overlay appears in display / region captures.
///
/// Features hardware-accelerated Metal rendering, Neural Engine person segmentation,
/// background blur, procedural virtual backdrops, custom image replacement,
/// and transparent cutout silhouettes.
@MainActor
public final class WebcamOverlayController: ObservableObject {

    @Published public private(set) var isVisible: Bool = false
    @Published public var corner: WebcamCorner = .bottomRight {
        didSet { reposition() }
    }
    @Published public var size: WebcamSize = .medium {
        didSet { reposition() }
    }
    @Published public var shape: WebcamShape = .circle {
        didSet {
            videoProcessor.aspectRatio = (shape == .circle) ? .square : aspectRatio
            reposition()
        }
    }
    @Published public var aspectRatio: WebcamAspectRatio = .square {
        didSet {
            videoProcessor.aspectRatio = (shape == .circle) ? .square : aspectRatio
            reposition()
        }
    }
    @Published public var mirrored: Bool = true {
        didSet { videoProcessor.mirrored = mirrored }
    }
    @Published public var targetDisplayID: CGDirectDisplayID? = nil {
        didSet { reposition() }
    }

    @Published public var backgroundMode: WebcamBackgroundMode = .none {
        didSet {
            videoProcessor.backgroundMode = backgroundMode
            if let host = window?.contentView {
                updateHostStyling(host: host, size: currentDimensions)
            }
        }
    }
    @Published public var blurStrength: WebcamBlurStrength = .balanced {
        didSet { videoProcessor.blurStrength = blurStrength }
    }
    @Published public var blurCustomImage: Bool = false {
        didSet { videoProcessor.blurCustomImage = blurCustomImage }
    }
    @Published public var backgroundPreset: WebcamBackgroundPreset = .warmStudio {
        didSet { videoProcessor.backgroundPreset = backgroundPreset }
    }
    @Published public var customImageURL: URL? = nil {
        didSet { videoProcessor.customImageURL = customImageURL }
    }
    @Published public var showBorder: Bool = true {
        didSet {
            if let host = window?.contentView {
                updateHostStyling(host: host, size: currentDimensions)
            }
        }
    }
    @Published public var borderColor: CGColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) {
        didSet {
            if let host = window?.contentView {
                updateHostStyling(host: host, size: currentDimensions)
            }
        }
    }
    @Published public var borderWidth: CGFloat = 2.0 {
        didSet {
            if let host = window?.contentView {
                updateHostStyling(host: host, size: currentDimensions)
            }
        }
    }

    /// Current target frame size matching the chosen shape and aspect ratio.
    public var currentDimensions: CGSize {
        size.dimensions(shape: shape, aspectRatio: aspectRatio)
    }

    private let log = Logger(subsystem: "com.macscreenrecord.app", category: "Webcam")
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.macscreenrecord.webcam.video", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.macscreenrecord.webcam.session", qos: .userInitiated)
    private let videoProcessor = WebcamVideoProcessor()

    private var window: WebcamPanel?
    private var metalView: WebcamMetalView?
    private var currentDeviceID: String?

    public init() {
        videoProcessor.mirrored = mirrored
        videoProcessor.backgroundMode = backgroundMode
        videoProcessor.blurStrength = blurStrength
        videoProcessor.blurCustomImage = blurCustomImage
        videoProcessor.backgroundPreset = backgroundPreset
        videoProcessor.customImageURL = customImageURL
        videoProcessor.aspectRatio = (shape == .circle) ? .square : aspectRatio
    }

    /// CGWindowID of the overlay panel — used by SCContentFilter exceptions.
    public var windowID: CGWindowID? {
        guard let w = window else { return nil }
        return CGWindowID(w.windowNumber)
    }

    public func show(deviceID: String) async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw NSError(
                    domain: "Webcam",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Camera access was not granted. Enable it in System Settings › Privacy & Security › Camera."]
                )
            }
        case .denied, .restricted:
            throw NSError(
                domain: "Webcam",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Camera access is denied. Enable it in System Settings › Privacy & Security › Camera."]
            )
        @unknown default:
            break
        }
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw NSError(domain: "Webcam", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Camera not found"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        if window == nil {
            let panel = makePanel()
            self.window = panel
        }
        currentDeviceID = deviceID
        let session = captureSession
        let output = videoOutput
        let processor = videoProcessor
        let vQueue = videoQueue
        sessionQueue.async {
            Self.applySessionConfiguration(
                captureSession: session,
                videoOutput: output,
                videoProcessor: processor,
                videoQueue: vQueue,
                input: input
            )
            session.startRunning()
        }
        reposition()
        window?.orderFront(nil)
        isVisible = true
        log.info("Webcam overlay shown")
    }

    public func hide() {
        let session = captureSession
        sessionQueue.async { session.stopRunning() }
        window?.orderOut(nil)
        isVisible = false
    }

    public func setDevice(_ deviceID: String) throws {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw NSError(domain: "Webcam", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Camera not found"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        currentDeviceID = deviceID
        let session = captureSession
        let output = videoOutput
        let processor = videoProcessor
        let vQueue = videoQueue
        sessionQueue.async {
            Self.applySessionConfiguration(
                captureSession: session,
                videoOutput: output,
                videoProcessor: processor,
                videoQueue: vQueue,
                input: input
            )
        }
    }

    /// Prompts the user to select an image from disk and returns its URL if chosen.
    public func pickCustomImage() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a background image for webcam PIP"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            return url
        }
        return nil
    }

    // MARK: - Internals

    nonisolated private static func applySessionConfiguration(
        captureSession: AVCaptureSession,
        videoOutput: AVCaptureVideoDataOutput,
        videoProcessor: WebcamVideoProcessor,
        videoQueue: DispatchQueue,
        input: AVCaptureDeviceInput
    ) {
        captureSession.beginConfiguration()
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(videoProcessor, queue: videoQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if captureSession.canSetSessionPreset(.medium) { captureSession.sessionPreset = .medium }
        captureSession.commitConfiguration()
    }

    private func makePanel() -> WebcamPanel {
        let frame = NSRect(origin: .zero, size: currentDimensions)
        let panel = WebcamPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        let host = NSView(frame: frame)
        host.wantsLayer = true

        let metal = WebcamMetalView(frame: host.bounds)
        metal.autoresizingMask = [.width, .height]
        host.addSubview(metal)

        self.metalView = metal
        self.videoProcessor.renderView = metal

        updateHostStyling(host: host, size: currentDimensions)
        panel.contentView = host
        return panel
    }

    private func updateHostStyling(host: NSView, size: CGSize) {
        let isCircle = (shape == .circle)
        let radius: CGFloat = isCircle ? min(size.width, size.height) / 2 : 18
        host.layer?.cornerRadius = radius
        if #available(macOS 10.15, *) {
            host.layer?.cornerCurve = isCircle ? .circular : .continuous
        }

        if showBorder && borderWidth > 0 {
            host.layer?.borderColor = borderColor
            host.layer?.borderWidth = borderWidth
            host.layer?.masksToBounds = true
            metalView?.layer?.masksToBounds = true
        } else {
            host.layer?.borderColor = nil
            host.layer?.borderWidth = 0
            if backgroundMode == .cutout {
                host.layer?.masksToBounds = false
                metalView?.layer?.masksToBounds = false
            } else {
                host.layer?.masksToBounds = true
                metalView?.layer?.masksToBounds = true
            }
        }
        metalView?.layer?.cornerRadius = radius
        if #available(macOS 10.15, *) {
            metalView?.layer?.cornerCurve = isCircle ? .circular : .continuous
        }
        window?.invalidateShadow()
    }

    private func reposition() {
        guard let panel = window,
              let targetScreen = (targetDisplayID.flatMap { id in
                  NSScreen.screens.first(where: {
                      guard let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                      return CGDirectDisplayID(num.uint32Value) == id
                  })
              } ?? NSScreen.main ?? NSScreen.screens.first) else { return }

        let target = currentDimensions
        let visibleFrame = targetScreen.visibleFrame
        let margin: CGFloat = 24
        let origin: NSPoint
        switch corner {
        case .topLeft:
            origin = NSPoint(
                x: visibleFrame.minX + margin,
                y: visibleFrame.maxY - target.height - margin
            )
        case .topRight:
            origin = NSPoint(
                x: visibleFrame.maxX - target.width - margin,
                y: visibleFrame.maxY - target.height - margin
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visibleFrame.minX + margin,
                y: visibleFrame.minY + margin
            )
        case .bottomRight:
            origin = NSPoint(
                x: visibleFrame.maxX - target.width - margin,
                y: visibleFrame.minY + margin
            )
        }
        panel.setFrame(NSRect(origin: origin, size: target), display: true, animate: false)

        if let host = panel.contentView {
            host.frame = NSRect(origin: .zero, size: target)
            metalView?.frame = host.bounds
            updateHostStyling(host: host, size: target)
        }
    }
}

/// NSPanel subclass so the window can become key for keyboard input but
/// doesn't activate the app — we want the underlying app to keep focus.
private final class WebcamPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
