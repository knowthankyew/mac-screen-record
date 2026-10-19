import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Active background processing mode for the webcam picture-in-picture overlay.
public enum WebcamBackgroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case blur
    case preset
    case customImage
    case cutout

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none:        return "Normal"
        case .blur:        return "Blur"
        case .preset:      return "Virtual Backdrop"
        case .customImage: return "Custom Image"
        case .cutout:      return "Cutout (Silhouette)"
        }
    }
}

/// Active visual source for the presenter picture-in-picture overlay.
public enum WebcamSourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case camera
    case staticImage
    case videoClip

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .camera:      return "Camera"
        case .staticImage: return "Static Image"
        case .videoClip:   return "Video Loop"
        }
    }
    public var systemImage: String {
        switch self {
        case .camera:      return "camera"
        case .staticImage: return "photo"
        case .videoClip:   return "play.rectangle"
        }
    }
}

/// Framing shape for the webcam overlay window.
public enum WebcamShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle
    case roundedRect
    case oval
    case hexagon
    case diamond
    case heart
    case star

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .circle:      return "Circle"
        case .roundedRect: return "Rounded Rectangle"
        case .oval:        return "Oval"
        case .hexagon:     return "Hexagon"
        case .diamond:     return "Diamond"
        case .heart:       return "Heart"
        case .star:        return "Star"
        }
    }

    public var systemImage: String {
        switch self {
        case .circle:      return "circle"
        case .roundedRect: return "rectangle.roundedtop"
        case .oval:        return "oval"
        case .hexagon:     return "hexagon"
        case .diamond:     return "diamond"
        case .heart:       return "heart"
        case .star:        return "star"
        }
    }

    /// Whether this shape supports non-square aspect ratios (16:9 widescreen and 4:3 classic).
    public var supportsAspectRatio: Bool {
        self == .roundedRect || self == .oval
    }

    /// Generates the vector outline path for this shape fitting within the specified bounds.
    /// - Parameters:
    ///   - bounds: The bounding rectangle to fit the shape within.
    ///   - flipped: When `true`, inverts the vertical axis so that shapes drawn in SwiftUI
    ///              (where Y increases downward) match AppKit window coordinates (where Y increases upward).
    public func path(in bounds: CGRect, flipped: Bool = false) -> CGPath {
        guard bounds.width > 0 && bounds.height > 0 else {
            return CGPath(rect: bounds, transform: nil)
        }
        let basePath: CGPath
        switch self {
        case .circle:
            let d = min(bounds.width, bounds.height)
            let circleRect = CGRect(
                x: bounds.midX - d / 2.0,
                y: bounds.midY - d / 2.0,
                width: d,
                height: d
            )
            basePath = CGPath(ellipseIn: circleRect, transform: nil)

        case .oval:
            basePath = CGPath(ellipseIn: bounds, transform: nil)

        case .roundedRect:
            let cornerRadius = min(bounds.width, bounds.height) * 0.16
            basePath = CGPath(
                roundedRect: bounds,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )

        case .hexagon:
            let path = CGMutablePath()
            let cx = bounds.midX
            let cy = bounds.midY
            let rx = bounds.width / 2.0
            let ry = bounds.height / 2.0
            for i in 0..<6 {
                let angle = -Double.pi / 2.0 + Double(i) * (Double.pi / 3.0)
                let pt = CGPoint(
                    x: cx + rx * CGFloat(cos(angle)),
                    y: cy + ry * CGFloat(sin(angle))
                )
                if i == 0 {
                    path.move(to: pt)
                } else {
                    path.addLine(to: pt)
                }
            }
            path.closeSubpath()
            basePath = path

        case .diamond:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
            path.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY))
            path.addLine(to: CGPoint(x: bounds.minX, y: bounds.midY))
            path.closeSubpath()
            basePath = path

        case .heart:
            let path = CGMutablePath()
            let w = bounds.width
            let h = bounds.height
            let ox = bounds.minX
            let oy = bounds.minY
            let tip = CGPoint(x: ox + w * 0.5, y: oy + h * 0.05)
            let notch = CGPoint(x: ox + w * 0.5, y: oy + h * 0.72)
            path.move(to: tip)
            // Left lobe
            path.addCurve(
                to: CGPoint(x: ox + w * 0.05, y: oy + h * 0.55),
                control1: CGPoint(x: ox + w * 0.25, y: oy + h * 0.15),
                control2: CGPoint(x: ox + w * 0.05, y: oy + h * 0.35)
            )
            path.addCurve(
                to: notch,
                control1: CGPoint(x: ox + w * 0.05, y: oy + h * 0.95),
                control2: CGPoint(x: ox + w * 0.45, y: oy + h * 0.95)
            )
            // Right lobe
            path.addCurve(
                to: CGPoint(x: ox + w * 0.95, y: oy + h * 0.55),
                control1: CGPoint(x: ox + w * 0.55, y: oy + h * 0.95),
                control2: CGPoint(x: ox + w * 0.95, y: oy + h * 0.95)
            )
            path.addCurve(
                to: tip,
                control1: CGPoint(x: ox + w * 0.95, y: oy + h * 0.35),
                control2: CGPoint(x: ox + w * 0.75, y: oy + h * 0.15)
            )
            path.closeSubpath()
            basePath = path

        case .star:
            let path = CGMutablePath()
            let cx = bounds.midX
            let cy = bounds.midY
            let R = min(bounds.width, bounds.height) / 2.0
            let r = R * 0.382
            for i in 0..<10 {
                let angle = Double.pi / 2.0 + Double(i) * (Double.pi / 5.0)
                let radius = (i % 2 == 0) ? R : r
                let pt = CGPoint(
                    x: cx + CGFloat(radius * cos(angle)),
                    y: cy + CGFloat(radius * sin(angle))
                )
                if i == 0 {
                    path.move(to: pt)
                } else {
                    path.addLine(to: pt)
                }
            }
            path.closeSubpath()
            basePath = path
        }

        guard flipped else { return basePath }
        var transform = CGAffineTransform(translationX: bounds.minX, y: bounds.maxY)
            .scaledBy(x: 1, y: -1)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
        return basePath.copy(using: &transform) ?? basePath
    }
}

