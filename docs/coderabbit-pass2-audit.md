Notice: Detected antigravity environment. Use `coderabbit review --agent` for structured agent-friendly output.
╔═══════════════════════════════════════════╗
║                                           ║
║   New update available! 0.8.2 -> 0.9.0    ║
║          Run: coderabbit update           ║
║                                           ║
╚═══════════════════════════════════════════╝

Connecting to CodeRabbit... 1s elapsed
Preparing review... 4s elapsed
────────────────────────────────────────
CodeRabbit Review

Diff      : tracked changes
Compare   : main → main
Directory : mac-screen-record
────────────────────────────────────────

(\(\
(• .•)  Estimate the order of your algorithms. Get a feel for how long things are likely to take before you write code.

Summarizing changes... 5s elapsed
Writing review comments... 55s elapsed
Writing review comments... 1m 01s elapsed - still working

────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/RecordingsListView.swift:140Sources/RecorderUI/RecordingsListView.swift:140-149]8;;

  Allow only one GIF export at a time.

  exportingID holds a single URL. If a user starts a second export, the
  first progress indicator disappears. When the first export finishes, it
  sets exportingID = nil and hides the progress indicator for the second
  export, which is still running. Several large exports can also run at the
  same time. Turn off "Export as GIF" while exportingID != nil, or track a
  set of exporting URLs.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/EncoderKit/GIFExporter.swift:13Sources/EncoderKit/GIFExporter.swift:13-17]8;;

  Validate fps and maxWidth.

  If fps is 0, then 1.0 / Double(options.fps) gives infinity, and the
  frame count stays at 1. A negative fps or maxWidth gives invalid
  values. Clamp both values in init, for example fps = max(1, fps).


────────────────────────────────────────────────────────────────────────
  minor [Data Integrity & Integration]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/RecordingsLibrary.swift:198Sources/RecorderUI/RecordingsLibrary.swift:198-199]8;;

  Do not overwrite an existing GIF without confirmation.

  exportGIF always writes to .gif. If that file already exists,
  GIFExporter replaces it through replaceItemAt. A user's earlier export
  or an unrelated GIF with the same base name is lost without a warning. Use
  the same collision-suffix logic that rename uses.


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/RecordingsLibrary.swift:127Sources/RecorderUI/RecordingsLibrary.swift:127]8;;

  Mark the path interpolation privacy explicitly.

  The url.path value at Line 127 and Line 153 has no privacy specifier.
  OSLog redacts it by default, so the full path, which includes the user's
  home directory, stays hidden. Use lastPathComponent with .public to
  stay consistent with the other log lines and keep the logs useful.


────────────────────────────────────────────────────────────────────────
  major [Performance & Scalability]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/EncoderKit/GIFExporter.swift:47Sources/EncoderKit/GIFExporter.swift:47-49]8;;

  Bound the frame count to prevent unbounded export cost.

  frameCount grows with the recording duration and has no upper limit. A
  one-hour recording at 12 fps produces 43,200 frames. CGImageDestination
  keeps every added frame until CGImageDestinationFinalize runs, so memory
  grows with frame count, and the export can run for a very long time. The
  path instruction asks for "GIF generation memory bounds." Cap frameCount
  and widen interval when the cap applies. You can also reject sources
  longer than a set duration.


  🛡️ Proposed fix

  -        let frameCount = max(1, Int(totalSeconds * Double(options.fps)))
  +        let maxFrames = 600
  +        let frameCount = min(maxFrames, max(1, Int(totalSeconds * Double(options.fps))))
           let interval = totalSeconds / Double(frameCount)

  Also set the frame delay to interval instead of 1.0 / fps. This keeps
  playback speed correct when the cap applies.


  As per path instructions, "Audit ... GIF generation memory bounds."


────────────────────────────────────────────────────────────────────────
  minor [Data Integrity & Integration]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/Presets.swift:168Sources/RecorderUI/Presets.swift:168-180]8;;

  Loading the legacy key does not migrate it, and a decode failure keeps a
  stale default.

  load() reads legacyKey when key is missing. It writes nothing to
  key until a later persist(). If decoding fails, the method returns
  early. defaultPresetID then keeps its old value even though presets is
  not refreshed. The second case causes the most harm. A corrupted
  MacScreenRecord.presets.v1 blob hides every preset, and there is no
  fallback to legacyKey. Try the legacy key when the new key fails to
  decode. After a successful legacy load, call persist().


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/RecordingViewModel.swift:555Sources/RecorderUI/RecordingViewModel.swift:555-569]8;;

  lastRecordingURL is set before the start succeeds.

  When session.start throws, lastRecordingURL still points to a file
  that does not exist. revealLastRecording and "Delete Artifacts…" then
  target that path. They also replace the previous valid recording URL.
  Assign the URL only after session.start succeeds.


