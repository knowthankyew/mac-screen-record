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
| **Complex Geometric Polygons** (Hexagons, octagons, superellipses) | **Circumvented / Descheduled** | Elaborate broadcast stencils add Metal shader complexity with zero evidentiary value. The standard circular Facecam PiP satisfies all presenter needs. |
| **HSV Color Wheel Sliders & Palette Steppers** (Phase 6.3) | **Streamlined** | Standard system color controls are sufficient; custom design studio color pickers are out of scope. |

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
- ✅ **Neural Engine Presenter PiP & Security Guards (v0.3.0)**:
  - Apple Neural Engine on-device person segmentation (`VNGeneratePersonSegmentationRequest`) with real-time Metal rendering.
  - Zero-egress background blur and virtual backdrops.
  - Keystroke overlay with active password masking via `IsSecureEventInputEnabled()`.
  - Global Carbon hotkeys (`⌃⌥⌘R` / `⌃⌥⌘S`) and Menu Bar status controller.
  - Automated CycloneDX JSON SBOM (`bom.json`) and `NOTICE.md` supply chain disclosures.

---

## 4. Active & Future Portfolio Roadmap

### Phase 7: Cryptographic Evidence Integrity (The Evidence Seal)
**Objective**: Provide verifiable local checksums and recording metadata manifests for regulatory filings and documentation workflows.

- **Cryptographic Checksumming**:
  - Immediately upon recording termination, compute SHA-256 and SHA-512 cryptographic hashes of the saved media container before closing the file handle.
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

### Phase 9: Automated Supply Chain & Zero-Egress CI Gate
**Objective**: Continuous automated verification that the codebase never introduces remote dependencies or network egress.

- **Static Zero-Egress CI Linter**:
  - GitHub Actions runner scanning all Swift source files for forbidden networking primitives (`URLSession`, `Network.framework`, `NSURLConnection`, `CFNetwork`, `WebKit`).
- **Zero-SPM Dependency Gate**:
  - Build failure if `url:` is detected in `Package.swift`.
- **Automated CycloneDX SBOM Attestation**:
  - Continuous validation of `bom.json` schema 1.5 compliance during every release build.
