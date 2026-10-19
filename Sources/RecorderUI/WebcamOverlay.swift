@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import CoreImage
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

    public var normalizedPoint: CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: 0.0, y: 1.0)
        case .topRight:    return CGPoint(x: 1.0, y: 1.0)
        case .bottomLeft:  return CGPoint(x: 0.0, y: 0.0)
        case .bottomRight: return CGPoint(x: 1.0, y: 0.0)
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
        guard shape.supportsAspectRatio else {
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
    @Published public var lastError: String? = nil
    @Published public var sourceType: WebcamSourceType = .camera {
        didSet {
            guard oldValue != sourceType else { return }
            updateSource()
        }
    }
    @Published public var staticImageURL: URL? = nil {
        didSet {
            guard oldValue != staticImageURL else { return }
            cachedStaticCIImage = nil
            failedStaticImageURL = nil
            if sourceType == .staticImage { updateSource() }
        }
    }
    @Published public var videoClipURL: URL? = nil {
        didSet {
            guard oldValue != videoClipURL else { return }
            if sourceType == .videoClip { updateSource() }
        }
    }
    public let backdropOverlay = PresenterBackdropOverlay()

    public var backdropEnabled: Bool {
        get { backdropOverlay.isEnabled }
        set {
            backdropOverlay.isEnabled = newValue
            if newValue, let p = window {
                backdropOverlay.show(targetScreen: p.screen, pipFrame: p.frame, relativeTo: p)
            }
        }
    }

    public var backdropImageURL: URL? {
        get { backdropOverlay.imageURL }
        set {
            backdropOverlay.imageURL = newValue
            if backdropOverlay.isEnabled, let p = window {
                backdropOverlay.show(targetScreen: p.screen, pipFrame: p.frame, relativeTo: p)
            }
        }
    }

    private var isTrackingUserMove = false
    @Published public var pipNormalizedPosition: CGPoint = CGPoint(x: 1.0, y: 0.0) {
        didSet {
            guard !isTrackingUserMove else { return }
            reposition()
        }
    }

    @Published public var corner: WebcamCorner = .bottomRight {
        didSet { snapTo(corner: corner) }
    }
    @Published public var size: WebcamSize = .medium {
        didSet { reposition() }
    }
    @Published public var shape: WebcamShape = .circle {
        didSet {
            videoProcessor.aspectRatio = shape.supportsAspectRatio ? aspectRatio : .square
            reposition()
            refreshStaticFrameIfNeeded()
        }
    }
    @Published public var aspectRatio: WebcamAspectRatio = .square {
        didSet {
            videoProcessor.aspectRatio = shape.supportsAspectRatio ? aspectRatio : .square
            reposition()
            refreshStaticFrameIfNeeded()
        }
    }
    @Published public var mirrored: Bool = true {
        didSet {
            videoProcessor.mirrored = mirrored
            refreshStaticFrameIfNeeded()
        }
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
            refreshStaticFrameIfNeeded()
        }
    }
    @Published public var blurStrength: WebcamBlurStrength = .balanced {
        didSet {
            videoProcessor.blurStrength = blurStrength
            refreshStaticFrameIfNeeded()
        }
    }
    @Published public var blurCustomImage: Bool = false {
        didSet {
            videoProcessor.blurCustomImage = blurCustomImage
            refreshStaticFrameIfNeeded()
        }
    }
    @Published public var backgroundPreset: WebcamBackgroundPreset = .warmStudio {
        didSet {
            videoProcessor.backgroundPreset = backgroundPreset
            refreshStaticFrameIfNeeded()
        }
    }
    @Published public var customImageURL: URL? = nil {
        didSet {
            videoProcessor.customImageURL = customImageURL
            refreshStaticFrameIfNeeded()
        }
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
    private var overlayView: PassthroughView?
    private var currentDeviceID: String?
    private var borderShapeLayer: CAShapeLayer?
    private var maskShapeLayer: CAShapeLayer?
    private var mediaLoopPlayer: WebcamMediaLoopPlayer?
    private var cachedStaticCIImage: CIImage?
    private var failedStaticImageURL: URL?

    public init() {
        videoProcessor.mirrored = mirrored
        videoProcessor.backgroundMode = backgroundMode
        videoProcessor.blurStrength = blurStrength
        videoProcessor.blurCustomImage = blurCustomImage
        videoProcessor.backgroundPreset = backgroundPreset
        videoProcessor.customImageURL = customImageURL
        videoProcessor.aspectRatio = shape.supportsAspectRatio ? aspectRatio : .square
        videoProcessor.onAssetLoaded = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshStaticFrameIfNeeded()
            }
        }
    }

    /// CGWindowID of the overlay panel — used by SCContentFilter exceptions.
    public var windowID: CGWindowID? {
        guard let w = window else { return nil }
        return CGWindowID(w.windowNumber)
    }

    /// CGWindowID of the resizable backdrop plate panel.
    public var backdropWindowID: CGWindowID? {
        backdropOverlay.windowID
    }

    public func show(deviceID: String) async throws {
        currentDeviceID = deviceID

        var cameraInput: AVCaptureDeviceInput?
        if sourceType == .camera {
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
            cameraInput = try AVCaptureDeviceInput(device: device)
        }

        // Present panel ONLY after camera authorization and device lookup succeed (or for non-camera sources)
        if window == nil {
            let panel = makePanel()
            self.window = panel
        }
        reposition()
        if let panel = window {
            panel.orderFront(nil)
            backdropOverlay.show(targetScreen: panel.screen, pipFrame: panel.frame, relativeTo: panel)
        }
        isVisible = true
        videoProcessor.acceptedSource = sourceType

        if let input = cameraInput {
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
        } else {
            updateSource()
        }
        log.info("Webcam overlay shown (source: \(self.sourceType.rawValue, privacy: .public))")
    }

    public func hide() {
        let session = captureSession
        sessionQueue.async { session.stopRunning() }
        mediaLoopPlayer?.stop()
        mediaLoopPlayer = nil
        clearCanvas()
        backdropOverlay.hide()
        window?.orderOut(nil)
        isVisible = false
    }

    private func clearCanvas() {
        videoProcessor.clearCanvas(size: currentDimensions)
    }

    private func refreshStaticFrameIfNeeded() {
        guard isVisible, sourceType == .staticImage else { return }
        if let img = cachedStaticCIImage {
            videoProcessor.processImage(img)
        } else if let url = staticImageURL, url != failedStaticImageURL {
            if let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
                cachedStaticCIImage = img
                failedStaticImageURL = nil
                videoProcessor.processImage(img)
            } else {
                failedStaticImageURL = url
                lastError = "Couldn't load avatar image \(url.lastPathComponent)."
                clearCanvas()
            }
        }
    }

    private func updateSource() {
        guard isVisible else { return }
        switch sourceType {
        case .camera:
            videoProcessor.acceptedSource = .camera
            mediaLoopPlayer?.stop()
            mediaLoopPlayer = nil
            let devID = (currentDeviceID?.isEmpty == false) ? currentDeviceID! : (AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified).devices.first?.uniqueID ?? "")
            guard !devID.isEmpty else {
                lastError = "No camera available."
                clearCanvas()
                return
            }
            let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if authStatus == .notDetermined {
                clearCanvas()
                Task { @MainActor [weak self] in
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    guard let self, self.sourceType == .camera else { return }
                    if granted {
                        self.updateSource()
                    } else {
                        self.lastError = "Camera access was not granted. Enable it in System Settings › Privacy & Security › Camera."
                    }
                }
                return
            }
            guard authStatus == .authorized else {
                lastError = "Camera access is denied. Enable it in System Settings › Privacy & Security › Camera."
                clearCanvas()
                return
            }
            currentDeviceID = devID
            do {
                try setDevice(devID)
                let session = captureSession
                sessionQueue.async {
                    if !session.isRunning { session.startRunning() }
                }
            } catch {
                lastError = "Couldn't start webcam: \(error.localizedDescription)"
                clearCanvas()
            }
        case .staticImage:
            videoProcessor.acceptedSource = .staticImage
            let session = captureSession
            sessionQueue.async {
                if session.isRunning { session.stopRunning() }
            }
            mediaLoopPlayer?.stop()
            mediaLoopPlayer = nil
            refreshStaticFrameIfNeeded()
            if cachedStaticCIImage == nil {
                clearCanvas()
            }
        case .videoClip:
            videoProcessor.acceptedSource = .videoClip
            let session = captureSession
            sessionQueue.async {
                if session.isRunning { session.stopRunning() }
            }
            cachedStaticCIImage = nil
            clearCanvas()
            if let url = videoClipURL {
                let player = mediaLoopPlayer ?? WebcamMediaLoopPlayer(processor: videoProcessor)
                player.onError = { [weak self] errorMessage in
                    Task { @MainActor [weak self] in
                        self?.lastError = errorMessage
                        self?.clearCanvas()
                    }
                }
                mediaLoopPlayer = player
                player.start(url: url)
            } else {
                mediaLoopPlayer?.stop()
                mediaLoopPlayer = nil
            }
        }
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
        panel.message = "Choose a background image for presenter PiP"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            return url
        }
        return nil
    }

    /// Prompts the user to select a static image avatar from disk.
    public func pickStaticImage() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a static image avatar for presenter PiP"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            return url
        }
        return nil
    }

    /// Prompts the user to select a video clip to loop as presenter PiP.
    public func pickVideoClip() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.message = "Choose a video file to loop for presenter PiP"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            return url
        }
        return nil
    }

    /// Prompts the user to select an image (PNG, JPG, etc.) for the presenter backdrop plate.
    public func pickBackdropImage() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .image]
        panel.message = "Choose a backdrop image (PNG, JPG, etc.)"
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

        let overlay = PassthroughView(frame: host.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.zPosition = 1000
        host.addSubview(overlay, positioned: .above, relativeTo: metal)

        self.metalView = metal
        self.overlayView = overlay
        self.videoProcessor.renderView = metal

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let p = self.window, let screen = p.screen else { return }
                let frame = p.frame
                let vFrame = screen.visibleFrame
                let margin: CGFloat = 24
                let minX = vFrame.minX + margin
                let maxX = max(minX, vFrame.maxX - frame.width - margin)
                let minY = vFrame.minY + margin
                let maxY = max(minY, vFrame.maxY - frame.height - margin)
                let normX = (maxX > minX) ? max(0, min(1, (frame.minX - minX) / (maxX - minX))) : 1.0
                let normY = (maxY > minY) ? max(0, min(1, (frame.minY - minY) / (maxY - minY))) : 0.0
                self.isTrackingUserMove = true
                self.pipNormalizedPosition = CGPoint(x: normX, y: normY)
                self.isTrackingUserMove = false
                self.backdropOverlay.updatePiPFrame(frame, on: screen)
            }
        }

        updateHostStyling(host: host, size: currentDimensions)
        panel.contentView = host
        return panel
    }

    private func updateHostStyling(host: NSView, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let shapePath = shape.path(in: bounds)

        // Mask metalView to exact vector shape path
        if maskShapeLayer == nil {
            let mask = CAShapeLayer()
            self.maskShapeLayer = mask
            metalView?.layer?.mask = mask
        }
        maskShapeLayer?.frame = bounds
        maskShapeLayer?.path = shapePath

        // Draw vector border stroke following exact perimeter on top of metalView
        if borderShapeLayer == nil {
            let border = CAShapeLayer()
            border.fillColor = nil
            border.lineJoin = .round
            border.lineCap = .round
            border.zPosition = 1000
            self.borderShapeLayer = border
            overlayView?.layer?.addSublayer(border)
        }
        borderShapeLayer?.zPosition = 1000
        borderShapeLayer?.frame = bounds
        let inset = (showBorder && borderWidth > 0) ? borderWidth / 2 : 0
        borderShapeLayer?.path = shape.path(in: bounds.insetBy(dx: inset, dy: inset))
        if showBorder && borderWidth > 0 {
            borderShapeLayer?.lineWidth = borderWidth
            borderShapeLayer?.strokeColor = borderColor
        } else {
            borderShapeLayer?.lineWidth = 0
            borderShapeLayer?.strokeColor = nil
        }

        host.layer?.cornerRadius = 0
        host.layer?.borderWidth = 0
        metalView?.layer?.cornerRadius = 0
        metalView?.layer?.borderWidth = 0

        window?.invalidateShadow()
    }

    public func snapTo(corner: WebcamCorner) {
        pipNormalizedPosition = corner.normalizedPoint
    }

    public func snapTo(position: PresenterSnapPosition) {
        pipNormalizedPosition = position.normalizedPoint
    }

    public func reposition() {
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
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - target.width - margin)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - target.height - margin)

        let posX = minX + max(0, min(1, pipNormalizedPosition.x)) * (maxX - minX)
        let posY = minY + max(0, min(1, pipNormalizedPosition.y)) * (maxY - minY)
        let newPipFrame = NSRect(x: posX, y: posY, width: target.width, height: target.height)
        panel.setFrame(newPipFrame, display: true, animate: false)

        if let host = panel.contentView {
            host.frame = NSRect(origin: .zero, size: target)
            metalView?.frame = host.bounds
            overlayView?.frame = host.bounds
            updateHostStyling(host: host, size: target)
        }

        backdropOverlay.updatePiPFrame(newPipFrame, on: targetScreen)
    }
}

