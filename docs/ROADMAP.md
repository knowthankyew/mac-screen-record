# Mac Screen Record — Strategic Architecture & Roadmap

> **Portfolio Alignment**: Native macOS Zero-Egress Evidence & Reality Capture Engine  
> **Governance Standard**: `knowthankyew` Consumer-Safe Zero-Egress & Air-Gap Invariant  
> **Target Baseline**: macOS 13.0+ (Ventura, Sonoma, Sequoia) | Apple Silicon & Intel x86_64  

---

## 1. Portfolio Architectural Scope & Treatment

Within the **`knowthankyew`** portfolio, `mac-screen-record` serves as the **Native macOS Reality & Evidence Capture Engine**. Its purpose is to provide users, advocates, and researchers with an air-gapped, zero-dependency utility to capture high-fidelity visual and auditory records of software workflows, regulatory interfaces, subscription disclosures, and user interface interactions.

Similar to how **`gradcast`** is explicitly designated in the Portfolio Master Brief as an *inherently public civic open-data engine*, **`mac-screen-record`** is explicitly designated as a **pure native desktop utility governed by local OS invariants**:
1. **Zero Network Egress**: Zero socket frameworks, zero telemetry SDKs, zero cloud uploads. The binary contains zero networking imports (`URLSession`, `Network.framework`, `NSURLConnection`, `CFNetwork`).
2. **Zero Third-Party Dependencies**: Zero SPM dependencies; strictly bound to native Apple SDKs (`ScreenCaptureKit`, `AVFoundation`, `VideoToolbox`, `Vision`, `Metal`).
3. **In-Memory Volatile Security**: Keystroke overlays operate transiently in RAM and automatically suppress when password fields are active (`IsSecureEventInputEnabled`).

---

## 2. Scope Realignment: Lean Native Architecture vs. Heavy Broadcast Suites

Rather than adopting heavy third-party broadcasting suites (such as OBS Studio scenes, web browser CEF sources, or cloud overlays), **`mac-screen-record`** implements rich presenter personalization and evidence branding using **pure, lightweight Apple native frameworks** (`AVFoundation`, `CoreGraphics`, `Metal`, `AppKit`, `CoreImage`):

| Feature Capability | Architecture & Native Implementation | Portfolio Justification |
| :--- | :--- | :--- |
| **Basic Geometric PiP Shapes** | Vector `CGPath` masks (Circle, Rounded-Rect, Oval, Hexagon, Diamond, Heart, Star) with matching border stroke paths | Clean visual framing without heavy Metal shader complexity or external polygon engines. |
| **Alternative Visual Sources** (Static Image & Video Loop) | Native `AVPlayerItemVideoOutput` and `CGImage` pipeline replacing live camera feed | Enables privacy-safe virtual avatars, static profile representations, and repeatable testing without camera activation. |
| **Transparent Branding / Watermark Overlay** | Local alpha-channel PNG image composited via Core Image / AppKit layer across all PiP variants | Allows lightweight organizational attribution, badges, or decorative borders with zero cloud dependencies. |
| **Standard System Color Controls** | Standard macOS `ColorPicker` and slider stroke controls | Native HIG consistency without maintaining custom HSV color wheels or palette steppers. |

---

## 3. Shipped & Stabilized Milestones (v0.1.0 – v0.5.0)

- ✅ **Core Hardware Capture & Encoding (v0.1.0)**:
  - Display, single-window, specific application, and drag-to-select region capture via ScreenCaptureKit.
  - VideoToolbox hardware-accelerated encoding (H.264, HEVC, Apple ProRes 422 / 4444).
  - System audio capture and microphone capture with live level meters.
- ✅ **Local Persistence & Presets (v0.2.0)**:
  - Local recordings library (`~/Movies/Mac Screen Record/`) with Finder reveal and non-destructive trash deletion.
  - Reusable capture presets with automated startup default loading and migration fallback.
  - Native Intel (`x86_64`) and Apple Silicon (`arm64`) architecture parity.
  - Stable self-signed local identity harness preserving macOS TCC permissions across builds.
