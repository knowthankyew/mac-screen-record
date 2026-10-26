<!-- diagram-meta
  last-validated: 2026-10-26
  validated-commit: 6b92f53
  covers: [Sources/**, Package.swift, Resources/**, Scripts/**]
  generated-by: manual
-->

# Architecture & Invariants Specification: Mac Screen Record

> Pure native macOS zero-egress screen recorder, evidence capture studio, and hardware-accelerated presenter engine.

---

## 1. Executive Summary

`mac-screen-record` is the native macOS desktop engine in the `knowthankyew` portfolio built for capturing unassailable evidence of consumer fraud, billing discrepancies, and subscription dark patterns. Operating with strict zero external dependencies and guaranteed compile-time air-gapping (zero network frameworks or socket primitives), it uses macOS native frameworks (`ScreenCaptureKit`, `VideoToolbox`, `Vision`, `Metal`) to capture 4K60 video, audio, and webcam presenter PiP directly on local Apple Silicon, validated continuously by `Scripts/audit-claims.py`.

---

## 2. System Architecture & Pipeline Boundaries

### A. Execution Sandbox & Hardware Acceleration Boundary

```mermaid
flowchart TD
    subgraph AppleHardware["Apple Silicon & macOS Subsystems"]
        Display["🖥️ Retina Display & Windows"]
        Camera["📷 FaceTime / External Camera"]
        Microphone["🎙️ CoreAudio Inputs"]
        ANE["🧠 Apple Neural Engine (ANE)"]
        GPU["⚡ Metal GPU / Apple Silicon Media Engine"]
    end

    subgraph OSFrameworks["Zero-Egress Native Apple Frameworks"]
        SCK["ScreenCaptureKit<br/><i>(Screen & System Audio Capture)</i>"]
        AVF["AVFoundation<br/><i>(Camera Input & MP4 Muxing)</i>"]
        Vision["Vision.framework<br/><i>(On-Device Person Segmentation)</i>"]
        VTB["VideoToolbox<br/><i>(Hardware H.264 / HEVC / ProRes)</i>"]
        Carbon["Carbon.HIToolbox<br/><i>(Global Hotkeys: ⌃⌥⌘R, ⌃⌥⌘S)</i>"]
    end

    subgraph AppArchitecture["Mac Screen Record Modules (Sources/)"]
        subgraph Capture["CaptureCore"]
            StreamMgr["StreamManager<br/><code>Sources/CaptureCore/CaptureSession.swift</code>"]
            PiPCompositor["Presenter PiP Engine<br/><code>Sources/RecorderUI/WebcamVideoProcessor.swift</code>"]
            OverlayMgr["Metal Overlay Engine<br/><code>Sources/RecorderUI/WebcamMetalView.swift</code>"]
        end

        subgraph Devices["DeviceKit"]
            DeviceEnum["DeviceManager<br/><code>Sources/DeviceKit/DeviceManager.swift</code>"]
        end

        subgraph Encoding["EncoderKit"]
            HwEncoder["HardwareVideoEncoder<br/><code>Sources/EncoderKit/VideoEncoder.swift</code>"]
            FileWriter["AssetWriterMuxer<br/><code>Sources/EncoderKit/VideoEncoder.swift</code>"]
        end

        subgraph Presentation["RecorderUI"]
            SwiftUIBar["Floating Recorder Control Bar"]
            KeystrokeView["Keystroke Overlay<br/><i>(Masks on IsSecureEventInputEnabled)</i>"]
            PrivacyClaims["PrivacyClaimsProvider<br/><code>Sources/RecorderUI/PrivacyClaims.swift</code>"]
        end
    end

    subgraph ClaimsGate["Verification & Claims Linting Gate"]
        ClaimsLinter["🛡️ Scripts/audit-claims.py<br/><i>(Verifies zero sockets, zero SPM deps, version parity)</i>"]
        SBOM["📦 Scripts/generate-sbom.py<br/><i>(CycloneDX 1.5 JSON SBOM)</i>"]
    end

    subgraph LocalStorage["Local Disk Only"]
        MP4["📁 ~/Movies/Recordings/*.mp4<br/><i>(Zero Network Transmission)</i>"]
    end

    %% Hardware to OS
    Display --> SCK
    Camera & Microphone --> AVF
    Camera --> Vision
    ANE -.-> Vision
    GPU -.-> VTB & PiPCompositor

    %% Frameworks to App
    SCK --> StreamMgr
    AVF --> StreamMgr
    Vision --> PiPCompositor
    Carbon --> SwiftUIBar

    %% Internal App Flow
    StreamMgr --> PiPCompositor
    PiPCompositor --> OverlayMgr
    OverlayMgr --> HwEncoder
    HwEncoder --> FileWriter
    FileWriter --> MP4

    SwiftUIBar --> KeystrokeView
    PrivacyClaims -.->|"Dynamic Claims Grounding"| SwiftUIBar
    ClaimsLinter -.->|"CI Fail-Closed Audit"| AppArchitecture

    classDef hw fill:#0f172a,stroke:#64748b,stroke-width:1px,color:#f8fafc;
    classDef fw fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef app fill:#14532d,stroke:#22c55e,stroke-width:2px,color:#f8fafc;
    classDef gate fill:#78350f,stroke:#f59e0b,stroke-width:2px,color:#f8fafc;
    classDef disk fill:#312e81,stroke:#818cf8,stroke-width:1px,color:#f8fafc;

    class Display,Camera,Microphone,ANE,GPU hw;
    class SCK,AVF,Vision,VTB,Carbon fw;
    class StreamMgr,PiPCompositor,OverlayMgr,DeviceEnum,HwEncoder,FileWriter,SwiftUIBar,KeystrokeView,PrivacyClaims app;
    class ClaimsLinter,SBOM gate;
    class MP4 disk;
```

### B. Capture, Hardware Encode & Amnesiac Purge Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor User as User / Presenter
    participant Bar as RecorderUI (SwiftUI)
    participant SCK as ScreenCaptureKit
    participant Metal as Metal Presenter PiP
    participant Enc as VideoToolbox Hardware Encoder
    participant Claims as Claims Provider & Keystroke
    participant Disk as Local Storage

    User->>Bar: Press ⌃⌥⌘R (Start Recording)
    Bar->>Claims: Check IsSecureEventInputEnabled()
    Claims-->>Bar: Password protection status
    Bar->>SCK: Initialize SCStream (4K60, zero-drop queue)
    Bar->>Metal: Activate Metal presenter PiP & overlays
    loop Every Video Frame (60 FPS)
        SCK->>Metal: Deliver CMSampleBuffer (Screen + Audio)
        Metal->>Metal: Composite Vision segmented presenter & branding
        Metal->>Enc: Dispatch hardware pixel buffer (CVPixelBuffer)
        Enc->>Enc: Encode H.264 / HEVC / ProRes via VideoToolbox
        Enc->>Disk: Append to local fragmented MP4
    end

    alt Save Recording
        User->>Bar: Press ⌃⌥⌘S (Stop Recording)
        Bar->>Enc: FinishEncodingSession()
        Enc->>Disk: Finalize MP4 container
        Bar-->>User: Notification: Recording saved to local disk
    else Amnesiac Discard ("Nuclear Cancel")
        User->>Bar: Click "Discard / Cancel"
        Bar->>Enc: AbortSession()
        Bar->>Disk: Physically unlink partial temporary file
        Bar->>Metal: Purge texture caches & Vision segmentation buffers
        Bar-->>User: Clean amnesiac reset (Zero disk residual)
    end
```

---

## 3. Core Architectural Invariants

| # | Invariant | Description & Enforcement |
|:--|:----------|:--------------------------|
| 1 | **Zero-Egress Air-Gap** | Zero networking frameworks (`Network`, `CFNetwork`, `WebKit`) and zero BSD sockets (`socket`, `connect`, `URLSession`) exist in source tree; enforced fail-closed by `Scripts/audit-claims.py`. |
| 2 | **Zero Remote SPM Dependencies** | `Package.swift` contains zero external package URLs (`url:` forbidden). All capabilities built on Apple first-party SDKs. |
| 3 | **Password Masking Protection** | Keystroke overlay inspects `IsSecureEventInputEnabled()` before rendering; automatically suppresses password keystrokes. |
| 4 | **Dynamic UI Claims Parity** | `PrivacyClaimsProvider.currentClaims()` dynamically confirms zero egress, air-gap status, and memory isolation to the SwiftUI interface. |
| 5 | **Hardware-Accelerated Encoding** | Uses VideoToolbox hardware encoders directly with zero software CPU transcode bottlenecks. |

---

## 4. Directory Structure

```
mac-screen-record/
├── Package.swift                # Zero remote dependency package manifest
├── Resources/
│   ├── Info.plist               # App metadata, bundle identifier & permissions
│   └── MacScreenRecord.entitlements # Hardened runtime entitlements
├── Scripts/
│   ├── audit-claims.py          # Architectural claims, zero-egress & parity linter
│   ├── build-app.sh             # App bundle packager & code signing runner
│   ├── generate-sbom.py         # CycloneDX 1.5 JSON SBOM generator
│   └── setup-stable-signing.sh  # Code signing identity configuration
├── Sources/
│   ├── CaptureCore/             # ScreenCaptureKit, Metal PiP & Vision segmentation
│   ├── DeviceKit/               # Display, camera & audio input enumerators
│   ├── EncoderKit/              # VideoToolbox hardware encoder & MP4 writer
│   ├── MacScreenRecord/         # App executable entrypoint
│   └── RecorderUI/              # SwiftUI controls, hotkeys & PrivacyClaimsProvider
├── Tests/
│   └── MacScreenRecordTests/    # Unit tests for capture, encoders & claims
└── docs/
    ├── ARCHITECTURE.md          # Architecture, data flow & invariant specification
    ├── QA_CHECKLIST.md          # Release qualification procedure
    ├── RELEASE_NOTES.md         # Version history & changelogs
    └── ROADMAP.md               # Feature phases & milestones
```
