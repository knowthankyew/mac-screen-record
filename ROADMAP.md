# Mac Screen Record — Roadmap

**Target versions:** v0.4.0 – v0.8.0+  
**Subsystems:** `RecorderUI`, `CaptureCore`, `DeviceKit`, `EncoderKit`, Build & Distribution

---

## Shipped (Phases 1 – 5)

- ✅ **Phase 1 — Core Capture & Encoding**: Display/window/app source selection, system audio capture, microphone capture with AGC, H.264/HEVC/ProRes encoding, custom resolution overrides.
- ✅ **Phase 2 — Interaction & Persistence**: Drag-to-select region capture, live recording timer, real-time dual audio level meters, recordings library with Finder reveal, capture presets.
- ✅ **Phase 3 — Overlays & Hotkeys**: Hardware-accelerated webcam PiP overlay, mouse click highlights, global Carbon hotkeys (`⌘⇧R` / `⌘⇧S`), menu bar status item controller.
- ✅ **Phase 4 — Polish & Flexibility**: Non-destructive pause/resume with PTS presentation timestamp rewriting, keystroke overlay with modifier key visualization, animated GIF exporter with palette quantization, App Settings panel, library management.
- ✅ **Phase 5 — Hardening & Universal Mac Support**: Native Intel (`x86_64`) support alongside Apple Silicon, self-healing local code signing for persistent macOS TCC permissions, mid-stream interruption detection with auto-salvage of partial recordings, artifact cleanup wizard, sensitive password field masking, CycloneDX SBOM supply chain attestation.

---

## Phase 6: Facecam Studio & Unified PiP Engine

### 6.1 Quick-Toggle Header & Smart Profiles *(Shipped in v0.3.5)*
- **Header Facecam Toggle (`person.crop.square` / `person.crop.square.fill`)**: One-click quick activation right in the window header next to History (`film.stack`).
- **Intelligent Profile Resolution**:
  - Automatically loads and applies the profile designated with `useForFacecam`.
  - If only one profile has PIP enabled, it is automatically marked as the Facecam profile.
  - Creating the first profile with PIP auto-checks `"Use as default Facecam profile"`.
  - If no profile has PIP configured, turns on the camera in the current context, smoothly scrolls to **Overlays**, and highlights the controls with an accent border and badge.
- **Preset Serialization**: Full persistence of camera device, corner, size, background mode, mouse clicks, and keystrokes with backwards-compatible JSON decoding.

### 6.2 Geometric Shapes Engine (Beyond the Circle)
- **Shape Catalog**:
  - **Classic Circle**: 1:1 round badge.
  - **Squircle / Rounded Rectangle**: Apple Human Interface superellipse with adjustable corner radius (`8px` to `48px`).
  - **Widescreen Rectangle (16:9 / 4:3)**: Standard broadcast sensor aspect ratio to capture hand gestures and desk items.
  - **Stadium / Pill**: Compact horizontal or vertical pill.
  - **Architectural Arch / Vault**: Curved top with flat flush bottom designed to anchor cleanly into screen corners.
  - **Geometric Polygons**: Hexagons and octagons with 4x MSAA edge antialiasing.
- **Technical Architecture**: `CAShapeLayer` clipping path and Metal fragment shader stencil masks with aspect ratio locking (`1:1`, `4:3`, `16:9`, `Freeform`).

### 6.3 Border & Stroke Engine ("Solid Color" & Standard Workflow)
- **Configurable Stroke Width**: Continuous slider from `0 px` (borderless) to `20 px` with numeric stepper.
- **"Solid Color" Standard System Workflow**:
  - Standard macOS `NSColorPanel` integration.
  - Color Wheel (HSV) with luminance/saturation controls.
  - RGB Sliders (0–255 / 0–100%) and direct Hex input (`#RRGGBB` / `#RRGGBBAA`).
  - System color swatches & recent favorites.
  - Screen Loupe / Eyedropper to sample any pixel from slides, code, or brand assets.
- **Contrast Shadow**: Optional subtle drop shadow (`blur: 8px, opacity: 0.35, y: -2px`) for readability across dark and light content.

