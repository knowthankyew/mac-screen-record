# CodeRabbit Review — Pass 21 Audit

**Base Branch**: `origin/main`  
**Review Target**: Local `main` (Phase 12: Ephemeral Recording HUD & Dynamic Session Companion + Saved Recording Green Link Visual Callout + Comprehensive Iterative Review Resolutions)  
**Date**: October 19, 2026  
**Result**: **CLEAN (0 Findings)**

---

## Review Summary

```
────────────────────────────────────────
CodeRabbit Review

Diff      : tracked changes
Compare   : main → origin/main (local main differs, using origin/main)
Directory : mac-screen-record
────────────────────────────────────────

Review complete
Review completed
No findings ✔

21 files reviewed:
  - README.md
  - Sources/CaptureCore/CaptureSession.swift
  - Sources/CaptureCore/CaptureSource.swift
  - Sources/EncoderKit/VideoEncoder.swift
  - Sources/MacScreenRecord/App.swift
  - Sources/RecorderUI/AppSettings.swift
  - Sources/RecorderUI/GlobalHotkeys.swift
  - Sources/RecorderUI/KeystrokeOverlay.swift
  - Sources/RecorderUI/MainView.swift
  - Sources/RecorderUI/MenuBarController.swift
  - Sources/RecorderUI/RecordingViewModel.swift
  - Sources/RecorderUI/RecordingsLibrary.swift
  - Sources/RecorderUI/SettingsView.swift
  - Sources/RecorderUI/VideoTrimModalView.swift
  - Tests/MacScreenRecordTests/MenuBarAndSessionCompanionTests.swift
  - Tests/MacScreenRecordTests/TestHarness.swift
  - docs/QA_CHECKLIST.md
  - docs/ROADMAP.md
  - (and companion audit documentation)
────────────────────────────────────────
```

---

## Resolved Findings History

Across Passes 12 through 20, the following items were surfaced by CodeRabbit and completely resolved:

1. **Shared Hard Burn Confirmation Modal**:
   - Extracted `confirmHardBurn() -> Bool` on `RecordingViewModel.swift` presenting an explicit `.critical` `NSAlert` modal before unlinking media.
   - Unified modal confirmation across both the menu bar dropdown Hard Burn action and the `⌃⌥⌘⌫` global hotkey.

2. **Active Capture Session Telemetry**:
   - Exposed immutable `sessionSource`, `sessionGeometry`, `sessionCodec`, `sessionMicrophoneEnabled`, `sessionSystemAudioEnabled`, and `sessionMicrophoneDeviceID` getters on `RecordingViewModel`.
   - Updated `MenuBarController` to read active session parameters instead of UI controls during recording.
   - Extracted `describeTarget(for:)` in `MenuBarController.swift` to synchronize button tooltips and dropdown menu telemetry into a single helper.

3. **CaptureSession Hard Burn Teardown Race Condition**:
   - Reordered `CaptureSession.burn()` so `stream?.stopCapture()` and `micCapture?.stop()` halt sample delivery before `encoder?.cancel()` and reference clearance.

4. **VideoEncoder Finalization Safeguard**:
   - Guarded `VideoEncoder.cancel()` with `guard !self.isFinishing, let writer = self.writer else { return }`, ensuring finalized recordings cannot be deleted if `cancel()` is called after `finish()`.
   - Exposed `writerStatus` property on `VideoEncoder` for observability.

5. **Trim Review Discard Isolation**:
   - Added `onDiscard` callback in `VideoTrimModalView` routed to `vm.discardReviewedRecording(at: target.url)`.
   - Ensured discarding a reviewed recording deletes that specific URL and only resets UI state if that session is still the active finished recording, protecting concurrent new recordings.

6. **Window Minimization State Tracking**:
   - Added `didMinimizeForCapture` flag in `RecordingViewModel` to ensure `restoreWindowIfNeeded()` only runs if the window was actually minimized by capture start.
   - Cleanly reset `didMinimizeForCapture = false` on all exit paths (stop, burn, and failure).
   - Moved `restoreWindowIfNeeded()` to run immediately upon recording completion in `stopRecording()`, preventing delays during library reload.

7. **Unified Active-Session Metadata Reset**:
   - Extracted `resetActiveSessionMetadata()` in `RecordingViewModel` to eliminate duplicate resetting blocks across `stopRecording`, `burnRecording`, and `handleRecordingFailure`.

8. **Roadmap & Claims Parity**:
   - Updated `docs/ROADMAP.md` table and text to accurately describe wall-clock duration formatting (`MM:SS` / `HH:MM:SS`) and PTS pause excision.
   - Updated test suite count claim to 31 tests across 7 suites.

---

## Verification & Automated Test Status

- **Unit Tests**: All 31 unit tests passing across 7 test suites (`swift run MacScreenRecordTests`).
- **Claims Audit**: Claims audit clean (`python3 Scripts/audit-claims.py`).
  - Zero-egress network integrity enforced
  - Carbon global hotkey invariants verified (`⌃⌥⌘R`, `⌃⌥⌘S`, `⌥Space`, `⌃⌥⌘⌫`)
  - SecureEventInput suppression intact
  - CycloneDX SBOM & version parity verified
