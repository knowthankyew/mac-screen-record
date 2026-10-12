Notice: Detected antigravity environment. Use `coderabbit review --agent` for structured agent-friendly output.
╔═══════════════════════════════════════════╗
║                                           ║
║   New update available! 0.8.2 -> 0.9.0    ║
║          Run: coderabbit update           ║
║                                           ║
╚═══════════════════════════════════════════╝

Connecting to CodeRabbit... 1s elapsed
Preparing review... 3s elapsed
────────────────────────────────────────
CodeRabbit Review

Diff      : tracked changes
Compare   : main → main
Directory : mac-screen-record
────────────────────────────────────────

(\(\
(• .•)  I've git the power!

Summarizing changes... 4s elapsed
Summarizing changes... 1m 01s elapsed - still working
Writing review comments... 1m 19s elapsed - still working

────────────────────────────────────────────────────────────────────────
  minor [Stability & Availability]
  → Sources/RecorderUI/AppSettings.swift:62

  The init creates the output folder with try?, so a failure is silent.

  createDirectory can fail, for example when the stored folder is
  read-only or on an unmounted volume. The recorder then writes into a
  directory that does not exist. This only applies when
  isLocalNonUbiquitous passed using the parent directory check on line 67.
  If creation fails, fall back to fallback and create that folder instead.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → Sources/RecorderUI/Presets.swift:229-234

  update(_:) can leave two presets marked useForFacecam.

  update replaces the preset as given. If the updated preset has
  useForFacecam = true, any earlier designation is not cleared.
  normalizeFacecamProfiles only handles the case where exactly one preset
  has PIP. Two presets with the flag set are never fixed. facecamPreset
  then returns whichever comes first in the array. The menu at
  PresetsBar.swift Lines 84-88 shows two checkmarks. Enforce a single
  designation in update the same way add does.


  Proposed fix

       public func update(_ preset: Preset) {
           if let i = presets.firstIndex(where: { $0.id == preset.id }) {
               presets[i] = preset
  +            if preset.webcamEnabled && preset.useForFacecam {
  +                for j in presets.indices where j != i { presets[j].useForFacecam = false }
  +            }
               normalizeFacecamProfiles()


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → Sources/RecorderUI/WebcamOverlay.swift:111-121

  Request camera access before you start the session when status is
  .notDetermined.

  The default branch also covers .notDetermined. In that state the code
  starts the session without an explicit `AVCaptureDevice.requestAccess(for:
  .video)` call. The OS prompt then appears in the middle of the flow, and
  the panel stays black until the user responds. If the user denies access,
  the panel stays visible with no frames and no error. Call requestAccess
  first, and show the panel only after access is granted.


────────────────────────────────────────────────────────────────────────
  trivial [Performance & Scalability]
  → Sources/RecorderUI/WebcamVideoProcessor.swift:237-251

  Cache the fallback backdrop for .customImage.

  While the custom image loads, or after the load fails, line 251 rebuilds a
  warm studio gradient on every frame. If the load fails, this repeats for
  the entire session, and the user sees no error. Reuse the cached preset
  image, or cache this fallback image.


────────────────────────────────────────────────────────────────────────
  trivial [Performance & Scalability]
  → Sources/RecorderUI/WebcamMetalView.swift:80-85

  Bound in-flight frames before you acquire currentDrawable.

  draw(in:) reads view.currentDrawable on the main thread. When no
  drawable is free, this call can block for up to one second. The method
  also commits command buffers without any in-flight limit. Under sustained
  30–60fps webcam input, the main thread can stall. Add a
  DispatchSemaphore(value: 3) and signal it in
  commandBuffer.addCompletedHandler. If the semaphore wait times out, skip
  the frame.


────────────────────────────────────────────────────────────────────────
  minor [Stability & Availability]
  → Sources/RecorderUI/PermissionsBanner.swift:59-66

  Do not terminate the app when the relaunch fails.

  try? task.run() ignores any error from the relaunch. NSApp.terminate
  then runs in every case. If /usr/bin/open fails to launch, the app quits
  and does not restart. Call NSApp.terminate(nil) only after task.run()
  succeeds. Also replace the deprecated launchPath with executableURL.


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → Sources/RecorderUI/MenuBarController.swift:55

  Remove the redundant menu rebuild.

  The menu delegate already repopulates the menu in menuNeedsUpdate. The
  extra buildMenu() call on every status change is unnecessary.


────────────────────────────────────────────────────────────────────────
  major [Security & Privacy] | 🛡️ Analyzed with Security Review
  → Scripts/audit-claims.py:71-80

  Security: Security Misconfiguration (CWE-693)
  Reachability: Internal · Exploitability: Difficult

  Block BSD socket use in the zero-egress audit.

  Scripts/audit-claims.py does not match socket(...) or sys/socket.h.
  A Swift file can therefore import Darwin and create a BSD socket without
  triggering the audit. Add checks for BSD socket APIs and headers, plus an
  isolated fixture test that asserts the audit rejects them.

Writing review comments... 3m 44s elapsed - still working - 8 findings so far

────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → Sources/RecorderUI/RecordingsLibrary.swift:166-170

  Reject invalid rename input with an error instead of returning silently.

  rename returns without action for empty names, /, \, ., and ...
  commitRename in RecordingsListView.swift then closes the rename field,
  and the user gets no feedback. A name that starts with . passes
  validation. The file then becomes hidden, and reload() skips it
  (.skipsHiddenFiles), so it disappears from the list. Throw a
  LocalizedError for these cases and reject a leading .. The existing
  alert in RecordingsListView then shows the reason.


────────────────────────────────────────────────────────────────────────
  trivial [Functional Correctness]
  → Sources/RecorderUI/MainView.swift:76-79

  Mark interruptions with an explicit status, not by matching message text.

  isInterruption is true for any error that contains "interrupted". A
  failed start can produce such text: startRecording puts SCK or NSError
  text into "Recording failed: \(detail)". A failed start does not update
  lastRecordingURL. It still points to the previous successful recording.
  The banner then shows "Delete Artifacts…", and confirming deletes that
  good recording. Add a dedicated status, for example `case
  interrupted(message: String, partialURL: URL?)`, and set it only in
  handleRecordingFailure. Show the deletion action only when partialURL
  is non-nil.

Writing review comments... 4m 47s elapsed - still working - 10 findings so far

────────────────────────────────────────
Review complete
Review completed
10 findings ✔

Major    1
Minor    5
Trivial  4

48 files reviewed:
  - .coderabbit.yaml
  - .gitignore
  - LICENSE
  - NOTICE.md
  - Package.swift
  - README.md
  - RELEASE_NOTES.md
  - ROADMAP.md
  - Resources/Info.plist
  - Resources/MacScreenRecord.entitlements
  ... and 38 more files
────────────────────────────────────────

Print all AI prompts: coderabbit review --show-prompts
