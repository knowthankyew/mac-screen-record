# Mac Screen Record — Interactive UI QA & Verification Checklist

> **Purpose**: Step-by-step hands-on testing guide for evaluating the native macOS UI, presenter studio, lossless trimming, and cryptographic verification in **Mac Screen Record (`v0.3.0`)**. Feel free to wander off-script at any point!

---

## 🚀 Quick Launch

Launch the freshly built and signed release bundle:
```bash
open "/Users/cl0rkster/Dev/mac-screen-record/dist/Mac Screen Record.app"
```
*(Or run in Xcode / terminal via `swift run MacScreenRecord`)*

---

## 📋 Section 1: Launch, Window Shell & Permissions

- [ ] **1.1 Launch & Dock/Menu Bar State**
  - Launch the app from `dist/Mac Screen Record.app`.
  - Verify the native macOS window appears with title **"Mac Screen Record"** and modern dark-translucent glass styling.
  - Verify a companion recording icon appears in the macOS menu bar status item tray.
- [ ] **1.2 TCC Permissions Prompt Handling**
  - On first launch, verify standard macOS system prompts appear for:
    - **Screen Recording** (`ScreenCaptureKit`)
    - **Microphone** (`AVCaptureDevice`)
    - **Camera** (`AVCaptureDevice` for Facecam PiP)
    - **Accessibility** (for global hotkeys and click highlight coordinates)
  - Verify the app does not crash or freeze if any permission is pending.

---

## 🎥 Section 2: Recording Controls, Presets & Overlays

- [ ] **2.1 Capture Mode Selection**
  - Test switching between **Full Screen**, **Window**, and **Selected Area** capture.
  - For **Selected Area**: drag a selection rectangle on screen, verify dimension badges and handles update smoothly.
- [ ] **2.2 Codec, Resolution & Framerate Selection**
  - Switch format between **H.264 (.mp4)**, **HEVC / H.265 (.mp4)**, and **Apple ProRes 422 (.mov)**.
  - Switch framerate between **30 fps** and **60 fps**.
  - Check the dynamic bitrate estimate readout updates appropriately based on selected codec and resolution.
- [ ] **2.3 Audio Level Monitoring**
  - Select your microphone input. Speak into the mic and verify the green/yellow/red audio level VU meters animate responsively with zero audible feedback loop.
- [ ] **2.4 Cursor Effects & Keystroke Visualizer**
  - Toggle **Mouse Click Highlights** on. Perform several clicks and verify circular ripple animations appear at cursor coordinates.
  - Toggle **Keystroke Overlay** on. Type common key combinations (e.g., `⌘C`, `⇧⌘4`, text characters) and verify floating visual badges render on screen.
- [ ] **2.5 Password Field Masking Invariant (`IsSecureEventInputEnabled`)**
  - Open a password prompt (e.g., macOS Keychain prompt, Safari password field, or terminal `sudo` prompt).
  - Type characters while the keystroke overlay is active.
  - **Verify**: The keystroke overlay immediately and silently suppresses display of keys while secure input is active, preventing credential leakage.

---

## 👤 Section 3: Presenter PiP / Facecam Studio (ANE + Metal)

- [ ] **3.1 Facecam Activation & Framing**
  - Enable **Facecam** in the main toolbar.
  - Verify a floating circular/rounded webcam preview window appears on screen.
  - Drag the window across multiple displays and test resizing handles.
- [ ] **3.2 Apple Neural Engine (ANE) Segmentation & Blur**
  - Turn on **Background Blur**.
  - Adjust the blur radius slider. Verify the person segmentation separates your silhouette from the room background at 60 fps with low CPU utilization (rendered via `MTKView`).
- [ ] **3.3 Procedural Studio Backdrops**
  - Cycle through the 5 procedural Core Image backdrops:
    - *Studio Gradient*
    - *Warm Sunset*
    - *Ocean Breeze*
    - *Cyber Neon*
    - *Minimal Neutral*
  - Verify seamless background replacement with smooth edge alpha matting.
- [ ] **3.4 Custom Background Image & Transparent Silhouette**
  - Test loading a custom local image (`.jpg` or `.png`) as the backdrop.
  - Test the **Cutout Mode** (silhouette only, background transparent).
- [ ] **3.5 Preset Switcher (`useForFacecam`)**
  - Save your Facecam settings as a custom preset.
  - Switch to a different preset and verify camera framing, shape, and backdrop restore instantly.

---

## ⌨️ Section 4: Universal Hyper Hotkeys & Customization

- [ ] **4.1 Default Carbon Hyper Shortcuts**
  - Press `⌃⌥⌘R` (Control + Option + Command + R) from any application.
  - **Verify**: Recording starts immediately without needing to bring Mac Screen Record to the foreground.
  - Press `⌃⌥⌘S` (Control + Option + Command + S).
  - **Verify**: Recording stops immediately, and the finish bar / trimmer appears.
