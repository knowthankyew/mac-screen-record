import Combine
import EncoderKit
import Foundation

public struct Preset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String

    public var sourceKindRaw: String           // RecordingViewModel.SourceKind.rawValue
    public var codec: OutputCodec
    public var fps: Int
    public var showsCursor: Bool
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool
    public var customWidth: Int?
    public var customHeight: Int?

    // Overlay settings
    public var webcamEnabled: Bool
    public var useForFacecam: Bool
    public var clickHighlightsEnabled: Bool
    public var keystrokesEnabled: Bool
    public var webcamCorner: WebcamCorner?
    public var webcamSize: WebcamSize?
    public var webcamBackgroundMode: WebcamBackgroundMode?
    public var webcamBlurStrength: WebcamBlurStrength?
    public var webcamShape: WebcamShape?
    public var webcamAspectRatio: WebcamAspectRatio?
    public var webcamBlurCustomImage: Bool?
    public var webcamShowBorder: Bool?
    public var webcamBorderColorHex: String?
    public var webcamBorderWidth: Double?
    public var webcamSourceType: WebcamSourceType?
    public var webcamStaticImageURL: String?
    public var webcamVideoClipURL: String?
    public var webcamBrandingOverlayURL: String?
    public var pipNormalizedX: Double?
    public var pipNormalizedY: Double?
    public var backdropEnabled: Bool?
    public var backdropImageURL: String?
    public var backdropIsGrouped: Bool?
    public var backdropRelativeX: Double?
    public var backdropRelativeY: Double?
    public var backdropRelativeWidth: Double?
    public var backdropRelativeHeight: Double?
    public var backdropFreeformNormalizedX: Double?
    public var backdropFreeformNormalizedY: Double?
    public var backdropFreeformNormalizedWidth: Double?
    public var backdropFreeformNormalizedHeight: Double?

    public init(
        id: UUID = UUID(),
        name: String,
        sourceKindRaw: String,
        codec: OutputCodec,
        fps: Int,
        showsCursor: Bool,
        captureSystemAudio: Bool,
        captureMicrophone: Bool,
        customWidth: Int?,
        customHeight: Int?,
        webcamEnabled: Bool = false,
        useForFacecam: Bool = false,
        clickHighlightsEnabled: Bool = false,
        keystrokesEnabled: Bool = false,
        webcamCorner: WebcamCorner? = nil,
        webcamSize: WebcamSize? = nil,
        webcamBackgroundMode: WebcamBackgroundMode? = nil,
        webcamBlurStrength: WebcamBlurStrength? = nil,
        webcamShape: WebcamShape? = nil,
        webcamAspectRatio: WebcamAspectRatio? = nil,
        webcamBlurCustomImage: Bool? = nil,
        webcamShowBorder: Bool? = nil,
        webcamBorderColorHex: String? = nil,
        webcamBorderWidth: Double? = nil,
        webcamSourceType: WebcamSourceType? = nil,
        webcamStaticImageURL: String? = nil,
        webcamVideoClipURL: String? = nil,
        webcamBrandingOverlayURL: String? = nil,
        pipNormalizedX: Double? = nil,
        pipNormalizedY: Double? = nil,
        backdropEnabled: Bool? = nil,
        backdropImageURL: String? = nil,
        backdropIsGrouped: Bool? = nil,
        backdropRelativeX: Double? = nil,
        backdropRelativeY: Double? = nil,
        backdropRelativeWidth: Double? = nil,
        backdropRelativeHeight: Double? = nil,
        backdropFreeformNormalizedX: Double? = nil,
        backdropFreeformNormalizedY: Double? = nil,
        backdropFreeformNormalizedWidth: Double? = nil,
        backdropFreeformNormalizedHeight: Double? = nil
    ) {
        self.id = id; self.name = name
        self.sourceKindRaw = sourceKindRaw
        self.codec = codec; self.fps = fps
        self.showsCursor = showsCursor
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.customWidth = customWidth; self.customHeight = customHeight
        self.webcamEnabled = webcamEnabled
        self.useForFacecam = useForFacecam
        self.clickHighlightsEnabled = clickHighlightsEnabled
        self.keystrokesEnabled = keystrokesEnabled
        self.webcamCorner = webcamCorner
        self.webcamSize = webcamSize
        self.webcamBackgroundMode = webcamBackgroundMode
        self.webcamBlurStrength = webcamBlurStrength
        self.webcamShape = webcamShape
        self.webcamAspectRatio = webcamAspectRatio
        self.webcamBlurCustomImage = webcamBlurCustomImage
        self.webcamShowBorder = webcamShowBorder
        self.webcamBorderColorHex = webcamBorderColorHex
        self.webcamBorderWidth = webcamBorderWidth
        self.webcamSourceType = webcamSourceType
        self.webcamStaticImageURL = webcamStaticImageURL
        self.webcamVideoClipURL = webcamVideoClipURL
        self.webcamBrandingOverlayURL = webcamBrandingOverlayURL
        self.pipNormalizedX = pipNormalizedX
        self.pipNormalizedY = pipNormalizedY
        self.backdropEnabled = backdropEnabled
        self.backdropImageURL = backdropImageURL
        self.backdropIsGrouped = backdropIsGrouped
        self.backdropRelativeX = backdropRelativeX
        self.backdropRelativeY = backdropRelativeY
        self.backdropRelativeWidth = backdropRelativeWidth
        self.backdropRelativeHeight = backdropRelativeHeight
        self.backdropFreeformNormalizedX = backdropFreeformNormalizedX
        self.backdropFreeformNormalizedY = backdropFreeformNormalizedY
        self.backdropFreeformNormalizedWidth = backdropFreeformNormalizedWidth
        self.backdropFreeformNormalizedHeight = backdropFreeformNormalizedHeight
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sourceKindRaw, codec, fps, showsCursor
        case captureSystemAudio, captureMicrophone, customWidth, customHeight
        case webcamEnabled, useForFacecam, clickHighlightsEnabled, keystrokesEnabled
        case webcamCorner, webcamSize, webcamBackgroundMode
        case webcamCornerRaw, webcamSizeRaw, webcamBackgroundModeRaw
        case webcamBlurStrength, webcamBlurStrengthRaw
        case webcamShape, webcamAspectRatio, webcamBlurCustomImage
        case webcamShowBorder, webcamBorderColorHex, webcamBorderWidth
        case webcamShapeRaw, webcamAspectRatioRaw
        case webcamSourceType, webcamSourceTypeRaw
        case webcamStaticImageURL, webcamVideoClipURL, webcamBrandingOverlayURL
        case pipNormalizedX, pipNormalizedY
        case backdropEnabled, backdropImageURL, backdropIsGrouped
        case backdropRelativeX, backdropRelativeY, backdropRelativeWidth, backdropRelativeHeight
        case backdropFreeformNormalizedX, backdropFreeformNormalizedY, backdropFreeformNormalizedWidth, backdropFreeformNormalizedHeight
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourceKindRaw, forKey: .sourceKindRaw)
        try container.encode(codec, forKey: .codec)
        try container.encode(fps, forKey: .fps)
        try container.encode(showsCursor, forKey: .showsCursor)
        try container.encode(captureSystemAudio, forKey: .captureSystemAudio)
        try container.encode(captureMicrophone, forKey: .captureMicrophone)
        try container.encodeIfPresent(customWidth, forKey: .customWidth)
        try container.encodeIfPresent(customHeight, forKey: .customHeight)

        try container.encode(webcamEnabled, forKey: .webcamEnabled)
        try container.encode(useForFacecam, forKey: .useForFacecam)
        try container.encode(clickHighlightsEnabled, forKey: .clickHighlightsEnabled)
        try container.encode(keystrokesEnabled, forKey: .keystrokesEnabled)

        // Store typed enums directly, plus legacy raw string keys for backward compatibility
        try container.encodeIfPresent(webcamCorner, forKey: .webcamCorner)
        try container.encodeIfPresent(webcamCorner?.rawValue, forKey: .webcamCornerRaw)
        try container.encodeIfPresent(webcamSize, forKey: .webcamSize)
        try container.encodeIfPresent(webcamSize?.rawValue, forKey: .webcamSizeRaw)
        try container.encodeIfPresent(webcamBackgroundMode, forKey: .webcamBackgroundMode)
        try container.encodeIfPresent(webcamBackgroundMode?.rawValue, forKey: .webcamBackgroundModeRaw)
        try container.encodeIfPresent(webcamBlurStrength, forKey: .webcamBlurStrength)
        try container.encodeIfPresent(webcamBlurStrength?.rawValue, forKey: .webcamBlurStrengthRaw)
        try container.encodeIfPresent(webcamShape, forKey: .webcamShape)
        try container.encodeIfPresent(webcamShape?.rawValue, forKey: .webcamShapeRaw)
        try container.encodeIfPresent(webcamAspectRatio, forKey: .webcamAspectRatio)
        try container.encodeIfPresent(webcamAspectRatio?.rawValue, forKey: .webcamAspectRatioRaw)
        try container.encodeIfPresent(webcamBlurCustomImage, forKey: .webcamBlurCustomImage)
        try container.encodeIfPresent(webcamShowBorder, forKey: .webcamShowBorder)
        try container.encodeIfPresent(webcamBorderColorHex, forKey: .webcamBorderColorHex)
        try container.encodeIfPresent(webcamBorderWidth, forKey: .webcamBorderWidth)
        try container.encodeIfPresent(webcamSourceType, forKey: .webcamSourceType)
        try container.encodeIfPresent(webcamSourceType?.rawValue, forKey: .webcamSourceTypeRaw)
        try container.encodeIfPresent(webcamStaticImageURL, forKey: .webcamStaticImageURL)
        try container.encodeIfPresent(webcamVideoClipURL, forKey: .webcamVideoClipURL)
        try container.encodeIfPresent(webcamBrandingOverlayURL, forKey: .webcamBrandingOverlayURL)
        try container.encodeIfPresent(pipNormalizedX, forKey: .pipNormalizedX)
        try container.encodeIfPresent(pipNormalizedY, forKey: .pipNormalizedY)
        try container.encodeIfPresent(backdropEnabled, forKey: .backdropEnabled)
        try container.encodeIfPresent(backdropImageURL, forKey: .backdropImageURL)
        try container.encodeIfPresent(backdropIsGrouped, forKey: .backdropIsGrouped)
        try container.encodeIfPresent(backdropRelativeX, forKey: .backdropRelativeX)
        try container.encodeIfPresent(backdropRelativeY, forKey: .backdropRelativeY)
        try container.encodeIfPresent(backdropRelativeWidth, forKey: .backdropRelativeWidth)
        try container.encodeIfPresent(backdropRelativeHeight, forKey: .backdropRelativeHeight)
        try container.encodeIfPresent(backdropFreeformNormalizedX, forKey: .backdropFreeformNormalizedX)
        try container.encodeIfPresent(backdropFreeformNormalizedY, forKey: .backdropFreeformNormalizedY)
        try container.encodeIfPresent(backdropFreeformNormalizedWidth, forKey: .backdropFreeformNormalizedWidth)
        try container.encodeIfPresent(backdropFreeformNormalizedHeight, forKey: .backdropFreeformNormalizedHeight)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.sourceKindRaw = try container.decode(String.self, forKey: .sourceKindRaw)
        self.codec = try container.decode(OutputCodec.self, forKey: .codec)
        self.fps = try container.decode(Int.self, forKey: .fps)
        self.showsCursor = try container.decode(Bool.self, forKey: .showsCursor)
        self.captureSystemAudio = try container.decode(Bool.self, forKey: .captureSystemAudio)
        self.captureMicrophone = try container.decode(Bool.self, forKey: .captureMicrophone)
        self.customWidth = try container.decodeIfPresent(Int.self, forKey: .customWidth)
        self.customHeight = try container.decodeIfPresent(Int.self, forKey: .customHeight)

        self.webcamEnabled = try container.decodeIfPresent(Bool.self, forKey: .webcamEnabled) ?? false
        self.useForFacecam = try container.decodeIfPresent(Bool.self, forKey: .useForFacecam) ?? false
        self.clickHighlightsEnabled = try container.decodeIfPresent(Bool.self, forKey: .clickHighlightsEnabled) ?? false
        self.keystrokesEnabled = try container.decodeIfPresent(Bool.self, forKey: .keystrokesEnabled) ?? false

        // Typed enums with fallback to legacy raw strings
        if let corner = try? container.decodeIfPresent(WebcamCorner.self, forKey: .webcamCorner) {
            self.webcamCorner = corner
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .webcamCornerRaw), let corner = WebcamCorner(rawValue: raw) {
            self.webcamCorner = corner
        } else {
            self.webcamCorner = nil
        }

        if let size = try? container.decodeIfPresent(WebcamSize.self, forKey: .webcamSize) {
            self.webcamSize = size
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .webcamSizeRaw), let size = WebcamSize(rawValue: raw) {
            self.webcamSize = size
        } else {
            self.webcamSize = nil
        }

        if let mode = try? container.decodeIfPresent(WebcamBackgroundMode.self, forKey: .webcamBackgroundMode) {
            self.webcamBackgroundMode = mode
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .webcamBackgroundModeRaw), let mode = WebcamBackgroundMode(rawValue: raw) {
            self.webcamBackgroundMode = mode
        } else {
            self.webcamBackgroundMode = nil
        }

        if let strength = try? container.decodeIfPresent(WebcamBlurStrength.self, forKey: .webcamBlurStrength) {
            self.webcamBlurStrength = strength
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .webcamBlurStrengthRaw), let strength = WebcamBlurStrength(rawValue: raw) {
            self.webcamBlurStrength = strength
        } else {
            self.webcamBlurStrength = nil
        }

        if let shape = try? container.decodeIfPresent(WebcamShape.self, forKey: .webcamShape) {
            self.webcamShape = shape
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .webcamShapeRaw), let shape = WebcamShape(rawValue: raw) {
            self.webcamShape = shape
        } else {
            self.webcamShape = nil
        }

        if let ratio = try? container.decodeIfPresent(WebcamAspectRatio.self, forKey: .webcamAspectRatio) {
            self.webcamAspectRatio = ratio
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .webcamAspectRatioRaw), let ratio = WebcamAspectRatio(rawValue: raw) {
            self.webcamAspectRatio = ratio
        } else {
            self.webcamAspectRatio = nil
        }

        self.webcamBlurCustomImage = try? container.decodeIfPresent(Bool.self, forKey: .webcamBlurCustomImage)
        self.webcamShowBorder = try? container.decodeIfPresent(Bool.self, forKey: .webcamShowBorder)
        self.webcamBorderColorHex = try? container.decodeIfPresent(String.self, forKey: .webcamBorderColorHex)
        self.webcamBorderWidth = try? container.decodeIfPresent(Double.self, forKey: .webcamBorderWidth)

        if let st = try? container.decodeIfPresent(WebcamSourceType.self, forKey: .webcamSourceType) {
            self.webcamSourceType = st
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .webcamSourceTypeRaw), let st = WebcamSourceType(rawValue: raw) {
            self.webcamSourceType = st
        } else {
            self.webcamSourceType = nil
        }

        self.webcamStaticImageURL = try? container.decodeIfPresent(String.self, forKey: .webcamStaticImageURL)
        self.webcamVideoClipURL = try? container.decodeIfPresent(String.self, forKey: .webcamVideoClipURL)
        self.webcamBrandingOverlayURL = try? container.decodeIfPresent(String.self, forKey: .webcamBrandingOverlayURL)

        self.pipNormalizedX = try? container.decodeIfPresent(Double.self, forKey: .pipNormalizedX)
        self.pipNormalizedY = try? container.decodeIfPresent(Double.self, forKey: .pipNormalizedY)

        self.backdropEnabled = try? container.decodeIfPresent(Bool.self, forKey: .backdropEnabled)
        self.backdropImageURL = try? container.decodeIfPresent(String.self, forKey: .backdropImageURL)
        self.backdropIsGrouped = try? container.decodeIfPresent(Bool.self, forKey: .backdropIsGrouped)
        self.backdropRelativeX = try? container.decodeIfPresent(Double.self, forKey: .backdropRelativeX)
        self.backdropRelativeY = try? container.decodeIfPresent(Double.self, forKey: .backdropRelativeY)
        self.backdropRelativeWidth = try? container.decodeIfPresent(Double.self, forKey: .backdropRelativeWidth)
        self.backdropRelativeHeight = try? container.decodeIfPresent(Double.self, forKey: .backdropRelativeHeight)
        self.backdropFreeformNormalizedX = try? container.decodeIfPresent(Double.self, forKey: .backdropFreeformNormalizedX)
        self.backdropFreeformNormalizedY = try? container.decodeIfPresent(Double.self, forKey: .backdropFreeformNormalizedY)
        self.backdropFreeformNormalizedWidth = try? container.decodeIfPresent(Double.self, forKey: .backdropFreeformNormalizedWidth)
        self.backdropFreeformNormalizedHeight = try? container.decodeIfPresent(Double.self, forKey: .backdropFreeformNormalizedHeight)
    }

    public var effectivePipNormalizedPosition: CGPoint {
        if let x = pipNormalizedX, let y = pipNormalizedY {
            return CGPoint(x: x, y: y)
        } else if let corner = webcamCorner {
            return corner.normalizedPoint
        } else {
            return CGPoint(x: 1.0, y: 0.0)
        }
    }
}