- ✅ **Neural Engine Presenter PiP, Security Guards & Claims Linter (v0.3.0) — Phase 6**:
  - Apple Neural Engine on-device person segmentation (`VNGeneratePersonSegmentationRequest`) with real-time Metal rendering.
  - Zero-egress background blur, 5 virtual backdrops, custom background image replacement, cutout silhouette mode, and Quick-Toggle Facecam header workflow (`useForFacecam`).
  - Keystroke overlay with synchronous password masking via `IsSecureEventInputEnabled()`.
  - Global Carbon hotkeys (`⌃⌥⌘R` / `⌃⌥⌘S`) and Menu Bar status controller.
  - Automated CycloneDX JSON SBOM (`bom.json`), `NOTICE.md` supply chain disclosures, and `Scripts/audit-claims.py` verification gate.
- ✅ **Cryptographic Evidence Integrity (*The Evidence Seal*) (v0.3.0) — Phase 7**:
  - Immediate post-recording streaming SHA-256 and SHA-512 cryptographic hashing using native `CryptoKit` with $O(1)$ memory usage.
  - Deterministic `.evidence.json` companion metadata manifest conforming to `knowthankyew:evidence:v1` (temporal integrity via `mach_continuous_time`, capture context, audio telemetry, sealed badge in library, 1-click clipboard copy, and trash/delete lifecycle synchronization).
- ✅ **Universal Keyboard Control & Workflow Polish (v0.3.0) — Phase 8**:
  - Expanded global Carbon hotkeys (`⌃⌥⌘R` start, `⌃⌥⌘S` stop, `⌥Space` pause/resume with PTS rewriting, `⌃⌥P` Facecam toggle, `⌃⌥K` keystrokes toggle).
  - In-app hotkey customization table in Settings with key capture, modifier translation, Carbon handler suspension/resume, `UserDefaults` persistence, and "Reset Hotkeys to Defaults".
- ✅ **Automated Supply Chain, Unit Tests & Zero-Egress CI Gate (v0.3.0) — Phase 9**:
  - 23 deterministic unit tests across 6 test suites at v0.3.0 (47 across 8 as of v0.5.0) (`MacScreenRecordTests`) running in sub-second time without TCC hardware permissions.
  - Static zero-egress scanner and claims linter (`Scripts/audit-claims.py`) checking zero network imports, hotkeys, and TCC table parity.
  - GitHub Actions CI workflow (`.github/workflows/ci.yml`), CycloneDX 1.5 JSON SBOM (`bom.json`), and SLSA build provenance attestation.
- ✅ **Post-Capture & Library Lossless Trim (v0.3.0) — Phase 10**:
  - Sub-second, frame-accurate lossless trimming engine (`LosslessTrimmer`) leveraging `AVAssetExportPresetPassthrough` across `.mp4`, `.mov`, and `.m4v` bitstreams (H.264, HEVC, ProRes) with zero re-encoding and zero generation loss.
  - Interactive trim review modal (`VideoTrimModalView`) with asynchronous filmstrip generation (`AVAssetImageGenerator`), draggable In/Out handles with frame scrubbing, real-time timestamp displays, and looping playback preview.
  - Dual entry points: optional post-capture trim review before finalization (`settings.trimBeforeSave`), one-click trim from completion bar, row-level scissors button & context menu in Recordings Library, and posthumous trimming of any video file loaded from disk.
  - Dual save options: save trimmed copy (`_trimmed.mp4`) or replace original via macOS Trash-safe workflow with automated companion Evidence Seal recalculation.
- ✅ **Ephemeral Recording HUD, Open With & Zero-Ghost Recents (v0.4.0) — Phase 12**:
  - Ephemeral recording companion in macOS menu bar that exists exclusively during active capture (`.recording` / `.paused`) with live `MM:SS` elapsed duration timer, notch-safe real estate, context-aware Pause/Resume (`⌥Space`), in-flight overlay toggles, distraction-free auto-minimize, and amnesiac Hard Burn purge (`⌃⌥⌘⌫`).
  - Native macOS "Open With" integration (`CFBundleDocumentTypes`) and Dock icon drag-and-drop routing external `.mp4`, `.mov`, and `.m4v` video files directly into lossless trim review (`VideoTrimModalView`).
  - Standard system application menu bar commands (`⌘O` Open Video to Trim…, `⌘L` Recordings Library…, and "Open Recent" submenu).
  - Strict zero-ghost invariant dynamically excluding any files deleted from disk from recent history and library listings.
  - Visual callout and pulsing radar animation drawing immediate focus to the saved recording path.
