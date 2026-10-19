import AppKit
import Foundation
import Combine

/// Convenience snap positions for rapid alignment of the presenter staging area.
public enum PresenterSnapPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case bottomRight = "Bottom-Right"
    case bottomLeft = "Bottom-Left"
    case bottomCenter = "Bottom-Center"
    case topRight = "Top-Right"
    case topLeft = "Top-Left"
    case center = "Center"

    public var id: String { rawValue }

    public var normalizedPoint: CGPoint {
        switch self {
        case .bottomRight: return CGPoint(x: 1.0, y: 0.0)
        case .bottomLeft:  return CGPoint(x: 0.0, y: 0.0)
        case .bottomCenter: return CGPoint(x: 0.5, y: 0.0)
        case .topRight:    return CGPoint(x: 1.0, y: 1.0)
        case .topLeft:     return CGPoint(x: 0.0, y: 1.0)
        case .center:      return CGPoint(x: 0.5, y: 0.5)
        }
    }
}

/// Floating transparent backdrop element placed strictly behind the PiP overlay on screen.
/// Can be grouped (anchored to PiP) or freely placed with independent resizable bounds.
public final class PresenterBackdropOverlay: ObservableObject, @unchecked Sendable {
    @Published public private(set) var cachedImage: NSImage?

    @Published public var isEnabled: Bool = false {
        didSet {
            guard oldValue != isEnabled else { return }
            updateVisibility()
        }
    }

    @Published public var imageURL: URL? = nil {
        didSet {
            guard oldValue != imageURL else { return }
            reloadImage()
        }
    }

    @Published public var isGrouped: Bool = true {
        willSet {
            guard isGrouped != newValue else { return }
            synchronizeGroupingTransition(toGrouped: newValue)
        }
        didSet {
            guard oldValue != isGrouped else { return }
            updateFrame()
        }
    }

    /// Offset and dimensions relative to the PiP window's origin when grouped.
    /// E.g. x: -30, y: -20, width: 260, height: 240
    @Published public var relativeRect: CGRect = CGRect(x: -30, y: -20, width: 260, height: 240) {
        didSet {
            guard oldValue != relativeRect else { return }
            updateFrame()
        }
    }

    /// Normalized position and size on the visible screen when ungrouped (0...1).
    @Published public var freeformNormalizedRect: CGRect = CGRect(x: 0.75, y: 0.05, width: 0.22, height: 0.22) {
        didSet {
            guard oldValue != freeformNormalizedRect else { return }
            updateFrame()
        }
    }

    public var windowID: CGWindowID? {
        guard let w = window else { return nil }
        return CGWindowID(w.windowNumber)
    }

    /// Window level of the backdrop overlay panel.
    public var panelLevel: NSWindow.Level? {
        window?.level
    }

    private var window: PresenterBackdropPanel?
    private var imageView: NSImageView?
    private var currentPiPFrame: NSRect = .zero
    private weak var currentTargetScreen: NSScreen?
    private weak var pipPanel: NSWindow?
    private var isUpdatingFrame: Bool = false
    private var isTrackingBackdropMove: Bool = false
    private var isTransitioningGrouping: Bool = false
    private var moveObserverToken: (any NSObjectProtocol)?

    public init() {}