- [ ] **4.2 In-App Hotkey Customization**
  - Open **Settings > Shortcuts**.
  - Click the hotkey recorder button for **Start/Pause** or **Stop**.
  - Press a new custom key combination.
  - **Verify**: The binding persists across app restarts and functions globally.

---

## ✂️ Section 5: Phase 10 Lossless Video Trimming

- [ ] **5.1 In-App Review Before Save (Settings Workflow)**
  - Open **Settings > Defaults**, and enable **"Review and trim before saving"**.
  - Record a short 10-second test video and press Stop.
  - **Verify**: The **Video Trim Modal sheet** opens automatically over the main window.
- [ ] **5.2 Finish Bar Action**
  - With "Review before save" disabled, stop a recording.
  - In the bottom finish bar, click the new **"Trim…"** button (next to *Show in Finder* and *Save*).
  - **Verify**: The modal sheet opens with the newly captured recording preloaded.
- [ ] **5.3 Library Row Action & Context Menu**
  - Open the **Recordings Library** slide-out panel.
  - Hover over any recorded video item in the list:
    - Click the scissors icon button on the row.
    - Alternatively, right-click the row and select **"Trim Video…"**.
  - **Verify**: The trim modal opens for that specific library file.
- [ ] **5.4 Trimming External Video Files**
  - At the bottom of the Recordings Library, click **"Trim Video…"**.
  - Use the native macOS file picker (`NSOpenPanel`) to select any `.mp4`, `.mov`, or `.m4v` from your disk.
  - **Verify**: The video loads cleanly into the trimmer with correct duration and aspect ratio.
- [ ] **5.5 Interactive Timeline, Filmstrip & Scrubbing**
  - Inside the trim modal:
    - Verify the asynchronous filmstrip thumbnail strip loads across the timeline.
    - Drag the **In (Start)** handle inward (e.g., to 00:02.00).
    - Drag the **Out (End)** handle inward (e.g., to 00:07.00).
    - Verify live video frame scrubbing follows handle dragging.
    - Verify timecode readouts update accurately (`MM:SS.SS` format).
    - Press the Play button or Spacebar to preview playback — verify playback loops strictly between the In and Out markers.
- [ ] **5.6 Export Mode: "Save Copy"**
  - Click **"Save Copy"**.
  - Verify a progress indicator appears during export.
  - **Verify**: A new file named `<filename>_trimmed.mp4` is created without re-encoding (instant passthrough export).
  - Verify both the original file and trimmed file appear in the Recordings Library.
- [ ] **5.7 Export Mode: "Replace Original" & Manifest Continuity**
  - Trim an existing library recording and select **"Replace Original"**.
  - Confirm the alert warning about overwriting.
  - **Verify**: The original file is replaced with the trimmed cut.
  - **Verify**: The companion `.evidence.json` cryptographic seal is automatically recalculated with new SHA-256 and SHA-512 hashes.

---

## 🔏 Section 6: Cryptographic Evidence Manifests

- [ ] **6.1 Companion Manifest Generation**
  - Open the output directory (`~/Movies/Mac Screen Record/`).
  - For any recording `recording.mp4`, verify there is a companion `recording.mp4.evidence.json`.
- [ ] **6.2 Manifest Schema & Hashes**
  - Inspect the JSON file:
    ```bash
    cat ~/Movies/Mac\ Screen\ Record/*.evidence.json | head -n 30
    ```
  - Verify schema metadata:
    - `"schemaVersion": "knowthankyew:evidence:v1"`
    - `"sha256"` (64 hex characters)
    - `"sha512"` (128 hex characters)
    - `"fileSizeBytes"` matching actual file size
    - `"recordingMetadata"` detailing codec, resolution, and fps.

---

## 🥾 Section 7: "Off-Script" Exploratory Probing

1. **Simulated Crash & Auto-Salvage Recovery**:
   - Start a recording.
   - Force kill the application from Terminal (`killall -9 "Mac Screen Record"`).
   - Inspect the temporary output file in the salvage location — verify `AVAssetWriter` fragmentation was handled and the file plays cleanly up to the last flushed frame.
2. **Cloud-Sync Egress Guard**:
   - In Settings, attempt to choose an iCloud Drive or Dropbox synced folder as the default save location.
   - **Verify**: The application actively detects ubiquitous cloud storage via `AppSettings.isLocalNonUbiquitous(_:)` and prevents selection, preserving local air-gapped isolation.
3. **Multi-Monitor Display Density Scaling**:
   - Move the window between a Retina display and an external standard DPI display while scrubbing the trimmer or previewing Facecam.
   - Verify layout coordinates, drag handles, and Metal view scale factors adjust cleanly without blurring or offset glitches.