- ✅ **Extended PiP Shapes, Alternate Visual Sources & Transparent Branding (v0.5.0) — Phase 13**:
  - Expanded geometric PiP outlines (Oval, Hexagon, Diamond, Heart, Star) with synchronized `CGPath` vector masks and border stroke layers inset by half border width.
  - Camera-free alternative visual sources: Static Image Avatar (`.png`, `.jpg`, `.heic`, `.tiff`) and Looping Video File (`.mp4`, `.mov`, `.m4v`) via native Apple `AVPlayerItemVideoOutput` / `AVPlayerLooper`, routed through Neural Engine segmentation and backdrop framing.
  - Transparent PNG branding and custom frame overlay composited upright (non-mirrored) over all PiP presenter modes with preset persistence.

---

## 4. Active & Future Portfolio Roadmap

### Master Milestone Grid

| Phase | Milestone | Track | Scope & Deliverables | Status |
| :--- | :--- | :--- | :--- | :---: |
| **Phases 1–6** | **Core Capture, Universal Mac, Neural Engine PiP & Claims Linter** | Foundation (`v0.1.0 – v0.3.0`) | ScreenCaptureKit + VideoToolbox, Intel/ARM64 parity, stable TCC signing, auto-salvage, ANE/Metal PiP, Facecam quick-toggle, CycloneDX SBOM, `Scripts/audit-claims.py` (7-pass CodeRabbit 0-Major baseline) | ✅ **Shipped** |
| **Phase 7** | **Cryptographic Evidence Integrity (*The Evidence Seal*)** | Portfolio Governance | Post-finalization SHA-256 / SHA-512 streaming checksumming and companion `.evidence.json` tamper-evident metadata manifest conforming to `knowthankyew:evidence:v1` | ✅ **Shipped** |
| **Phase 8** | **Universal Keyboard Control & Workflow Polish** | Portfolio Governance | Expanded global Carbon hotkeys (`⌃⌥⌘R` start, `⌃⌥⌘S` stop, `⌥Space` pause/resume, `⌃⌥P` Facecam, `⌃⌥K` keystrokes) and in-app hotkey remapping in Settings | ✅ **Shipped** |
| **Phase 9** | **Automated Supply Chain, Unit Tests & Zero-Egress CI Gate** | Portfolio Governance | GitHub Actions CI runner (`.github/workflows/ci.yml`), `MacScreenRecordTests` unit test suite (`swift run MacScreenRecordTests`), static zero-egress scanner (`Scripts/audit-claims.py`), and CycloneDX 1.5 SBOM + SLSA build provenance attestation | ✅ **Shipped** |
| **Phase 10** | **Post-Capture & Library Lossless Trim** | Post-Capture Workflow | Immediate post-recording trim-before-save modal **plus** posthumous lossless trimming of any existing/loaded recording from supported container formats (`.mp4`, `.mov`, `.m4v`) via `AVAssetExportPresetPassthrough` | ✅ **Shipped** |
| **Phase 11** | **Streamlined Facecam & PiP Improvements** | Presenter PiP Polish | **1.** Blurred custom image backdrop (`CIGaussianBlur` behind cutout on user-selected images); **2.** Circle vs. Rounded-Rectangle shape/aspect toggle; **3.** Standard system border color/width controls | ✅ **Shipped** |
| **Phase 12** | **Ephemeral Recording HUD & Dynamic Session Companion** | Capture UX & Governance | Zero-bloat transient status bar item with live elapsed duration (`MM:SS` / `HH:MM:SS`), first-class Pause/Resume controls (`⌥Space`), distraction-free auto-minimize, in-flight overlay toggles, and amnesiac Hard Burn purge | ✅ **Shipped** |
| **Phase 13** | **Extended PiP Shapes, Alternate Visual Sources & Transparent Branding** | Presenter PiP & Branding (`v0.5.0`) | **1.** Expanded basic geometric shapes (Oval, Hexagon, Diamond, Heart, Star) with synchronized `CGPath` border strokes; **2.** Static image & looping video alternative visual sources substituting camera; **3.** Transparent PNG branding/frame overlay across all variants | ✅ **Shipped** |
| **Phase 14** | **General Availability Hardening, Distribution & OBS-User Gap Polish** | Release Candidate (`v1.0.0`) | **1.** Full user QA & OBS-user gap assessment; **2.** Hardware resilience & edge-case hardening; **3.** First-run onboarding & HIG refinement; **4.** Universal drag-to-install DMG packaging | 🔜 **Up Next (v1.0.0 Target)** |

---

### Phase 7: Cryptographic Evidence Integrity (The Evidence Seal) ✅ Shipped
**Objective**: Provide verifiable local checksums and recording metadata manifests for regulatory filings and documentation workflows.

