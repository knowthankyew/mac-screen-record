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
(• .•)  Transformers: Not just a movie franchise.

Summarizing changes... 4s elapsed
Writing review comments... 54s elapsed
Writing review comments... 1m 01s elapsed - still working

────────────────────────────────────────────────────────────────────────
  trivial [Performance & Scalability]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/EncoderKit/GIFExporter.swift:93Sources/EncoderKit/GIFExporter.swift:93-94]8;;

  Each frame decode is a separate seek with zero tolerance. This is slow for
  long recordings.

  Each generator.image(at:) call does an exact seek and decode. On a long
  4K HEVC recording, 600 exact seeks can take minutes. Use
  generator.images(for:) (macOS 13+), which batches the requests.
  Alternatively, allow a small tolerance near interval / 2.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/RecorderUI/RecordingsLibrary.swift:121Sources/RecorderUI/RecordingsLibrary.swift:121-170]8;;

  A failed delete is silent to the user.

  When trashItem/removeItem fails, deleteArtifacts only logs the
  error. The row stays in the list and no message appears. Make the method
  throws, or return a result, so RecordingsListView can show
  errorMessage.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/EncoderKit/GIFExporter.swift:51Sources/EncoderKit/GIFExporter.swift:51-52]8;;

  Frame timing is wrong when the frame count is capped.

  For a long video, frameCount is capped at 600, so interval becomes
  totalSeconds / 600. The GIF plays in real time at a low frame rate,
  which is acceptable. When interval is below 0.02, max(0.02, …) raises
  it. Line 91 then computes sample times as i interval. Those times can
  run past duration. Here is the trigger: a 1-second clip at fps=50 gives
  50 frames and an interval of 0.02. That case works. But with fps=50 and a
  10.001 s clip, the count is capped at 500 and the interval is ~0.02, which
  is fine. The real gap is that GIF delay times have a 0.01 s resolution,
  and most decoders clamp delays under 0.02. The current math stays inside
  those limits. However, if Double(i) interval reaches or exceeds
  duration, generator.image(at:) with zero tolerance can throw. That
  error aborts the whole export. Clamp the sample time below duration.


  Proposed fix

  -            let t = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
  +            let secs = min(Double(i) * interval, max(0, totalSeconds - 0.001))
  +            let t = CMTime(seconds: secs, preferredTimescale: 600)


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/README.md:117README.md:117]8;;

  Fix the conflict between the shipped and planned pause/resume claims.

  Line 117 and Phase 4 at Line 395 list pause/resume as shipped. Phase 8 at
  Line 401 lists pause/resume as planned. Line 401 should say "pause/resume
  hotkey", so the planned item is clearly different from the shipped
  feature.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/audit-claims.py:218Scripts/audit-claims.py:218-241]8;;

  Compare the SBOM against the bundle copy, not against a possibly stale
  dist/bom.json.

  The build script copies dist/bom.json into the bundle. The audit then
  validates dist/bom.json only when that file exists. If the
  generate-sbom.py step is skipped, an old dist/bom.json passes or fails
  this audit based on an earlier build. Validate
  $APP_DIR/Contents/Resources/bom.json, or make the SBOM step mandatory in
  the build.


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/build-app.sh:40Scripts/build-app.sh:40-51]8;;

  Make SBOM generation mandatory.

  The script treats the claims audit as mandatory, but it skips SBOM
  generation without an error if generate-sbom.py is missing. If the SBOM
  step is skipped, the bundle has no bom.json, which contradicts
  NOTICE.md. Fail the build when the SBOM script is missing.


  Proposed fix

  -if [ -f "$ROOT/Scripts/generate-sbom.py" ]; then
  +if [ ! -f "$ROOT/Scripts/generate-sbom.py" ]; then
  +    echo "ERROR: Scripts/generate-sbom.py is missing." >&2
  +    exit 1
  +fi
  +{


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/ROADMAP.md:59ROADMAP.md:59]8;;

  Change the hashing step order.

  A SHA-256 hash taken "before closing the file handle" can miss data that
  AVAssetWriter writes during finalization. Compute the hash after
  finishWriting completes and the file is closed.


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/RELEASE_NOTES.md:3RELEASE_NOTES.md:3]8;;

  Correct the upstream release range.

  This note says that the upstream releases covered v0.1.0 – v0.3.0. The
  0.2.0 section and 0.3.0 section in this file describe releases of this
  fork. The claim conflicts with the fork history and can mislead readers
  about attribution. Give only the upstream versions that were actually
  released, or remove the version range.


────────────────────────────────────────────────────────────────────────
  minor [Security & Privacy] | 🛡️ Analyzed with Security Review
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Scripts/audit-claims.py:88Scripts/audit-claims.py:88-103]8;;

  Security: Security Misconfiguration (CWE-1188)
  Reachability: Internal · Exploitability: Difficult

  Close the egress-scanner coverage gaps before NOTICE.md claims complete
  verification. The shown patterns miss NSURLSession, lowercase nw_*
  APIs, network-specific CFNetwork stream APIs, and framework imports such
  as #import . Add targeted patterns for these forms. Do not flag generic
  CFReadStream unless the pattern identifies network-backed use.

Writing review comments... 3m 07s elapsed - still working - 9 findings so far

────────────────────────────────────────────────────────────────────────
  minor [Stability & Availability]
  → ]8;;vscode://file//Users/cl0rkster/Github/mac-screen-record/Sources/CaptureCore/CaptureSession.swift:135Sources/CaptureCore/CaptureSession.swift:135-141]8;;

  Stop the microphone before clearing encoder in the stream-registration
  failure path.

  At this point mic.start() has already succeeded. The microphone callback
  on MicrophoneCapture.queue reads self.encoder (Line 116). This path
  sets self.encoder = nil before it stops the microphone. That is an
  unsynchronized read and write of a strong class reference on two threads.
  CaptureSession is @unchecked Sendable, so the compiler does not detect
  this race. The race can cause a retain/release crash.

  Stop the microphone first, then clear the encoder.
  AVCaptureSession.stopRunning() is synchronous, so no more callbacks
  arrive after it returns.


  🔒️ Proposed reorder

           } catch {
               state = .failed(error.localizedDescription)
  -            self.encoder?.cancel()
  -            self.encoder = nil
               self.micCapture?.stop()
               self.micCapture = nil
  +            self.encoder?.cancel()
  +            self.encoder = nil
               throw CaptureError.streamFailed(error.localizedDescription)
           }

  As per path instructions: "audio/video frame processing is safely isolated
  on dedicated background queues without deadlocks."

Writing review comments... 4m 14s elapsed - still working - 10 findings so far

────────────────────────────────────────
Review complete
Review completed
10 findings ✔

Minor    9
Trivial  1

52 files reviewed:
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
  ... and 42 more files
────────────────────────────────────────

Print all AI prompts: coderabbit review --show-prompts