@MainActor
public final class PresetsStore: ObservableObject {
    @Published public private(set) var presets: [Preset] = []
    @Published public private(set) var defaultPresetID: UUID?

    private let defaults: UserDefaults
    private let key = "MacScreenRecord.presets.v1"
    private let legacyKey = "FreeMacScreenRecorder.presets.v1"
    private let defaultKey = "MacScreenRecord.defaultPresetID.v1"
    private let legacyDefaultKey = "FreeMacScreenRecorder.defaultPresetID.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public var defaultPreset: Preset? {
        guard let id = defaultPresetID else { return nil }
        return presets.first(where: { $0.id == id })
    }

    public var facecamPreset: Preset? {
        presets.first(where: { $0.useForFacecam && $0.webcamEnabled })
    }

    public var presetsWithPIP: [Preset] {
        presets.filter { $0.webcamEnabled }
    }

    public func load() {
        var loadedPresets: [Preset]?
        var loadedFromLegacy = false

        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            loadedPresets = decoded
        } else if let legacyData = defaults.data(forKey: legacyKey),
                  let decoded = try? JSONDecoder().decode([Preset].self, from: legacyData) {
            loadedPresets = decoded
            loadedFromLegacy = true
        }

        guard let loaded = loadedPresets else { return }
        presets = loaded

        let hadLegacyDefault = defaults.object(forKey: legacyDefaultKey) != nil
        let rawDefaultStr = defaults.string(forKey: defaultKey) ?? defaults.string(forKey: legacyDefaultKey)
        if let str = rawDefaultStr, let uid = UUID(uuidString: str), presets.contains(where: { $0.id == uid }) {
            defaultPresetID = uid
        } else {
            defaultPresetID = nil
        }
        normalizeFacecamProfiles()

        if loadedFromLegacy {
            persist()
            defaults.removeObject(forKey: legacyKey)
        }
        if loadedFromLegacy || hadLegacyDefault {
            if let defaultPresetID {
                defaults.set(defaultPresetID.uuidString, forKey: defaultKey)
            } else {
                defaults.removeObject(forKey: defaultKey)
            }
            defaults.removeObject(forKey: legacyDefaultKey)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: key)
        }
    }

    public func setDefault(id: UUID?) {
        defaultPresetID = id
        if let id {
            defaults.set(id.uuidString, forKey: defaultKey)
        } else {
            defaults.removeObject(forKey: defaultKey)
        }
        defaults.removeObject(forKey: legacyDefaultKey)
    }

    /// Normalizes facecam profile designation.
    ///
    /// Invariant: If exactly 1 profile with PIP exists in the store and none is designated as `useForFacecam`,
    /// it is automatically designated for Facecam. This enforces the user requirement:
    /// "if a PIP profile exists and there is only one... check a new toggle for 'use for facecam'".
    ///
    /// Note on deletion: If deleting a profile leaves exactly 1 remaining PIP profile that had not been
    /// marked, it will be automatically promoted to the Facecam profile.
    public func normalizeFacecamProfiles() {
        var changed = false
        for i in presets.indices where !presets[i].webcamEnabled && presets[i].useForFacecam {
            presets[i].useForFacecam = false
            changed = true
        }
        let pipPresets = presetsWithPIP
        if pipPresets.count == 1 {
            let singlePIPId = pipPresets[0].id
            for i in presets.indices {
                if presets[i].id == singlePIPId && !presets[i].useForFacecam {
                    presets[i].useForFacecam = true
                    changed = true
                }
            }
        } else if pipPresets.filter(\.useForFacecam).count > 1 {
            var seenFirst = false
            for i in presets.indices where presets[i].webcamEnabled && presets[i].useForFacecam {
                if seenFirst {
                    presets[i].useForFacecam = false
                    changed = true
                } else {
                    seenFirst = true
                }
            }
        }
        if changed { persist() }
    }

    public func setAsFacecam(id: UUID) {
        for i in presets.indices {
            presets[i].useForFacecam = (presets[i].id == id)
        }
        persist()
    }

    public func add(_ preset: Preset) {
        var newPreset = preset
        let pipPresets = presetsWithPIP
        if newPreset.webcamEnabled {
            // First profile with PIP auto-checks useForFacecam
            if pipPresets.isEmpty {
                newPreset.useForFacecam = true
            } else if newPreset.useForFacecam {
                // If explicitly set, clear prior facecam designations
                for i in presets.indices {
                    presets[i].useForFacecam = false
                }
            }
        }
        presets.append(newPreset)
        normalizeFacecamProfiles()
        persist()
    }

    public func update(_ preset: Preset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            var updated = preset
            if !updated.webcamEnabled {
                updated.useForFacecam = false
            }
            presets[i] = updated
            if updated.webcamEnabled && updated.useForFacecam {
                for j in presets.indices where j != i {
                    presets[j].useForFacecam = false
                }
            }
            normalizeFacecamProfiles()
            persist()
        }
    }

    /// Deletes a preset by ID.
    /// If the deleted profile was the startup default, the default is cleared.
    /// If deleting leaves exactly 1 PIP preset remaining, `normalizeFacecamProfiles()`
    /// auto-designates it as the Facecam profile.
    public func delete(id: UUID) {
        if defaultPresetID == id {
            setDefault(id: nil)
        }
        presets.removeAll { $0.id == id }
        normalizeFacecamProfiles()
        persist()
    }
}
