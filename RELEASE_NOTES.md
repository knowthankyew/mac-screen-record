# Mac Screen Record Release Notes

> *Note: Mac Screen Record is a hard fork and continuation of Free Mac Screen Recorder by penguinpecker. All upstream releases (v0.1.0 – v0.3.0) and git commit history are preserved in full under the MIT License.*

## Mac Screen Record 0.3.0

**Release:** `v0.3.0` (Build `3`)  
**Date:** October 1, 2026  
**Architectures:** Apple Silicon (`arm64`), Intel (`x86_64`)  
**Minimum OS:** macOS 13.0 (Ventura) or later  

---

### What's New in 0.3.0

#### Real-Time Neural Engine Webcam PIP Effects

* **Apple Neural Engine Person Segmentation:**  
  Integrated Apple’s native `VNGeneratePersonSegmentationRequest` (Vision framework) for real-time person segmentation running on the Apple Neural Engine (ANE) and GPU. Completely on-device and zero-egress.
* **Hardware-Accelerated Metal Rendering:**  
  Replaced passive preview layer with `WebcamMetalView` (`MTKView` + Core Image render destinations) for zero-copy rendering and alpha transparency.
* **Background Blur:**  
  Added real-time background blurring with three intensity presets: Subtle (10px), Balanced (20px), and Strong (35px).
* **Virtual Backdrops:**  
  Added 5 built-in procedurally generated backdrops: Warm Studio, Cool Slate, Modern Minimal, Sunset, and Green Screen (chroma key `#00FF00`).
* **Custom Background Image Replacement:**  
  Users can select any photo or graphic from disk (`.png`, `.jpg`, `.heic`, etc.) via native macOS open panel with real-time aspect-fill cropping and GPU caching.
* **Cutout (Silhouette) Mode:**  
  Loom-style background removal where only the presenter's silhouette floats freely on screen.
* **Toggleable Border Ring:**  
  Customizable border ring styling with support for borderless floating cutouts.

---

## Free Mac Screen Recorder 0.2.0 Release Notes

**Release:** `v0.2.0` (Build `2`)  
**Date:** October 1, 2026  
**Architectures:** Apple Silicon (`arm64`), Intel (`x86_64`)  
**Minimum OS:** macOS 13.0 (Ventura) or later  

---

## Executive Summary (0.2.0)

Free Mac Screen Recorder `v0.2.0` represents a major milestone in platform support, recording reliability, consumer privacy governance, and desktop UX polish. This release introduces native Intel (`x86_64`) support, aggressive mid-stream failure alerting with partial video auto-salvage, persistent local code signing for macOS TCC retention, automated recording artifacts cleanup, sensitive password masking in keystroke overlays, and formal CycloneDX SBOM supply chain attestation.

---

## What's New in 0.2.0

### 1. Platform & Architecture

* **Native Intel (`x86_64`) Support:**  
  Build pipelines (`Scripts/build-app.sh`) now dynamically detect host CPU architecture (`$(uname -m)`) to compile native Mach-O thin binaries for both Intel and Apple Silicon Macs.
* **Persistent Local Code Signing:**  
  Added `Scripts/setup-stable-signing.sh` to generate a dedicated self-signed code-signing certificate (`Free Mac Screen Recorder Local`) in the user's login keychain. This establishes a stable designated requirement so macOS TCC preserves Screen Recording, Microphone, and Camera permissions across future rebuilds and updates without prompting or revoking access.

### 2. Recording Reliability & Fault Tolerance

* **Mid-Stream Failure Detection & Multi-Sensory Alerting:**  
  Wired asynchronous error pipelines from `VideoEncoder` and `SCStreamDelegate` through to `RecordingViewModel` and `MenuBarController`. If video or audio capture fails mid-session, the app triggers immediate, high-priority notifications:
  * Multi-chime system alert tone (`NSSound.beep()`)
  * Continuous Dock icon attention bounce (`NSApp.requestUserAttention(.criticalRequest)`)
  * Immediate app activation and window un-minimization
  * Menu bar status item error badge (`⚠️`) with failure reason tooltip
* **Auto-Salvage of Partial Recordings:**  
  When an interruption occurs, the recorder automatically finalizes and flushes any partial frames captured up to the failure point, ensuring long recording sessions are not lost.
* **Movie Fragmentation (`movieFragmentInterval = 10s`):**  
  Enabled 10-second movie fragment writing in `VideoEncoder` for MP4 and MOV containers. Long recordings are incrementally written to disk rather than buffered in RAM, preventing memory exhaustion and safeguarding partial files against sudden crashes.
* **Recording Artifacts Cleanup:**  
  Added a "Delete Artifacts…" modal sheet on both failed and completed recordings. Includes a safe, default-on **"Move files to Trash"** option, with the ability for users to explicitly choose permanent deletion.

### 3. Privacy, Sensitive Input & Supply Chain Governance

* **Sensitive Password Masking:**  
  The keystroke overlay controller (`KeystrokeOverlayController`) now queries `IsSecureEventInputEnabled()`. When typing in password fields, terminal sudo prompts, or credential managers, keystroke visualization is instantly suppressed to prevent sensitive credentials from appearing in recorded video.
* **Zero-Egress Governance in Settings:**  
  Added a new **"Privacy & Data Governance"** inspection panel in `SettingsView`, powered by a runtime `PrivacyClaimsProvider` that verifies the app's zero-egress, local-only, and zero-telemetry posture.
* **CycloneDX SBOM & Supply Chain Notices:**  
  Integrated `Scripts/generate-sbom.py` into the build script to generate a standardized CycloneDX v1.5 JSON Software Bill of Materials (`bom.json`) embedded directly into `Contents/Resources/bom.json`, alongside a comprehensive third-party and legal attribution notice (`NOTICE.md`).

### 4. UI & Workflow Refinements

* **Instant Presets UI Synchronization:**  
  Resolved an issue where newly created or deleted presets would not immediately reflect in the presets dropdown menu by directly observing `PresetsStore` in `PresetsBar` and forwarding object changes.
* **Startup Error De-duplication:**  
  Eliminated false-alarm "Recording Interrupted" error banners on startup. Missing permissions are cleanly delegated to `PermissionsBanner` without firing redundant red banners.
* **Dynamic Permission Re-enumeration:**  
  Subscribed `RecordingViewModel` to permission state changes. Granting Screen Recording permission in macOS System Settings now automatically enumerates displays and transitions the app to `.ready` without requiring an app relaunch.
* **Differentiated Banner Hierarchy:**  
  Stream failures are highlighted in high-contrast red with artifact cleanup controls, while non-fatal notices (such as camera disconnects or unselected sources) display in calm warning amber.
* **Dedicated Error Dismissal:**  
  Added a `dismissError()` action to cleanly reset error states back to `.ready` or `.idle`.

---

## Upgrade & Verification Instructions

### 1. Build and Run
```bash
# 1. Setup persistent signing identity (one-time setup)
./Scripts/setup-stable-signing.sh

# 2. Build release bundle
./Scripts/build-app.sh release

# 3. Launch
open "dist/Free Mac Screen Recorder.app"
```

### 2. Verify Version
Check the app bundle metadata:
```bash
defaults read "$PWD/dist/Free Mac Screen Recorder.app/Contents/Info.plist" CFBundleShortVersionString
# Output: 0.3.0

defaults read "$PWD/dist/Free Mac Screen Recorder.app/Contents/Info.plist" CFBundleVersion
# Output: 3
```
