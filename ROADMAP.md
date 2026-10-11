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

## 2. Scope Realignment: Circumventing Upstream Commercial Streamer Bloat

The inherited upstream roadmap included extensive planning for commercial content-creator and broadcasting studio tools. To preserve architectural purity and fulfill the `knowthankyew` consumer defense mission, those features are **circumvented and intentionally descheduled**:

| Inherited Upstream Proposal | Status | Portfolio Justification |
| :--- | :--- | :--- |
| **Modular Watermark & Branding Engine** (Phase 6.5) | **Circumvented / Descheduled** | Corporate logo branding and watermark overlays cater to commercial marketing, not consumer evidence gathering. |
| **Video PiP Playback Engine** (Phase 6.6: playing arbitrary MP4s inside PiP) | **Circumvented / Descheduled** | Embedding a file-based media player inside a capture overlay container creates code bloat, increases memory pressure, and diverges from honest reality recording. |
| **Complex Geometric Polygons** (Hexagons, octagons, architectural vaults) | **Circumvented / Descheduled** | Elaborate broadcast stencils add Metal shader complexity with zero evidentiary value. Clean Circle vs. Rounded-Rectangle framing is scheduled in Phase 11. |
| **HSV Color Wheel Sliders & Palette Steppers** (Phase 6.3) | **Streamlined (Phase 11)** | Standard macOS system color controls are sufficient; custom design studio color pickers are out of scope. |

---

## 3. Shipped & Stabilized Milestones (v0.1.0 – v0.3.0)

- ✅ **Core Hardware Capture & Encoding (v0.1.0)**:
  - Display, single-window, specific application, and drag-to-select region capture via ScreenCaptureKit.
  - VideoToolbox hardware-accelerated encoding (H.264, HEVC, Apple ProRes 422 / 4444).
  - System audio capture and microphone capture with live level meters.
- ✅ **Local Persistence & Presets (v0.2.0)**:
  - Local recordings library (`~/Movies/Mac Screen Record/`) with Finder reveal and non-destructive trash deletion.
  - Reusable capture presets with automated startup default loading and migration fallback.
  - Native Intel (`x86_64`) and Apple Silicon (`arm64`) architecture parity.
  - Stable self-signed local identity harness preserving macOS TCC permissions across builds.
- ✅ **Neural Engine Presenter PiP, Security Guards, Unit Tests & CI Gate (v0.3.0)**:
  - Apple Neural Engine on-device person segmentation (`VNGeneratePersonSegmentationRequest`) with real-time Metal rendering.
  - Zero-egress background blur, 5 virtual backdrops, custom background image replacement, cutout silhouette mode, and Quick-Toggle Facecam header workflow (`useForFacecam`).
  - Keystroke overlay with synchronous password masking via `IsSecureEventInputEnabled()`.
  - Global Carbon hotkeys (`⌃⌥⌘R` / `⌃⌥⌘S`) and Menu Bar status controller.
  - Automated CycloneDX JSON SBOM (`bom.json`), `NOTICE.md` supply chain disclosures, `Scripts/audit-claims.py` verification gate, 12-test `MacScreenRecordTests` unit test suite, and GitHub Actions CI + SLSA build provenance workflow (`.github/workflows/ci.yml`).

---

## 4. Active & Future Portfolio Roadmap

### Master Milestone Grid

| Phase | Milestone | Track | Scope & Deliverables | Status |
| :--- | :--- | :--- | :--- | :---: |
| **Phases 1–6** | **Core Capture, Universal Mac, Neural Engine PiP & Claims Linter** | Foundation (`v0.1.0 – v0.3.0`) | ScreenCaptureKit + VideoToolbox, Intel/ARM64 parity, stable TCC signing, auto-salvage, ANE/Metal PiP, Facecam quick-toggle, CycloneDX SBOM, `Scripts/audit-claims.py` (7-pass CodeRabbit 0-Major baseline) | ✅ **Shipped** |
| **Phase 7** | **Cryptographic Evidence Integrity (*The Evidence Seal*)** | Portfolio Governance | Post-finalization SHA-256 / SHA-512 checksumming and companion `.evidence.json` tamper-evident metadata manifest | 🟡 **Planned** |
| **Phase 8** | **Universal Keyboard Control & Workflow Polish** | Portfolio Governance | Expanded global Carbon hotkeys (`⌥Space` pause/resume, `⌃⌥P` Facecam, `⌃⌥K` keystrokes) and in-app hotkey remapping in Settings | 🟡 **Planned** |
| **Phase 9** | **Automated Supply Chain, Unit Tests & Zero-Egress CI Gate** | Portfolio Governance | GitHub Actions CI runner (`.github/workflows/ci.yml`), `MacScreenRecordTests` unit test suite (`swift run MacScreenRecordTests`), static zero-egress scanner (`Scripts/audit-claims.py`), and CycloneDX 1.5 SBOM + SLSA build provenance attestation | ✅ **Shipped** |
| **Phase 10** | **Post-Capture & Library Lossless Trim** | Post-Capture Workflow | Immediate post-recording trim-before-save modal **plus** posthumous lossless trimming of any existing/loaded recording from supported container formats (`.mp4`, `.mov`, `.m4v`) via `AVAssetExportPresetPassthrough` | 🔜 **Next After 7–8** |
| **Phase 11** | **Streamlined Facecam & PiP Improvements** | Presenter PiP Polish | **1.** Blurred custom image backdrop (`CIGaussianBlur` behind cutout on user-selected images); **2.** Circle vs. Rounded-Rectangle shape/aspect toggle; **3.** Standard system border color/width controls | 🔜 **Planned (Phase 10+)** |