- **Cryptographic Checksumming**:
  - Immediately upon recording termination, compute streaming SHA-256 and SHA-512 cryptographic hashes using native `CryptoKit` in 64 KB buffers to maintain $O(1)$ memory usage.
- **Deterministic Evidence Manifest (`.evidence.json`)**:
  - Generate an optional companion metadata manifest alongside the output file conforming to `knowthankyew:evidence:v1`:
    - **Temporal Integrity**: Precise start and end UTC timestamps tracked monotonically via `mach_continuous_time` and Mach timebase info.
    - **Capture Context**: Target display resolution, color space, active window titles, FPS, and codec.
    - **Audio Telemetry**: Verification of active audio input channels, sample rates, microphone device IDs, and system audio loopback state.
    - **Integrity Seal**: SHA-256 and SHA-512 checksums and file byte size for reproducible local verification.
    - **Library Lifecycle & UI**: Automatic companion `.evidence.json` cleanup on delete/trash, rename synchronization, visual "Sealed" badge in `RecordingsListView`, and 1-click SHA-256 clipboard copy.

### Phase 8: Universal Keyboard Control & Workflow Polish ✅ Shipped
**Objective**: Fast, tactile, zero-permission hotkey controls for seamless evidence capture without mouse interference.

- **Expanded Global Hotkey Suite**:
  - `⌃⌥⌘R`: Start recording.
  - `⌃⌥⌘S`: Stop recording.
  - `⌥Space`: Non-destructive pause / resume with presentation timestamp (PTS) rewriting.
  - `⌃⌥P`: Quick toggle Facecam presenter overlay.
  - `⌃⌥K`: Quick toggle keystroke indicator.
- **In-App Hotkey Customization**:
  - Full in-app shortcut remapping table in Settings with key capture, Carbon modifier translation, `UserDefaults` persistence, and "Reset Hotkeys to Defaults" capability.

### Phase 9: Automated Supply Chain, Unit Tests & Zero-Egress CI Gate ✅ Shipped
**Objective**: Continuous automated verification that the codebase never introduces remote dependencies, regressions, or network egress.

- **Static Zero-Egress & Claims CI Linter**:
  - GitHub Actions workflow (`.github/workflows/ci.yml`) executing `Scripts/audit-claims.py` across both `Sources/` and `Tests/` for forbidden networking primitives (`URLSession`, `Network.framework`, `NSURLConnection`, `CFNetwork`, `WebKit`, BSD sockets).
- **Automated Unit Test Suite (`MacScreenRecordTests`)**:
  - 18 deterministic unit tests across 5 test suites (`EncoderAndCaptureTests`, `PresetsAndLibraryTests`, `PrivacyAndOverlayTests`, `EvidenceSealTests`, `HotkeyTests`) executed via `swift run MacScreenRecordTests` without requiring full Xcode or TCC hardware permissions.
- **Zero-SPM Dependency Gate & Grouped Dependabot**:
  - Build failure if `url:` is detected in `Package.swift`; grouped GitHub Actions maintenance via `.github/dependabot.yml`.
- **Automated CycloneDX SBOM & SLSA Attestation**:
  - Continuous validation of `bom.json` schema 1.5 compliance and SLSA build provenance attestation during every `main` build.

---

## 5. Recent & Shipped Milestones (Phases 10–13)

### Phase 10: Post-Capture & Posthumous Library Lossless Trim ✅ Shipped
**Objective**: Eliminate dead air at the start and end of recordings without re-encoding or quality loss, both immediately after capture and posthumously from the Recordings Library or disk.

- **Dual Entry Points**:
  - **In-App Trim Before Save**: Optional review modal immediately after stopping a recording, allowing the user to trim start/end dead air before finalizing the file in the library.
  - **Posthumous Trim of Existing / Loaded Media**: Invoke the same trimmer directly from any recording in `RecordingsListView` (or by loading a supported `.mp4`, `.mov`, or `.m4v` file from disk) to save a trimmed copy (`Record_..._trimmed.mp4`) or replace the original via Trash-safe workflow.
- **Lossless Passthrough Engine**:
  - Scrubbable thumbnail filmstrip generated asynchronously via `AVAssetImageGenerator` with draggable In / Out handles.
  - Sub-second frame-accurate exports using `AVAssetExportSession` (`AVAssetExportPresetPassthrough`), preserving original hardware-encoded H.264, HEVC, and ProRes bitstreams with zero generation loss.