    deinit {
        if let token = moveObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func show(targetScreen: NSScreen?, pipFrame: NSRect, relativeTo pipWindow: NSWindow?) {
        self.currentTargetScreen = targetScreen
        self.currentPiPFrame = pipFrame
        self.pipPanel = pipWindow

        guard isEnabled, cachedImage != nil else {
            hide()
            return
        }

        if window == nil {
            self.window = makePanel()
        }

        imageView?.image = cachedImage
        updateFrame()

        if let panel = window {
            panel.pipWindow = pipWindow
            if let pipWin = pipWindow, pipWin.isVisible {
                panel.order(.below, relativeTo: pipWin.windowNumber)
            } else {
                panel.orderFront(nil)
            }
        }
    }

    public func hide() {
        window?.orderOut(nil)
    }

    public func updatePiPFrame(_ pipFrame: NSRect, on screen: NSScreen?) {
        self.currentPiPFrame = pipFrame
        if let screen { self.currentTargetScreen = screen }
        guard !isTrackingBackdropMove else { return }
        updateFrame()
    }

    public func updateFrame() {
        guard !isTransitioningGrouping else { return }
        guard let panel = window, isEnabled else { return }
        let screen = currentTargetScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let vFrame = screen.visibleFrame

        let targetRect: NSRect
        if isGrouped {
            targetRect = PresenterBackdropGeometry.groupedScreenRect(
                pipScreenRect: currentPiPFrame,
                relativeRect: relativeRect
            )
        } else {
            targetRect = PresenterBackdropGeometry.freeformScreenRect(
                visibleFrame: vFrame,
                freeformNormalizedRect: freeformNormalizedRect
            )
        }

        isUpdatingFrame = true
        panel.setFrame(targetRect, display: true, animate: false)
        isUpdatingFrame = false

        panel.pipWindow = pipPanel
        if let pipWin = pipPanel, pipWin.isVisible {
            panel.order(.below, relativeTo: pipWin.windowNumber)
        }
    }

    private func synchronizeGroupingTransition(toGrouped: Bool) {
        guard !isTransitioningGrouping else { return }
        isTransitioningGrouping = true
        defer { isTransitioningGrouping = false }

        let screen = currentTargetScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let vFrame = screen.visibleFrame

        guard currentPiPFrame.width > 0 && currentPiPFrame.height > 0 else { return }

        if toGrouped {
            let currentBackdrop = PresenterBackdropGeometry.freeformScreenRect(
                visibleFrame: vFrame,
                freeformNormalizedRect: freeformNormalizedRect
            )
            self.relativeRect = PresenterBackdropGeometry.computeRelativeRect(
                backdropScreenRect: currentBackdrop,
                pipScreenRect: currentPiPFrame
            )
        } else {
            let currentBackdrop = PresenterBackdropGeometry.groupedScreenRect(
                pipScreenRect: currentPiPFrame,
                relativeRect: relativeRect
            )
            self.freeformNormalizedRect = PresenterBackdropGeometry.computeFreeformNormalizedRect(
                backdropScreenRect: currentBackdrop,
                visibleFrame: vFrame
            )
        }
    }

    private func updateVisibility() {
        if isEnabled && cachedImage != nil {
            show(targetScreen: currentTargetScreen, pipFrame: currentPiPFrame, relativeTo: pipPanel)
        } else {
            hide()
        }
    }

    private func reloadImage() {
        guard let url = imageURL, let img = NSImage(contentsOf: url) else {
            cachedImage = nil
            imageView?.image = nil
            updateVisibility()
            return
        }
        cachedImage = img
        imageView?.image = img
        updateVisibility()
    }

    private func makePanel() -> PresenterBackdropPanel {
        let panel = PresenterBackdropPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Strictly place the backdrop one sub-level below .floating so the PiP camera window
        // (at .floating) is guaranteed by the WindowServer compositor to render in front,
        // even if the backdrop window is clicked or receives focus.
        panel.level = NSWindow.Level(NSWindow.Level.floating.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        let imgView = PassthroughImageView(frame: panel.contentView?.bounds ?? .zero)
        imgView.autoresizingMask = [.width, .height]
        imgView.imageScaling = .scaleAxesIndependently
        panel.contentView = imgView
        self.imageView = imgView

        if let oldToken = moveObserverToken {
            NotificationCenter.default.removeObserver(oldToken)
            moveObserverToken = nil
        }

        moveObserverToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let p = self.window, let screen = p.screen else { return }
                guard !self.isUpdatingFrame else { return }
                let frame = p.frame
                let vFrame = screen.visibleFrame
                if self.isGrouped, let pipWin = self.pipPanel {
                    let newPipX = frame.minX - self.relativeRect.origin.x
                    let newPipY = frame.minY - self.relativeRect.origin.y
                    self.isTrackingBackdropMove = true
                    pipWin.setFrameOrigin(NSPoint(x: newPipX, y: newPipY))
                    self.currentPiPFrame = pipWin.frame
                    self.isTrackingBackdropMove = false
                } else if !self.isGrouped {
                    self.currentTargetScreen = screen
                    let normX = (frame.minX - vFrame.minX) / max(1, vFrame.width)
                    let normY = (frame.minY - vFrame.minY) / max(1, vFrame.height)
                    let normW = frame.width / max(1, vFrame.width)
                    let normH = frame.height / max(1, vFrame.height)
                    self.freeformNormalizedRect = CGRect(
                        x: normX,
                        y: normY,
                        width: normW,
                        height: normH
                    )
                }
                if let pipWin = self.pipPanel, pipWin.isVisible {
                    p.order(.below, relativeTo: pipWin.windowNumber)
                }
            }
        }

        return panel
    }
}