────────────────────────────────────────────────────────────────────────
  trivial [Performance & Scalability]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/MainView.swift:572Sources/RecorderUI/MainView.swift:572-588]8;;

  updateNSView writes recorderWindow asynchronously on every update.

  Every SwiftUI update queues an async callback, even when the window has
  not changed. The callback triggers no publish because recorderWindow is
  not @Published, so this is wasted work only. Pass the window only from
  viewDidMoveToWindow in an NSView subclass.


────────────────────────────────────────────────────────────────────────
  major [Stability & Availability]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/RecordingViewModel.swift:621Sources/RecorderUI/RecordingViewModel.swift:621-666]8;;

  The salvage flow sets .error before it stops the session, so the user
  can start a new recording during the salvage.

  handleRecordingFailure sets status = .error(...) and then starts an
  async session.stop(). While the stop is in progress, toggleRecording()
  and the start hotkey both treat .error as idle and call
  startRecording(). startRecording() then calls session.start on a
  session that is still finalizing. It also overwrites lastRecordingURL.
  Set status = .stopping during the salvage. Set the error status only
  after stop() returns. Also report salvage failure in status. The
  current code only logs it.


  Proposed fix

  -        status = .error("⚠️ Recording interrupted: \(message)")
  +        status = .stopping
   ...
               } catch {
                   self.log.error("Auto-salvage failed: \(error.localizedDescription, privacy: .public)")
  +                self.status = .error("⚠️ Recording interrupted: \(message). Partial file could not be saved.")
               }


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/README.md:257README.md:257-258]8;;

  Correct the encoding claim.

  The text says no CPU-encode fallback exists and that all encoding runs on
  the GPU. VideoToolbox can use software encoders on Intel Macs without a
  hardware encoder. The README now claims Intel support. Reword this to say
  encoding uses VideoToolbox, hardware-accelerated where available.


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/README.md:348README.md:348]8;;

  Fix the stale product name in the FAQ.

  Line 348 says "Free Mac Screen Recorder natively supports both..." for
  this product. Use "Mac Screen Record".


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/NOTICE.md:23NOTICE.md:23]8;;

  Soften the "does not bundle networking frameworks" claim.

  Line 23 says the app does not bundle networking frameworks. AppKit,
  SwiftUI, and Foundation link CFNetwork transitively on macOS. The claim is
  not verifiable as written. Reword it to say the app code does not import
  or call networking APIs. Also add that this is enforced by the planned CI
  gate.


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/README.md:141README.md:141]8;;

  Fix the stale product name in the comparison table header.

  The header column still reads "Free Mac Screen Recorder". Use "Mac Screen
  Record". The path instructions require consistent naming.






  Proposed fix

  -|                              | Free Mac Screen Recorder | QuickTime | Loom | CleanShot X | ScreenFlow | Camtasia |
  +|                              | Mac Screen Record        | QuickTime | Loom | CleanShot X | ScreenFlow | Camtasia |


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/coderabbit_findings.txt:1coderabbit_findings.txt:1-733]8;;

  Remove generated CodeRabbit CLI output files from the repository.

  Both files are tool output artifacts and not project content. They go
  stale, and coderabbit_findings.txt leaks a local absolute path with a
  username.
  - coderabbit_findings.txt#L1-L733: delete the file and add it to
  .gitignore.
  - coderabbit_review.md#L1-L8: delete the file and add it to
  .gitignore.


────────────────────────────────────────────────────────────────────────
  trivial [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/build-app.sh:15Scripts/build-app.sh:15-21]8;;

  Unsupported ARCH values are not validated, and the architecture is not
  forced for the whole build.

  ARCH accepts any string from the environment. A value such as arm64e
  or a typo fails deep inside swift build. Validate against arm64 and
  x86_64 early. The uname -m value under Rosetta returns x86_64 on an
  Apple Silicon host, which silently builds an Intel binary. This is
  acceptable, but document it.


────────────────────────────────────────────────────────────────────────
  trivial [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/generate-sbom.py:15Scripts/generate-sbom.py:15-16]8;;

  An invalid SOURCE_DATE_EPOCH crashes the script with an unhelpful
  traceback.

  int(epoch) raises ValueError for non-numeric input. Wrap the call and
  exit with a clear message.