### 6.4 Blurred Custom Backdrop Engine
- **Concept**: Allows users to import a high-res photo of their real office, a stylish interior, or branded graphic, and applies GPU Gaussian blur (`CIGaussianBlur`) *behind* the Neural Engine person silhouette cutout.
- **Why it matters**: Solves the messy room problem naturally without generic, flat-looking virtual backgrounds.
- **Blur Radii**: Subtle (`10px`), Balanced (`22px`), Strong (`40px`), or Custom slider (`2–60px`).

### 6.5 Modular Branding & Watermark Engine (Independent Logo vs. PiP-Anchored Frame)
- **Architectural Decoupling**: Strict segregation between the Branding Layer and the PiP Layer, tied together through a unified configuration UX in Overlays.
- **Mode 1: Independent Screen Watermark (No PiP Required)**:
  - Place a corporate logo, channel badge, or copyright watermark in any screen corner (`Top Left`, `Top Right`, `Bottom Left`, `Bottom Right`) with adjustable padding.
  - Continuous scaling (`24px` icon to `320px` banner) and opacity slider (`10%` to `100%`).
  - Operates completely independently of whether the camera is active.
- **Mode 2: PiP-Anchored Broadcaster Mode**:
  - **Backing Plate**: Sits behind the person cutout silhouette.
  - **Framing Bezel**: Sits over the webcam frame with a transparent inner cutout.
  - Synchronously moves, snaps, and scales whenever the Facecam PiP is repositioned.
- **Web-Standard Formats**: PNG-24 with alpha, WebP with alpha, and vector SVG rendered at screen-native Retina DPI.

### 6.6 Unified PiP Engine: MP4 Media Playback Mode
- **Clarified Terminology**:
  - **Picture-in-Picture (PiP)**: The universal floating window engine (`WebcamPanel` / Metal / `SCContentFilter` exception layer).
  - **Facecam**: The fast-load live camera presenter mode.
  - **Video PiP**: File-based playback mode allowing users to load and play an `.mp4` or `.mov` inside the exact same floating overlay container.
- **Features**: Pre-recorded talking head demos, reactions, looping animated logo mascots, transport controls (play, pause, scrub bar, loop), audio mix routing (mix to recording, monitor, or mute), and inherited geometric styling.

---

## Phase 7: Discoverable & Rebindable Keyboard Shortcuts

### Objective
Provide universal keyboard control across all core recording, overlay, and navigation actions, with zero-permission global operation and complete user rebindability.

```
+--------------------------------------------------------------------------+
|  KEYBOARD SHORTCUTS REFERENCE                                       [⌘/] |
+--------------------------------------------------------------------------+
|  GLOBAL SYSTEM HOTKEYS (Active even when recorder is hidden/in background) |
|   • Start / Stop Recording        ⌘⇧R / ⌘⇧S                              |
|   • Pause / Resume Recording      ⌥Space                                 |
|   • Toggle PiP Overlay (Facecam)  ⌃⌥P                                    |
|   • Toggle Mouse Click Highlights ⌃⌥M                                    |
|   • Toggle Keystroke Overlay      ⌃⌥K                                    |
|                                                                          |
|  IN-APP SHORTCUTS                                                        |
|   • Browse Recordings Library     ⌘L                                     |
|   • App Settings / Preferences    ⌘,                                     |
|   • Refresh Displays & Devices    ⌘R                                     |
|   • Cycle Presets                 ⌘1 … ⌘9                                |
+--------------------------------------------------------------------------+
```

### 7.1 Core Actions & Default Palette
- **Start Recording**: `⌘⇧R` (Global Carbon hotkey, no permissions required).
- **Stop Recording**: `⌘⇧S` (Global Carbon hotkey).
- **Pause / Resume Recording**: `⌥Space` (or `⌘⌥Space`).
- **Toggle PiP Overlay (Facecam)**: `⌃⌥P` (Control-Option-P).
- **Toggle Mouse Click Highlights ("Show Clicks")**: `⌃⌥M`.
- **Toggle Keystroke Overlay**: `⌃⌥K`.
- **Open Recordings Library**: `⌘L`.
- **Cycle Presets**: `⌘1` through `⌘9`.