### Phase 11: Streamlined Facecam & PiP Improvements ✅ Shipped
**Objective**: Deliver high-utility presenter overlay refinements while maintaining zero-egress, native-only simplicity.

- **Blurred Custom Image Backdrop**:
  - Allow the Gaussian blur strength selector (Subtle `10px`, Balanced `20px`, Strong `35px`) to apply directly to user-selected custom background images (`WebcamBackgroundMode.customImage`) behind the Neural Engine person segmentation mask.
- **Circle vs. Rounded-Rectangle Framing**:
  - Clean shape toggle in Overlays switching the `WebcamPanel` / `WebcamMetalView` mask between the classic **1:1 Circle** and a **Rounded Rectangle** (with `1:1` square and `16:9` / `4:3` aspect options).
- **Standard System Border Controls**:
  - Native macOS `ColorPicker` and stroke width slider (`0px – 12px`) for the PiP border ring when `showBorder` is enabled.

### Phase 12: Ephemeral Recording HUD & Dynamic Session Companion ✅ Shipped
**Objective**: Deliver a lightweight, zero-bloat menu bar companion that only exists during active recording sessions, surfacing live capture duration, tactile pause/resume controls, distraction-free desktop capture, and amnesiac data purging.

- **Zero-Bloat Ephemeral Lifecycle**:
  - **No Idle Footprint**: Zero status bar presence when the application is idle. The `NSStatusItem` is created dynamically the moment capture starts (`.recording` / `.paused`) and is completely deallocated (`NSStatusBar.system.removeStatusItem`) upon session completion, cancellation, or error reset.
  - **Notch-Safe Real Estate**: Preserves critical menu bar width on modern MacBook displays (M-series camera notches), strictly respecting macOS Human Interface Guidelines.
- **Live Status Bar Timer & State Indicator**:
  - Real-time elapsed recording duration rendered directly in the macOS menu bar:
    - **Active**: Red recording indicator with wall-clock elapsed time (excluding paused intervals) formatted as `MM:SS` (or `HH:MM:SS` past one hour, e.g. `02:45` or `01:02:45`).
    - **Paused**: Pause glyph with frozen presentation timestamp duration (e.g. `02:00 (Paused)`).
  - Tooltip displaying active capture target (display resolution or application window title), hardware encoding profile, and elapsed time.
- **First-Class Pause / Resume Controls**:
  - Prominent, context-aware toggle in the dropdown: **"Pause Recording (⌥Space)"** / **"Resume Recording (⌥Space)"**.
  - Drives the same `CaptureSession` pause/resume path, which excises paused intervals via presentation timestamp (PTS) rewriting.
- **Distraction-Free Desktop Capture**:
  - Optional setting to automatically minimize or hide the main Mac Screen Record window upon capture start.
  - Because the ephemeral menu bar HUD provides live duration feedback, pause controls, and termination actions, the main recorder window never clutters screen captures or full-desktop evidence recordings.
  - Window automatically restores (or brings up post-capture trim review) upon capture termination.
- **Session Finalization & Amnesiac "Hard Burn"**:
  - **Stop Recording (`⌃⌥⌘S`)**: Cleanly stops capture, updates the local library, and writes the cryptographic Evidence Seal manifest (`.evidence.json`).
  - **Trim Before Saving**: Instant post-capture review routing directly into the lossless frame-accurate trimmer (`VideoTrimModalView`), allowing start/end dead-air pruning without altering global app defaults.
  - **Hard Burn / Amnesiac Discard (`⌃⌥⌘⌫`)**: Conforms to the `knowthankyew` portfolio privacy standard:
    - Immediately invokes `AVAssetWriter.cancelWriting()`.
    - Directly unlinks partial video artifacts from disk (bypassing `~/.Trash` to eliminate residual storage leaks).
    - Aborts pending Evidence Seal checksum workers, wipes volatile in-memory keystroke buffers, and resets audio level monitors.
- **In-Flight Telemetry & Quick Toggles**:
  - Read-only capture telemetry: selected microphone device (active/disabled), system audio capture state, and active capture target.
  - In-flight overlay toggles: Quick toggle Facecam presenter PiP (`⌃⌥P`), keystroke overlay (`⌃⌥K`), and mouse click highlights.