private final class PresenterBackdropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    weak var pipWindow: NSWindow?

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            if let pip = pipWindow, pip.isVisible {
                self.order(.below, relativeTo: pip.windowNumber)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let pip = pipWindow, pip.isVisible {
            self.order(.below, relativeTo: pip.windowNumber)
        }
    }
}

private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 8 Resize Handles Definition

public enum PresenterResizeHandle: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight

    public var id: String { rawValue }

    public func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:      return CGPoint(x: rect.minX, y: rect.minY)
        case .topCenter:    return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:     return CGPoint(x: rect.maxX, y: rect.minY)
        case .middleLeft:   return CGPoint(x: rect.minX, y: rect.midY)
        case .middleRight:  return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:   return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomCenter: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight:  return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

public typealias ResizeHandle = PresenterResizeHandle

// MARK: - Clamped Direct Manipulation Geometry

public enum PresenterBackdropGeometry {
    public static let minimumSize: CGFloat = 40.0

    /// Computes the new screen rect resulting from dragging a resize handle.
    /// Anchors the opposing edge(s) and strictly clamps the result within `visibleFrame` and `minSize`.
    public static func computeResizedRect(
        handle: PresenterResizeHandle,
        initialScreenRect: CGRect,
        canvasTranslation: CGSize,
        scale: CGFloat,
        visibleFrame: CGRect,
        minSize: CGFloat = minimumSize
    ) -> CGRect {
        let bounds = visibleFrame.union(initialScreenRect)
        let safeScale = max(0.001, scale)
        let deltaScreenX = canvasTranslation.width / safeScale
        let deltaScreenY = -canvasTranslation.height / safeScale

        let origX = initialScreenRect.origin.x
        let origY = initialScreenRect.origin.y
        let origW = initialScreenRect.width
        let origH = initialScreenRect.height
        let origMaxX = origX + origW
        let origMaxY = origY + origH

        var newX = origX
        var newW = origW
        var newY = origY
        var newH = origH

        // Horizontal dimension & anchoring
        switch handle {
        case .topLeft, .middleLeft, .bottomLeft:
            // Right edge anchored at origMaxX
            let unclampedLeft = origX + deltaScreenX
            let clampedLeft = max(bounds.minX, min(origMaxX - minSize, unclampedLeft))
            newX = clampedLeft
            newW = origMaxX - clampedLeft

        case .topRight, .middleRight, .bottomRight:
            // Left edge anchored at origX
            let unclampedRight = origMaxX + deltaScreenX
            let clampedRight = max(origX + minSize, min(bounds.maxX, unclampedRight))
            newX = origX
            newW = clampedRight - origX

        case .topCenter, .bottomCenter:
            newX = origX
            newW = origW
        }

        // Vertical dimension & anchoring
        switch handle {
        case .topLeft, .topCenter, .topRight:
            // Bottom edge anchored at origY
            let unclampedTop = origMaxY + deltaScreenY
            let clampedTop = max(origY + minSize, min(bounds.maxY, unclampedTop))
            newY = origY
            newH = clampedTop - origY

        case .bottomLeft, .bottomCenter, .bottomRight:
            // Top edge anchored at origMaxY
            let unclampedBottom = origY + deltaScreenY
            let clampedBottom = max(bounds.minY, min(origMaxY - minSize, unclampedBottom))
            newY = clampedBottom
            newH = origMaxY - clampedBottom

        case .middleLeft, .middleRight:
            newY = origY
            newH = origH
        }

        return CGRect(x: newX, y: newY, width: newW, height: newH)
    }