### 7.2 Discoverability Architecture
- **In-App Tooltip Badges**: Every primary button and toggle displays its shortcut badge in its hover tooltip (e.g., `"Start Recording (⌘⇧R)"`, `"Toggle Facecam PiP (⌃⌥P)"`).
- **Native macOS Menu Bar Glyphs**: Standard `NSMenuItem.keyEquivalent` integration displaying macOS symbols (`⌘`, `⇧`, `⌥`, `⌃`) in the system status bar menu.
- **Searchable Shortcuts Cheat Sheet (`⌘/` or `?`)**: Interactive modal dialog listing all global and in-app shortcuts with quick search.

### 7.3 User-Rebindable Hotkeys Engine
- **In-App Key Recorder**: A dedicated preference panel in App Settings where users can click to record custom key combinations.
- **Carbon Dynamic Re-registration**: Instantly re-registers hotkeys via `RegisterEventHotKey` without requiring an application restart.
- **Conflict Detection**: Validates against macOS system-reserved shortcuts (e.g. Spotlight, Mission Control) and flags key collisions.
- **Preset Binding**: Optional ability to associate specific hotkeys with distinct capture profiles.

---

## Phase 8: Post-Capture Trim & Visual Polish

### 8.1 In-App Trim Before Save
- **Problem**: Screen recordings almost always have dead air at the beginning (before switching apps) and end (switching back to stop the recording).
- **Solution**: A lightweight post-capture review modal displayed immediately after clicking Stop:
  - **Scrubbable Thumbnail Timeline**: Visual filmstrip generated asynchronously via `AVAssetImageGenerator`.
  - **Draggable In / Out Handles**: Precise start and end trim markers with frame-accurate stepping (`←` / `→` arrow keys).
  - **Lossless / Passthrough Trimming**: Uses `AVAssetExportSession` with `AVAssetExportPresetPassthrough` to perform sub-second trims without re-encoding, preserving pristine video quality and metadata.
  - **Actions**: "Save Trimmed", "Save Original", "Discard", or "Open in QuickTime".

### 8.2 Cursor Click Ripple Style Customization
- **Expanded Visual Styles**:
  - **Concentric Radar Wave**: Expanding double rings that dissipate outward.
  - **Soft Glow Pulse**: Expanding diffuse radial glow with smooth alpha falloff.
  - **High-Contrast Ring**: Crisp geometric ring for technical tutorials.
  - **Burst Particles**: Subtle mini-particle burst for playful/creator content.
- **Customization Controls**:
  - Color Picker (matches "Solid Color" engine or theme accent).
  - Radius / Size Slider (`20px` to `80px`).
  - Duration Slider (`0.2s` to `0.8s`).
  - Left-Click vs. Right-Click differentiation (distinct colors).
  - Optional subtle click sound effect or haptic feedback.

---

## Phase 9: Intelligent Capture (Auto-Zoom & Live Transcription)

### 9.1 Dynamic Auto-Zoom on Cursor (Screen Studio Style)
- **Concept**: Dynamically magnifies the active area of interest when the presenter clicks, types, or navigates menus, keeping viewers focused without manual post-production keyframing.
- **Algorithm & Motion Physics**:
  - **Interest Point Detection**: Tracks mouse clicks, text input events, and cursor dwell time to calculate focal centroids.
  - **Spring Physics Interpolation**: Uses critically damped spring physics (`response: 0.6s, damping: 0.82`) for buttery smooth camera pans and zooms.
  - **Metal Viewport Cropping**: Renders dynamic viewport transformations in real-time or records metadata sidecar coordinates for non-destructive post-recording pan/zoom rendering.
  - **Configurability**: Zoom Depth (`1.25x`, `1.5x`, `2.0x`), Smoothness slider, and manual override shortcut (`⌘+` / `⌘-` to zoom focal area on demand).

### 9.2 Live Captions & Transcription via Apple Speech Framework
- **Zero-Egress Posture**: Leverages Apple's native on-device `SFSpeechRecognizer` (macOS Speech framework). 100% private, zero network egress, fully functional offline.
- **Real-Time Visual Captions**:
  - Floating, modern subtitle badge rendered over the screen capture.
  - Word-level highlighting (karaoke style) synchronized with speech cadence.
  - Customizable typography (font, size, background pill color, text color).
- **Subtitle Export Formats**:
  - Generates synchronized `.srt` and `.vtt` sidecar subtitle files alongside the recorded `.mp4`.
  - Optional burned-in hard subtitles directly in the video track.

---

## Phase 10: Developer & Distribution Ecosystem

