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

        guard isEnabled, imageURL != nil else {
            hide()
            return
        }

        if window == nil {
            self.window = makePanel()
        }

        updateFrame()
        reloadImage()

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
            targetRect = NSRect(
                x: currentPiPFrame.minX + relativeRect.origin.x,
                y: currentPiPFrame.minY + relativeRect.origin.y,
                width: max(40, relativeRect.width),
                height: max(40, relativeRect.height)
            )
        } else {
            targetRect = NSRect(
                x: vFrame.minX + freeformNormalizedRect.origin.x * vFrame.width,
                y: vFrame.minY + freeformNormalizedRect.origin.y * vFrame.height,
                width: max(40, freeformNormalizedRect.width * vFrame.width),
                height: max(40, freeformNormalizedRect.height * vFrame.height)
            )
        }

        panel.setFrame(targetRect, display: true, animate: false)
        if let pipWin = pipPanel {
            panel.order(.below, relativeTo: pipWin.windowNumber)
        }
    }

    private func updateVisibility() {
        if isEnabled && imageURL != nil {
            show(targetScreen: currentTargetScreen, pipFrame: currentPiPFrame, relativeTo: pipPanel)
        } else {
            hide()
        }
    }

    private func reloadImage() {
        guard let url = imageURL, let img = NSImage(contentsOf: url) else {
            imageView?.image = nil
            hide()
            return
        }
        imageView?.image = img
        if isEnabled {
            updateVisibility()
        }
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