/// Aspect ratio for rounded rectangle webcam overlay framing.
public enum WebcamAspectRatio: String, Codable, CaseIterable, Identifiable, Sendable {
    case square
    case widescreen
    case classic

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .square:     return "1:1 Square"
        case .widescreen: return "16:9 Widescreen"
        case .classic:    return "4:3 Classic"
        }
    }

    /// Aspect ratio expressed as width / height
    public var ratio: CGFloat {
        switch self {
        case .square:     return 1.0
        case .widescreen: return 16.0 / 9.0
        case .classic:    return 4.0 / 3.0
        }
    }
}

/// Blur strength options for background blurring.
public enum WebcamBlurStrength: String, Codable, CaseIterable, Identifiable, Sendable {
    case subtle
    case balanced
    case strong

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .subtle:   return "Subtle (\(Int(sigma))px)"
        case .balanced: return "Balanced (\(Int(sigma))px)"
        case .strong:   return "Strong (\(Int(sigma))px)"
        }
    }
    public var sigma: Double {
        switch self {
        case .subtle:   return 10.0
        case .balanced: return 20.0
        case .strong:   return 35.0
        }
    }
}

/// Built-in virtual background presets generated on-device with zero assets or network egress.
public enum WebcamBackgroundPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case warmStudio
    case coolSlate
    case modernMinimal
    case sunset
    case chromaGreen

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .warmStudio:    return "Warm Studio"
        case .coolSlate:     return "Cool Slate"
        case .modernMinimal: return "Modern Minimal"
        case .sunset:        return "Sunset"
        case .chromaGreen:   return "Green Screen"
        }
    }

    /// Renders a crisp background `CIImage` sized to the target dimensions.
    public func makeImage(size: CGSize) -> CIImage {
        // Defensive lower bound: Prevents near-zero dimension crashes and degenerate
        // matrix inversions in Core Image procedural gradient filters.
        let width = max(size.width, 100)
        let height = max(size.height, 100)
        let rect = CGRect(origin: .zero, size: CGSize(width: width, height: height))

        switch self {
        case .warmStudio:
            let filter = CIFilter.radialGradient()
            filter.center = CGPoint(x: width * 0.5, y: height * 0.6)
            filter.radius0 = Float(min(width, height) * 0.1)
            filter.radius1 = Float(max(width, height) * 0.9)
            filter.color0 = CIColor(red: 0.34, green: 0.26, blue: 0.28)
            filter.color1 = CIColor(red: 0.12, green: 0.10, blue: 0.13)
            return filter.outputImage?.cropped(to: rect) ?? CIImage(color: filter.color1).cropped(to: rect)

        case .coolSlate:
            let filter = CIFilter.linearGradient()
            filter.point0 = CGPoint(x: 0, y: height)
            filter.point1 = CGPoint(x: width, y: 0)
            filter.color0 = CIColor(red: 0.14, green: 0.20, blue: 0.28)
            filter.color1 = CIColor(red: 0.06, green: 0.08, blue: 0.14)
            return filter.outputImage?.cropped(to: rect) ?? CIImage(color: filter.color1).cropped(to: rect)

        case .modernMinimal:
            let filter = CIFilter.radialGradient()
            filter.center = CGPoint(x: width * 0.5, y: height * 0.5)
            filter.radius0 = Float(min(width, height) * 0.15)
            filter.radius1 = Float(max(width, height) * 0.85)
            filter.color0 = CIColor(red: 0.28, green: 0.28, blue: 0.31)
            filter.color1 = CIColor(red: 0.14, green: 0.14, blue: 0.16)
            return filter.outputImage?.cropped(to: rect) ?? CIImage(color: filter.color1).cropped(to: rect)

        case .sunset:
            let filter = CIFilter.linearGradient()
            filter.point0 = CGPoint(x: 0, y: 0)
            filter.point1 = CGPoint(x: width, y: height)
            filter.color0 = CIColor(red: 0.44, green: 0.18, blue: 0.28)
            filter.color1 = CIColor(red: 0.16, green: 0.12, blue: 0.30)
            return filter.outputImage?.cropped(to: rect) ?? CIImage(color: filter.color1).cropped(to: rect)

        case .chromaGreen:
            return CIImage(color: CIColor(red: 0.0, green: 1.0, blue: 0.0)).cropped(to: rect)
        }
    }
}