### 10.1 Notarized Signed Releases on GitHub Releases
- **Automated Notarization Pipeline**:
  - CI workflow utilizing Apple's `xcrun notarytool` with App Store Connect API keys.
  - Automated `stapler` stapling to the `.app` bundle and DMG installer.
  - Gatekeeper-compliant distribution removing macOS quarantine warnings (`"Apple could not verify this app"`).
- **Release Automation**:
  - Automated GitHub Releases packaging upon semantic version tags (`v0.4.0`, etc.).
  - Checksums (SHA-256) and embedded CycloneDX SBOM (`bom.json`) for supply chain verification.

### 10.2 Full Xcode Project Alongside SwiftPM
- **Dual Development Ergonomics**:
  - Provide an official `.xcodeproj` generated cleanly alongside the root `Package.swift`.
  - Enables Xcode-native visual debugging, SwiftUI Canvas Previews, Metal frame capture (`MTLFrameCaptureManager`), Instruments profiling, and Apple Developer signing configuration.
  - Maintained via a clean generation script (`Scripts/generate-xcodeproj.sh` using SwiftPM / XcodeGen) to prevent configuration drift.

---

## Horizon: Stretch Goals *(Nice-to-Have)*

- **User-Defined Custom Cam Window Shapes**:
  - Upload arbitrary alpha stencil masks (PNG/WebP) or vector paths (`.svg`) to create comic speech bubbles, game HUDs, or organic brushstroke cam windows.
  - Automated edge outline dilation stroke using the "Solid Color" engine.
- **Standalone Presenter Mode**:
  - Float the Facecam overlay freely across any display during live video calls (Zoom, Google Meet, Microsoft Teams, Slack Huddles) without recording active.
- **Dual-Track ISO MP4 Recording**:
  - Simultaneously record `Screen_Capture.mp4` and `Facecam_Isolated.mp4` with shared timecode for multi-cam NLE editing in Final Cut Pro or Premiere.
- **Native Apple Silicon Center Stage & Studio Light**:
  - Direct UI toggles for AVFoundation `isCenterStageActive` and `isStudioLightActive`.
- **Lower-Third Presenter Name Badge**:
  - Attachable title badge displaying presenter name, role, and social handles.

---

## Milestone & Release Schedule

| Phase | Milestone | Target Version | Scope & Deliverables | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | Core Capture & Audio | v0.1.0 | Screen/window capture, mic + system audio, codecs, custom resolution | ✅ Shipped |
| **Phase 2** | Region & Persistence | v0.1.5 | Region drag-select, level meters, presets, library | ✅ Shipped |
| **Phase 3** | Overlays & Menus | v0.2.0 | Webcam PiP, mouse clicks, global hotkeys, menu bar status | ✅ Shipped |
| **Phase 4** | Pause & Export | v0.2.5 | Non-destructive pause/resume, keystrokes, GIF export, settings | ✅ Shipped |
| **Phase 5** | Hardening & Universal | v0.3.0 | Intel support, stable signing, auto-salvage, artifact cleanup, SBOM | ✅ Shipped |
| **Phase 6** | Facecam Studio & PiP | v0.4.0 – v0.5.5 | Header toggle (shipped v0.3.5), geometric shapes, "Solid Color" outline, blurred backdrop, modular branding, MP4 Video PiP | 🚀 In Progress |
| **Phase 7** | Rebindable Hotkeys | v0.6.0 | Rebindable hotkey engine, `⌘/` cheat sheet, tooltip badges, menu bar glyphs | 🟡 Planned |
| **Phase 8** | Post-Capture Trim | v0.6.5 | In-app trim before save (thumbnail timeline), click ripple styles | 🟡 Planned |
| **Phase 9** | Intelligent Capture | v0.7.0 | Screen Studio-style auto-zoom, on-device live speech captions (`SFSpeechRecognizer`) | 🟡 Planned |
| **Phase 10** | Distribution & IDE | v0.7.5 | Notarized GitHub releases (`notarytool`), full `.xcodeproj` generator | 🟡 Planned |
| **Horizon** | Stretch Goals | v0.8.0+ | Custom SVG shape stencils, standalone meeting mode, dual-track ISO recording | 🔮 Nice-to-Have |

---

Want a feature on this list to move from planned to shipped? Open an issue or a PR.