---

### Phase 7: Cryptographic Evidence Integrity (The Evidence Seal)
**Objective**: Provide verifiable local checksums and recording metadata manifests for regulatory filings and documentation workflows.

- **Cryptographic Checksumming**:
  - Immediately upon recording termination, compute SHA-256 and SHA-512 cryptographic hashes of the saved media container after `AVAssetWriter.finishWriting()` completes and the file handle is closed.
- **Deterministic Evidence Manifest (`.evidence.json`)**:
  - Generate an optional companion metadata manifest alongside the output file (e.g., `Record_2026-10-09_12-00-00.mp4` + `Record_2026-10-09_12-00-00.evidence.json`):
    - **Temporal Integrity**: Precise start and end UTC timestamps tracked monotonically via `mach_continuous_time`.
    - **Capture Context**: Target display resolution, color space, active window titles, and application bundle identifiers.
    - **Audio Telemetry**: Verification of active audio input channels, sample rates, and system audio loopback state.
    - **Integrity Seal**: SHA-256 checksum and file byte size for reproducible local verification and external timestamp authority countersigning.

### Phase 8: Universal Keyboard Control & Workflow Polish
**Objective**: Fast, tactile, zero-permission hotkey controls for seamless evidence capture without mouse interference.

- **Expanded Global Hotkey Suite**:
  - `⌃⌥⌘R`: Start recording.
  - `⌃⌥⌘S`: Stop recording.
  - `⌥Space`: Non-destructive pause / resume with presentation timestamp (PTS) rewriting.
  - `⌃⌥P`: Quick toggle Facecam presenter overlay.
  - `⌃⌥K`: Quick toggle keystroke indicator.
- **In-App Hotkey Customization**:
  - Allow users to remap hotkeys within the Settings panel using Carbon event modifiers.

### Phase 9: Automated Supply Chain, Unit Tests & Zero-Egress CI Gate (Shipped)
**Objective**: Continuous automated verification that the codebase never introduces remote dependencies, regressions, or network egress.

- **Static Zero-Egress & Claims CI Linter**:
  - GitHub Actions workflow (`.github/workflows/ci.yml`) executing `Scripts/audit-claims.py` across both `Sources/` and `Tests/` for forbidden networking primitives (`URLSession`, `Network.framework`, `NSURLConnection`, `CFNetwork`, `WebKit`, BSD sockets).
- **Automated Unit Test Suite (`MacScreenRecordTests`)**:
  - 12 deterministic unit tests across `EncoderAndCaptureTests`, `PresetsAndLibraryTests`, and `PrivacyAndOverlayTests` executed via `swift run MacScreenRecordTests` without requiring full Xcode or TCC hardware permissions.
- **Zero-SPM Dependency Gate & Grouped Dependabot**:
  - Build failure if `url:` is detected in `Package.swift`; grouped GitHub Actions maintenance via `.github/dependabot.yml`.
- **Automated CycloneDX SBOM & SLSA Attestation**:
  - Continuous validation of `bom.json` schema 1.5 compliance and SLSA build provenance attestation during every `main` build.

---

## 5. Phase 10+: Post-Capture Trim & Streamlined PiP Improvements

### Phase 10: Post-Capture & Posthumous Library Lossless Trim
**Objective**: Eliminate dead air at the start and end of recordings without re-encoding or quality loss, both immediately after capture and posthumously from the Recordings Library or disk.

- **Dual Entry Points**:
  - **In-App Trim Before Save**: Optional review modal immediately after stopping a recording, allowing the user to trim start/end dead air before finalizing the file in the library.
  - **Posthumous Trim of Existing / Loaded Media**: Invoke the same trimmer directly from any recording in `RecordingsListView` (or by loading a supported `.mp4`, `.mov`, or `.m4v` file from disk) to save a trimmed copy (`Record_..._trimmed.mp4`) or replace the original via Trash-safe workflow.
- **Lossless Passthrough Engine**:
  - Scrubbable thumbnail filmstrip generated asynchronously via `AVAssetImageGenerator` with draggable In / Out handles.
  - Sub-second frame-accurate exports using `AVAssetExportSession` (`AVAssetExportPresetPassthrough`), preserving original hardware-encoded H.264, HEVC, and ProRes bitstreams with zero generation loss.

### Phase 11: Streamlined Facecam & PiP Improvements
**Objective**: Deliver high-utility presenter overlay refinements while maintaining zero-egress, native-only simplicity.

- **Blurred Custom Image Backdrop**:
  - Allow the Gaussian blur strength selector (Subtle `10px`, Balanced `20px`, Strong `35px`) to apply directly to user-selected custom background images (`WebcamBackgroundMode.customImage`) behind the Neural Engine person segmentation mask.
- **Circle vs. Rounded-Rectangle Framing**:
  - Clean shape toggle in Overlays switching the `WebcamPanel` / `WebcamMetalView` mask between the classic **1:1 Circle** and a **Rounded Rectangle** (with `1:1` square and `16:9` / `4:3` aspect options).
- **Standard System Border Controls**:
  - Native macOS `ColorPicker` and stroke width slider (`0px – 12px`) for the PiP border ring when `showBorder` is enabled.
