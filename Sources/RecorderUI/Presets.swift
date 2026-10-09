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
        webcamBackgroundMode: WebcamBackgroundMode? = nil
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
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sourceKindRaw, codec, fps, showsCursor
        case captureSystemAudio, captureMicrophone, customWidth, customHeight
        case webcamEnabled, useForFacecam, clickHighlightsEnabled, keystrokesEnabled
        case webcamCorner, webcamSize, webcamBackgroundMode
        case webcamCornerRaw, webcamSizeRaw, webcamBackgroundModeRaw
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
    }
}

@MainActor
public final class PresetsStore: ObservableObject {
    @Published public private(set) var presets: [Preset] = []
    @Published public private(set) var defaultPresetID: UUID?

    private let defaults = UserDefaults.standard
    private let key = "MacScreenRecord.presets.v1"
    private let legacyKey = "FreeMacScreenRecorder.presets.v1"
    private let defaultKey = "MacScreenRecord.defaultPresetID.v1"
    private let legacyDefaultKey = "FreeMacScreenRecorder.defaultPresetID.v1"

    public init() { load() }

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

        let rawDefaultStr = defaults.string(forKey: defaultKey) ?? defaults.string(forKey: legacyDefaultKey)
        if let str = rawDefaultStr, let uid = UUID(uuidString: str), presets.contains(where: { $0.id == uid }) {
            defaultPresetID = uid
        } else {
            defaultPresetID = nil
        }
        normalizeFacecamProfiles()

        if loadedFromLegacy {
            persist()
            if let defaultPresetID {
                defaults.set(defaultPresetID.uuidString, forKey: defaultKey)
            }
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
        let pipPresets = presetsWithPIP
        if pipPresets.count == 1 {
            let singlePIPId = pipPresets[0].id
            var changed = false
            for i in presets.indices {
                if presets[i].id == singlePIPId && !presets[i].useForFacecam {
                    presets[i].useForFacecam = true
                    changed = true
                }
            }
            if changed { persist() }
        }
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
            presets[i] = preset
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