### Phase 13: Extended PiP Shapes, Alternate Visual Sources & Transparent Branding (v0.5.0) ✅ Shipped
**Objective**: Complete the presenter overlay suite with versatile geometric outlines, camera-free visual media sources (static images & looping video clips), and custom alpha-channel branding/frame overlays while maintaining strict zero-egress invariants and Apple native performance.

- **Expanded Geometric PiP Outlines**:
  - Add basic geometric shapes beyond Circle and Rounded Rectangle:
    - **Oval / Ellipse**: Smooth curved framing ideal for presenter busts and vertical avatars.
    - **Hexagon**: Symmetrical 6-sided polygon offering a modern, technical aesthetic.
    - **Diamond / Rhombus**: Dynamic 4-point angular framing.
    - **Heart & Star**: Playful presentation shapes providing custom flair.
  - Implement shape framing via native vector `CGPath` masks on `CALayer.mask` / `WebcamMetalView` with mathematically aligned border stroke paths, ensuring custom `NSColor` and border width (0–12px) cleanly track the exact perimeter.
- **Alternative Visual Sources (Camera Substitute / Virtual Presenter)**:
  - Allow users to select an alternative visual source instead of an active hardware webcam:
    - **Static Image Avatar**: PNG, JPEG, HEIC, or TIFF profile picture or character avatar displayed in the PiP window.
    - **Video Clip Loop**: Local supported video file (`.mp4`, `.mov`, `.m4v`) played on a seamless loop via native `AVPlayerItemVideoOutput` / `AVAssetReader`.
  - Fully compatible with all downstream PiP effects: shapes, aspect ratios, borders, drop shadows, and position dragging, enabling camera-free recording, avatar presentation, or repeatable test captures.
- **Transparent Branding & Frame Overlay**:
  - Allow selection of an alpha-channel transparent image (PNG) as a branding overlay or custom border frame.
  - Composited directly over or around the presenter PiP layer, available across all modes (live camera, blur backdrop, virtual preset, cutout silhouette, or media source).
  - Preserved in capture presets for streamlined reusable presentation setups.

---

## 6. Target Milestone: Phase 14 — General Availability, Distribution & OBS-User Gap Polish (v1.0.0) 🔜

### Phase 14: General Availability, Distribution & OBS-User Gap Polish (v1.0.0) 🔜 Planned
**Objective**: Transition Mac Screen Record from feature-complete preview (`v0.5.0`) to its official, production-grade General Availability (`v1.0.0`) release, incorporating targeted OBS-user feedback, edge-case hardware resilience, and streamlined drag-to-install distribution.

- **OBS-User Comparative Gap Assessment & UX Refinement**:
  - Evaluate feedback from real-world OBS users (e.g. streaming/recording workflows on Windows) to identify lightweight, high-utility native capture enhancements while strictly rejecting broadcast/streaming bloat (no CEF browser scenes, no RTMP servers).
  - High-potential candidates for native inclusion:
    - **Capture Countdown**: Optional pre-roll timer (`3… 2… 1…`) to eliminate clicking dead air.
    - **Visual Recording Perimeter**: Subtle on-screen border indicator outlining the active capture display or cropped window.
    - **Mic Push-to-Talk / Mute Shortcut**: Global or session hotkey to temporarily suppress microphone input.
    - **Multi-Track Audio Channels**: Independent mic and system audio track multiplexing in `.mp4`/`.mov` containers for post-production balancing.
- **Hardware & Session Resilience Hardening**:
  - Comprehensive edge-case handling across dynamic macOS hardware changes:
    - Mid-recording audio route changes (e.g., Bluetooth/AirPods battery exhaustion, USB mic disconnect).
    - Display topology changes (hot-unplugging or re-arranging external displays during capture).
    - System sleep, screen lock, and wake recovery during paused or active sessions.
    - Extended-duration capture stress testing (verifying flat memory footprint on 1+ hour 4K recordings).
- **First-Run Onboarding & Human Interface Polish**:
  - Streamlined permission onboarding flow guiding users through macOS Screen Recording, Microphone, and Camera authorizations with zero friction.
  - Built-in shortcuts cheat sheet and application help documentation conforming to macOS Human Interface Guidelines.
- **Production Packaging & Release Automation**:
  - Universal binary (`arm64` + `x86_64`) drag-to-install `.dmg` packager with custom background art and Applications symlink.
  - Automated notarization and staple harness for friction-free Gatekeeper validation.
  - Embedded CycloneDX 1.5 SBOM (`bom.json`) and provenance disclosures packaged into release assets.