/// An NSView that ignores mouse clicks so dragging the window background continues to function.
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// NSPanel subclass so the window can become key for keyboard input but
/// doesn't activate the app — we want the underlying app to keep focus.
private final class WebcamPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Plays a local video file on an infinite loop, extracting BGRA pixel buffers via `AVPlayerItemVideoOutput`
/// and forwarding them directly to `WebcamVideoProcessor`.
private final class WebcamMediaLoopPlayer: NSObject, @unchecked Sendable {
    var onError: (@Sendable (String) -> Void)?

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var outputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private var displayTimer: DispatchSourceTimer?
    private weak var processor: WebcamVideoProcessor?
    private let processingQueue = DispatchQueue(label: "com.macscreenrecord.webcam.videoloop", qos: .userInteractive)
    private var itemObservation: NSKeyValueObservation?
    private var looperObservation: NSKeyValueObservation?

    init(processor: WebcamVideoProcessor) {
        self.processor = processor
        super.init()
    }

    func start(url: URL) {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else {
            onError?("Video clip file not found at \(url.lastPathComponent).")
            return
        }

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue)
        ])
        let templateItem = AVPlayerItem(asset: asset)

        itemObservation = templateItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                let errDesc = item.error?.localizedDescription ?? "Playback error"
                self?.onError?("Couldn't play video clip \(url.lastPathComponent): \(errDesc)")
            }
        }

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)

        looperObservation = looper.observe(\.status, options: [.new]) { [weak self] lpr, _ in
            if lpr.status == .failed {
                let errDesc = lpr.error?.localizedDescription ?? "Loop playback failed"
                self?.onError?("Couldn't loop video clip \(url.lastPathComponent): \(errDesc)")
            }
        }

        var outputsMap: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
        for item in looper.loopingPlayerItems {
            let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
            item.add(out)
            outputsMap[ObjectIdentifier(item)] = out
        }
        self.looper = looper
        self.player = queuePlayer

        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self, weak queuePlayer] in
            guard let self = self, let item = queuePlayer?.currentItem else { return }
            let key = ObjectIdentifier(item)
            let out: AVPlayerItemVideoOutput
            if let existing = self.outputs[key] {
                out = existing
            } else {
                let created = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
                item.add(created)
                self.outputs[key] = created
                return
            }
            let itemTime = out.itemTime(forHostTime: CACurrentMediaTime())
            if out.hasNewPixelBuffer(forItemTime: itemTime),
               let pixelBuffer = out.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                self.processor?.processPixelBuffer(pixelBuffer, from: .videoClip)
            }
        }
        self.displayTimer = timer

        // Serial queue: runs after stop()'s removeAll(), before the first tick.
        processingQueue.async { [weak self] in
            self?.outputs = outputsMap
            timer.resume()
        }
        queuePlayer.play()
    }

    func stop() {
        itemObservation?.invalidate()
        itemObservation = nil
        looperObservation?.invalidate()
        looperObservation = nil
        displayTimer?.cancel()
        displayTimer = nil
        player?.pause()
        player = nil
        looper = nil
        processingQueue.async { [weak self] in
            self?.outputs.removeAll()
        }
    }
}
