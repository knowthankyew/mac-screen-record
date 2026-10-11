# Legal, Privacy, and Third-Party Attribution Notice

**Mac Screen Record**  
Copyright © 2026 knowthankyew and contributors  
Repository: [https://github.com/knowthankyew/mac-screen-record](https://github.com/knowthankyew/mac-screen-record)  

### Upstream Heritage & Hard Fork Notice
This software is an independent hard fork and continuation of **Free Mac Screen Recorder**:
- **Original Project:** Free Mac Screen Recorder
- **Original Author:** penguinpecker and contributors
- **Upstream Repository:** [https://github.com/penguinpecker/free-mac-screen-recorder](https://github.com/penguinpecker/free-mac-screen-recorder)
- **License:** MIT License (retained in full under [LICENSE](./LICENSE))

We acknowledge and express gratitude to the original upstream author for the foundational project architecture and initial ScreenCaptureKit integration.

---

## 1. Functional Scope Notice
Mac Screen Record is a native macOS utility application designed to capture display, window, application, and region video alongside microphone and system audio streams. All captured media is encoded via Apple VideoToolbox and saved directly to the user's local filesystem.

## 2. Consumer Privacy Defaults & Air-Gap Invariant
This application conforms to the `knowthankyew` Consumer-Safe Zero-Egress specification:
- **Zero Network Egress (`deny`):** Application code does not import or invoke networking APIs (`URLSession`, `Network.framework`, `NSURLConnection`, `CFNetwork`), establish BSD socket connections (`socket`, `connect`, `sys/socket.h`), or execute outbound network requests (statically verified across Swift and C/Objective-C sources during the build pipeline via `Scripts/audit-claims.py`, with automated GitHub Actions CI gating planned in Phase 9).
- **Zero Cloud Persistence:** Media is never uploaded to remote servers, cloud buckets, or third-party hosting services.
- **Zero Remote Telemetry:** The application does not bundle analytics SDKs, trackers, or remote error reporting pipelines. Diagnostics are handled exclusively through Apple's local unified logging subsystem (`os.Logger`).
- **Programmatic Claims Verification:** User-facing privacy assertions are derived directly at runtime from `PrivacyClaimsProvider`.

## 3. Sensitive Input & Password Protection
When the optional keystroke overlay is active:
- Keystrokes are inspected transiently in memory solely to render the floating visual indicator (`KeystrokeOverlayController`) and are never written to disk or logged.
- The overlay actively monitors `IsSecureEventInputEnabled()`. When the active application indicates secure event input (such as entering passwords, PINs, or master credentials in browsers, password managers, or terminal prompts), the keystroke overlay is immediately suppressed and faded out to prevent credential exposure in captured frames.

## 4. Software Bill of Materials (SBOM) & Supply Chain
- **Zero Third-Party Dependencies:** Mac Screen Record contains zero external Swift Package Manager dependencies. The dependency attack surface is limited strictly to Apple platform SDKs.
- **CycloneDX SBOM:** A standardized CycloneDX JSON Software Bill of Materials (`bom.json`) is generated during the application build pipeline (`Scripts/build-app.sh`) and packaged into `Contents/Resources/bom.json`.

## 5. Third-Party & Framework Attribution
- **Free Mac Screen Recorder by penguinpecker (MIT License):** Upstream codebase and foundational architecture.
- **Aperture by Sindre Sorhus (MIT License):** Referenced as an architectural design pattern for integrating ScreenCaptureKit with AVAssetWriter.
- **Apple macOS SDKs:** ScreenCaptureKit, AVFoundation, VideoToolbox, AppKit, SwiftUI, and Carbon HIToolbox.

## 6. Declared macOS TCC Usage Descriptions & Entitlements Justification

All macOS permission keys declared in `Resources/Info.plist` and `Resources/MacScreenRecord.entitlements` are restricted strictly to local capture and filesystem operations:

| Key / Entitlement | Source File | Plain-English Justification |
| :--- | :--- | :--- |
| `NSScreenCaptureUsageDescription` | `Info.plist` | Required by `ScreenCaptureKit` to capture display, window, application, or region video frames locally. |
| `NSCameraUsageDescription` | `Info.plist` | Required by `AVFoundation` to render the optional local presenter webcam picture-in-picture (PiP) overlay. |
| `NSMicrophoneUsageDescription` | `Info.plist` | Required by `AVFoundation` to capture optional microphone audio tracks alongside screen video. |
| `NSAppleEventsUsageDescription` | `Info.plist` | Required to enumerate window metadata for selective single-window and application capture. |
| `com.apple.security.device.camera` | `MacScreenRecord.entitlements` | Hardened Runtime entitlement enabling local camera hardware access for the PiP overlay when opted in by the user. |
| `com.apple.security.device.microphone` | `MacScreenRecord.entitlements` | Hardened Runtime entitlement enabling local microphone capture when opted in by the user. |
| `com.apple.security.device.audio-input` | `MacScreenRecord.entitlements` | Hardened Runtime entitlement enabling audio input stream capture for voiceover and level metering. |
| `com.apple.security.files.user-selected.read-write` | `MacScreenRecord.entitlements` | Enables writing recorded media and reading custom background images in user-selected local folders via `NSOpenPanel`. |
| `com.apple.security.files.downloads.read-write` | `MacScreenRecord.entitlements` | Allows saving recordings or GIF exports when the user selects a destination inside `~/Downloads`. |

See [LICENSE](./LICENSE) for the root MIT license terms.