// MARK: - Hex Color Conversions

extension CGColor {
    /// Creates a device-independent sRGB CGColor from a hex string (e.g. "#FFFFFF", "34C759", or 8-char "#RRGGBBAA").
    public static func fromHex(_ hex: String) -> CGColor? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") {
            hexSanitized.removeFirst()
        }
        guard hexSanitized.count == 6 || hexSanitized.count == 8 else { return nil }
        guard hexSanitized.allSatisfy(\.isHexDigit) else { return nil }
        guard let rgbValue = UInt64(hexSanitized, radix: 16) else { return nil }
        if hexSanitized.count == 6 {
            let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgbValue & 0x0000FF) / 255.0
            return CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        } else {
            let r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            let g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            let b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            let a = CGFloat(rgbValue & 0x000000FF) / 255.0
            return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
    }

    /// Canonical sRGB hexadecimal representation (`#RRGGBB` or `#RRGGBBAA` if alpha < 1.0).
    public var hexString: String {
        guard let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let srgb = converted(to: srgbSpace, intent: .defaultIntent, options: nil),
              let components = srgb.components, components.count >= 3 else {
            return "#FFFFFF"
        }
        let r = Int(round(components[0] * 255))
        let g = Int(round(components[1] * 255))
        let b = Int(round(components[2] * 255))
        let a = components.count >= 4 ? Int(round(components[3] * 255)) : 255
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        } else {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
    }
}

extension NSColor {
    public convenience init?(hex: String) {
        guard let cg = CGColor.fromHex(hex) else { return nil }
        self.init(cgColor: cg)
    }

    public var hexString: String {
        cgColor.hexString
    }
}