    /// Computes the new screen rect resulting from dragging the backdrop body.
    /// Strictly clamps the entire rect inside `visibleFrame` union `initialScreenRect`.
    public static func computeBodyDragRect(
        initialScreenRect: CGRect,
        canvasTranslation: CGSize,
        scale: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let bounds = visibleFrame.union(initialScreenRect)
        let safeScale = max(0.001, scale)
        let deltaScreenX = canvasTranslation.width / safeScale
        let deltaScreenY = -canvasTranslation.height / safeScale

        let minX = bounds.minX
        let maxX = max(minX, bounds.maxX - initialScreenRect.width)
        let minY = bounds.minY
        let maxY = max(minY, bounds.maxY - initialScreenRect.height)

        let newX = max(minX, min(maxX, initialScreenRect.minX + deltaScreenX))
        let newY = max(minY, min(maxY, initialScreenRect.minY + deltaScreenY))

        return CGRect(x: newX, y: newY, width: initialScreenRect.width, height: initialScreenRect.height)
    }

    /// Computes the absolute screen rect for a grouped backdrop anchored to the PiP camera window.
    public static func groupedScreenRect(
        pipScreenRect: CGRect,
        relativeRect: CGRect,
        minSize: CGFloat = minimumSize
    ) -> CGRect {
        CGRect(
            x: pipScreenRect.minX + relativeRect.origin.x,
            y: pipScreenRect.minY + relativeRect.origin.y,
            width: max(minSize, relativeRect.width),
            height: max(minSize, relativeRect.height)
        )
    }

    /// Computes the absolute screen rect for a freeform backdrop positioned on the visible screen.
    public static func freeformScreenRect(
        visibleFrame: CGRect,
        freeformNormalizedRect: CGRect,
        minSize: CGFloat = minimumSize
    ) -> CGRect {
        CGRect(
            x: visibleFrame.minX + freeformNormalizedRect.origin.x * visibleFrame.width,
            y: visibleFrame.minY + freeformNormalizedRect.origin.y * visibleFrame.height,
            width: max(minSize, freeformNormalizedRect.width * visibleFrame.width),
            height: max(minSize, freeformNormalizedRect.height * visibleFrame.height)
        )
    }

    /// Computes the relative offset and dimensions for grouped mode given absolute backdrop and PiP screen rects.
    public static func computeRelativeRect(
        backdropScreenRect: CGRect,
        pipScreenRect: CGRect,
        minSize: CGFloat = minimumSize
    ) -> CGRect {
        CGRect(
            x: backdropScreenRect.origin.x - pipScreenRect.origin.x,
            y: backdropScreenRect.origin.y - pipScreenRect.origin.y,
            width: max(minSize, backdropScreenRect.width),
            height: max(minSize, backdropScreenRect.height)
        )
    }

    /// Computes the normalized rect (0...1) relative to visibleFrame for freeform mode given an absolute backdrop screen rect.
    public static func computeFreeformNormalizedRect(
        backdropScreenRect: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let safeW = max(1.0, visibleFrame.width)
        let safeH = max(1.0, visibleFrame.height)
        return CGRect(
            x: (backdropScreenRect.origin.x - visibleFrame.minX) / safeW,
            y: (backdropScreenRect.origin.y - visibleFrame.minY) / safeH,
            width: backdropScreenRect.width / safeW,
            height: backdropScreenRect.height / safeH
        )
    }
}

