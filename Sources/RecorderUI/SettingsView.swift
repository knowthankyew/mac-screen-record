import EncoderKit
import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings

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
                LabeledContent("Start recording", value: "⌃⌥⌘R")
                LabeledContent("Stop recording",  value: "⌃⌥⌘S")
                Text("Hotkeys are system-wide. Rebinding from inside the app is on the roadmap.")
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
        .frame(minWidth: 480, minHeight: 520)
        .padding(.bottom, 12)
    }
}
