import AppKit
import Carbon.HIToolbox
import EncoderKit
import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var listeningAction: HotkeyAction?
    @State private var keyMonitor: Any?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("Defaults") {
                Picker("Codec", selection: $settings.defaultCodec) {
                    ForEach(OutputCodec.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Stepper(value: $settings.defaultFPS, in: 24...120, step: 1) {
                    Text("Frame rate: \(settings.defaultFPS) fps")
                }
                Toggle("Show cursor", isOn: $settings.defaultShowsCursor)
                Toggle("Capture system audio", isOn: $settings.defaultCaptureSystemAudio)
                Toggle("Generate cryptographic evidence seal (.evidence.json)", isOn: $settings.generateEvidenceSeal)
                Text("Generates tamper-evident SHA-256 and SHA-512 evidence manifests alongside recordings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Recordings folder").font(.body)
                        Text(settings.outputFolder.path)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose…") { settings.pickOutputFolder() }
                }
            }

            Section("Hotkeys") {
                ForEach(HotkeyAction.allCases) { action in
                    HStack {
                        Text(action.displayName)
                        Spacer()
                        if listeningAction == action {
                            HStack(spacing: 6) {
                                Text("Press keys…")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Button("Cancel") { stopListening() }
                                    .buttonStyle(.borderless)
                            }
                        } else {
                            Button(currentBinding(for: action).displayString) {
                                startListening(for: action)
                            }
                            .help("Click to remap shortcut (Esc to cancel)")
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Reset Hotkeys to Defaults") {
                        stopListening()
                        settings.resetHotkeyBindingsToDefaults()
                    }
                    .font(.caption)
                }

                Text("Global Carbon hotkeys operate system-wide with zero accessibility permissions. Defaults: Start: ⌃⌥⌘R, Stop: ⌃⌥⌘S, Pause/Resume: ⌥Space, Facecam: ⌃⌥P, Keystrokes: ⌃⌥K.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy & Data Governance") {
                let claims = PrivacyClaimsProvider.currentClaims()
                LabeledContent("Execution Model", value: claims.summaryBadge)
                LabeledContent("Network Egress", value: claims.networkEgressPolicy.uppercased() + " (Air-Gapped)")
                LabeledContent("Telemetry", value: "Disabled (Local OSLog Only)")
                LabeledContent("Third-Party Packages", value: "\(claims.thirdPartyDependenciesCount) Dependencies")
                LabeledContent("Password Masking", value: claims.secureInputSuppressionEnabled ? "Guarded (SecureEventInput)" : "Standard")
                LabeledContent("Evidence Integrity", value: settings.generateEvidenceSeal ? "SHA-256 + SHA-512 Sealed" : "Disabled")
                Text("Conforms to the knowthankyew Zero-Egress specification. No video, audio, keystroke, or telemetry data ever leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: "Mac Screen Record")
                LabeledContent("Project", value: "github.com/knowthankyew/mac-screen-record")
                LabeledContent("Heritage", value: "Hard fork of free-mac-screen-recorder (MIT)")
                LabeledContent("Governance Standard", value: "knowthankyew Zero-Egress v1.0")
                Text("MIT licensed. Hard fork of penguinpecker/free-mac-screen-recorder. Built on ScreenCaptureKit, AVFoundation, and VideoToolbox. See NOTICE.md for supply chain and attribution disclosures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .padding(.bottom, 12)
        .onDisappear {
            stopListening()
        }
    }

    private func currentBinding(for action: HotkeyAction) -> HotkeyBinding {
        settings.hotkeyBindings[action] ?? HotkeyBinding.defaultBinding(for: action)
    }

    private func startListening(for action: HotkeyAction) {
        stopListening()
        listeningAction = action
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // Escape
                self.stopListening()
                return nil
            }
            var carbonMods = 0
            let flags = event.modifierFlags
            if flags.contains(.control) { carbonMods |= controlKey }
            if flags.contains(.option)  { carbonMods |= optionKey }
            if flags.contains(.shift)   { carbonMods |= shiftKey }
            if flags.contains(.command) { carbonMods |= cmdKey }

            // Reject bare non-function keys to avoid intercepting regular typing system-wide
            let functionKeyCodes: Set<Int> = [
                kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
            ]
            let isFunctionKey = functionKeyCodes.contains(Int(event.keyCode))
            if carbonMods == 0 && !isFunctionKey {
                NSSound.beep()
                return nil // Keep listening
            }

            let binding = HotkeyBinding(keyCode: Int(event.keyCode), modifiers: carbonMods)
            self.settings.setHotkeyBinding(binding, for: action)
            self.stopListening()
            return nil
        }
    }

    private func stopListening() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        listeningAction = nil
    }
}