────────────────────────────────────────────────────────────────────────
  minor [Stability & Availability]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/WebcamOverlay.swift:155Sources/RecorderUI/WebcamOverlay.swift:155-179]8;;

  Run session configuration on sessionQueue.

  configureSession runs on the main actor while
  startRunning/stopRunning run on sessionQueue. If setDevice runs
  while a startRunning call is in progress, the two operations race.
  AVCaptureSession beginConfiguration/commitConfiguration calls also
  block the main thread. Dispatch the configuration to sessionQueue.


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/README.md:278README.md:278]8;;

  Fix the module count.

  The text says "four small Swift packages". The tree lists four library
  modules plus an executable, all in one package. Use "one Swift package
  with four library modules".


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/ROADMAP.md:65ROADMAP.md:65]8;;

  Egress attestation cannot be proven by the process itself.

  A self-reported statement that zero sockets were opened is unverifiable.
  Define the mechanism, or drop the claim.


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/build-app.sh:33Scripts/build-app.sh:33-39]8;;

  Reproducibility: the SBOM step ignores SOURCE_DATE_EPOCH unless the
  caller sets it.

  generate-sbom.py falls back to wall-clock time. Two builds of the same
  source then differ. The path instruction requires reproducible
  compilation. Export a default SOURCE_DATE_EPOCH from the last git commit
  time.






  Proposed fix

  +    export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)}"
       python3 "$ROOT/Scripts/generate-sbom.py" "$DIST_DIR/bom.json" "$ARCH" "$VERSION"


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/ROADMAP.md:11ROADMAP.md:11]8;;

  Remove the legal-evidence framing or the unverifiable claims.

  The text positions the app as a source of "undeniable" evidence of
  "corporate wrongdoing". The Evidence Seal phase promises court-submission
  integrity. A local hash does not give tamper evidence, because an attacker
  can recompute it. Use neutral wording. Add a signing or
  timestamp-authority design before you claim tamper evidence.


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/RELEASE_NOTES.md:35RELEASE_NOTES.md:35]8;;

  Version history conflicts across documents.

  RELEASE_NOTES.md dates v0.2.0 and v0.3.0 both October 1, 2026. It also
  uses the "Free Mac Screen Recorder" name and the old `Free Mac Screen
  Recorder Local` certificate name for 0.2.0. Historic naming is acceptable.
  Confirm the dates are correct. The 0.2.0 notes also describe the
  PrivacyClaimsProvider and keystroke overlay as shipped there, while
  ROADMAP.md lists them under v0.3.0–v0.3.5.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/build-app.sh:51Scripts/build-app.sh:51-56]8;;

  The identity check matches a substring and the legacy identity is silently
  accepted.

  grep -q "$CERT_NAME" matches any identity that contains the name. Use a
  quoted exact match, such as grep -F "\"$CERT_NAME\"". The legacy `Free
  Mac Screen Recorder Local` fallback signs with a different designated
  requirement. The bundle ID also changed, so TCC treats it as a new app.
  The fallback gives no TCC benefit. Remove it, or document the behavior.


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/README.md:401README.md:401-403]8;;

  Phase links do not match the Shipped list, and ROADMAP.md differs on
  hotkeys.

  README.md lists Phase 5 as shipped and plans Phases 7–9. ROADMAP.md shows
  shipped milestones as v0.1.0–v0.3.5 and has no Phase 5 or Phase 6 heading.
  ROADMAP.md also lists ⌘⇧R / ⌘⇧S as the hotkeys, but README.md documents
  ⌃⌥⌘R / ⌃⌥⌘S. Align the three documents. Verify the anchors resolve to the
  ROADMAP.md headings.


────────────────────────────────────────────────────────────────────────
  trivial [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/setup-stable-signing.sh:15Scripts/setup-stable-signing.sh:15]8;;

  The idempotency check still matches by substring and silently exits when
  the legacy certificate exists.

  grep -q "$CERT_NAME" can match a different identity name. Use an exact
  quoted match.


────────────────────────────────────────────────────────────────────────
  minor [Data Integrity & Integration]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/generate-sbom.py:21Scripts/generate-sbom.py:21-22]8;;

  Use the published CycloneDX schema identifier.

  $schema is allowed in CycloneDX 1.5. However, this value is incorrect:

  -        "$schema": "http://cyclonedx.org/schema/bom-1.5.json",
  +        "$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json",

  The current URL may prevent validators from resolving the intended schema.

Writing review comments... 2m 58s elapsed - still working - 26 findings so far

────────────────────────────────────────
Review complete
Review completed
26 findings ✔

Major    2
Minor    14
Trivial  10

40 files reviewed:
  - .coderabbit.yaml
  - LICENSE
  - NOTICE.md
  - Package.swift
  - README.md
  - RELEASE_NOTES.md
  - ROADMAP.md
  - Resources/Info.plist
  - Resources/MacScreenRecord.entitlements
  - Scripts/build-app.sh
  ... and 30 more files
────────────────────────────────────────

Print all AI prompts: coderabbit review --show-prompts
