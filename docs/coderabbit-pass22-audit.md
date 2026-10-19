# CodeRabbit Review — Pass 22 Audit

**Base Branch**: `origin/main`  
**Review Target**: Local `main` (`v0.4.0` Minor Release: macOS "Open With" Integration, Lossless Trimmer External Media Routing, Dynamic Zero-Ghost Recents History, System File Menu Commands, and Phase 12 Finalization)  
**Date**: October 19, 2026  
**Result**: **CLEAN (0 New Findings)**

---

## Review Output

```
────────────────────────────────────────
CodeRabbit Review

Diff      : tracked changes
Compare   : main → origin/main (local main differs, using origin/main)
Directory : mac-screen-record
────────────────────────────────────────

Review complete
Review completed
No new findings ✔

29 files reviewed:
  - README.md
  - Resources/Info.plist
  - Scripts/build-app.sh
  - Scripts/generate-sbom.py
  - Sources/CaptureCore/CaptureSession.swift
  - Sources/EncoderKit/VideoEncoder.swift
  - Sources/MacScreenRecord/App.swift
  - Sources/RecorderUI/AppSettings.swift
  - Sources/RecorderUI/GlobalHotkeys.swift
  - Sources/RecorderUI/KeystrokeOverlay.swift
  - Sources/RecorderUI/MainView.swift
  - Sources/RecorderUI/MenuBarController.swift
  - Sources/RecorderUI/RecentRecordingsStore.swift
  - Sources/RecorderUI/RecordingViewModel.swift
  - Sources/RecorderUI/RecordingsLibrary.swift
  - Sources/RecorderUI/RecordingsListView.swift
  - Sources/RecorderUI/SettingsView.swift
  - Sources/RecorderUI/VideoTrimModalView.swift
  - Tests/MacScreenRecordTests/RecentRecordingsAndOpenWithTests.swift
  - Tests/MacScreenRecordTests/TestHarness.swift
  - docs/RELEASE_NOTES.md
  - docs/ROADMAP.md
  ... and companion files
────────────────────────────────────────
```

---

## Pass 22 Findings & Resolutions

In Pass 22, CodeRabbit analyzed the full cumulative diff between `main` and `origin/main` and surfaced 4 minor findings, all of which were resolved in commit `a5db53f`:

1. **`Resources/Info.plist:32-37` (LSItemContentTypes scoping)**:
   - **Finding**: `public.movie` is an overly broad parent type encompassing `.avi`, `.mkv`, `.3gp`, etc., which are rejected by `LosslessTrimmer.isSupported`.
   - **Resolution**: Replaced `public.movie` with `com.apple.m4v-video`, aligning declared document types precisely with the `.mp4`, `.mov`, and `.m4v` lossless trimming engine contract.
   - **UX Improvement**: Added user-facing error banner presentation (`status = .error(...)`) and window activation in `openVideoForTrimming` so dropped or selected invalid files communicate clear feedback rather than failing silently.

2. **`Sources/MacScreenRecord/App.swift:29-45` (Recents Store Observation)**:
   - **Finding**: SwiftUI `CommandGroup` observed `vm`, but `RecentRecordingsStore` was an independent `ObservableObject`. Operations like "Clear Menu" or external file removals would not immediately trigger menu item re-renders without a `vm` property change.
   - **Resolution**: Added `recentsCancellable` in `RecordingViewModel.init` forwarding `recentsStore.objectWillChange` to `self.objectWillChange.send()`, guaranteeing synchronous reactive re-renders across all menus.

3. **`Scripts/generate-sbom.py:152` (CLI Fallback Version Parity)**:
   - **Finding**: Line 152 in `__main__` retained a fallback default to `0.3.0` if `sys.argv[3]` was not supplied.
   - **Resolution**: Updated the fallback default to `0.4.0` in both function signature and `__main__` CLI invocation.

4. **`docs/ROADMAP.md:57` (Historical Unit Test Count Accuracy)**:
   - **Finding**: Line 57 described Phase 9 as having 31 tests across 7 suites, which did not distinguish between the shipped v0.3.0 milestone and the expanded v0.4.0 suite.
   - **Resolution**: Updated description to `23 deterministic unit tests across 6 test suites at v0.3.0 (38 across 8 as of v0.4.0)`.

5. **`Sources/RecorderUI/RecordingViewModel.swift:1137` (Log Privacy & Sanitization)**:
   - **Finding**: `log.error` in `openVideoForTrimming` interpolated `standardized.path` with `privacy: .public`, which could record the user's home folder path (`/Users/<username>/...`) in unified logging.
   - **Resolution**: Changed to `standardized.lastPathComponent, privacy: .public`, matching all other log statements and adhering strictly to the local privacy invariant.

6. **UI Discoverability & Tooltip Response Enhancement**:
   - Replaced bare, borderless header icons with `.bordered` native button components featuring enlarged SF Symbols (`14pt .medium`) alongside explicit text labels ("Facecam", "Library", "Refresh").
   - Registered `NSInitialToolTipDelay = 150` in `AppDelegate` and `MainView.init` to eliminate sluggish hover latency and render help tooltips nearly instantaneously (150ms).
   - Added rotation animation feedback to the Refresh button.

---

## Verification & Parity Audit

- **Unit Test Suite**: All 38 unit tests pass cleanly across 8 test suites (`swift run MacScreenRecordTests`).
- **Privacy & Claims Audit**: `python3 Scripts/audit-claims.py` passed with 0 violations across all 6 gates:
  - Version parity (`v0.4.0` across `Info.plist`, `RELEASE_NOTES.md`, `ROADMAP.md`, `generate-sbom.py`, `bom.json`).
  - Zero-egress network framework scanner (0 forbidden symbols across Swift, C, and Objective-C sources).
  - TCC permission table justifications in `NOTICE.md`.
  - Entitlements audit and Carbon hotkey handler lifecycle.
  - CycloneDX 1.5 JSON SBOM schema validation.
- **Release Packaging**: `bash Scripts/build-app.sh release` produced signed `.app` bundle with embedded CycloneDX SBOM and verified zero-egress properties.
- **CodeRabbit Final Review**: **CLEAN (0 findings)** across all 30 modified/added files against `origin/main`.
