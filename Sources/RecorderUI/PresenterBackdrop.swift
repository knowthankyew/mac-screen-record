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

    private var window: PresenterBackdropPanel?
    private var imageView: NSImageView?
    private var currentPiPFrame: NSRect = .zero
    private weak var currentTargetScreen: NSScreen?
    private weak var pipPanel: NSWindow?

    public init() {}

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
            if let pipWin = pipWindow {
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
        updateFrame()
    }

    public func updateFrame() {
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

        panel.setFrame(targetRect, display: true, animate: false)
        if let pipWin = pipPanel {
            panel.order(.below, relativeTo: pipWin.windowNumber)
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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let imgView = NSImageView(frame: panel.contentView?.bounds ?? .zero)
        imgView.autoresizingMask = [.width, .height]
        imgView.imageScaling = .scaleAxesIndependently
        panel.contentView = imgView
        self.imageView = imgView

        return panel
    }
}

private final class PresenterBackdropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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
}

