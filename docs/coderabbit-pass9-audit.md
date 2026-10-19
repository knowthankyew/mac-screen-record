╔═══════════════════════════════════════════╗
║                                           ║
║   New update available! 0.8.2 -> 0.9.0    ║
║          Run: coderabbit update           ║
║                                           ║
╚═══════════════════════════════════════════╝

────────────────────────────────────────
CodeRabbit Review

Diff      : tracked changes
Compare   : main → origin/main (local main differs, using origin/main)
Directory : mac-screen-record
────────────────────────────────────────

(\(\
(• .•)  Always design for concurrency. Allow for concurrency, and you'll design cleaner interfaces with fewer assumptions.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Dev/mac-screen-record/Sources/RecorderUI/RecordingViewModel.swift:837Sources/RecorderUI/RecordingViewModel.swift:837-858]8;;

  Clear lastRecordingURL and restore .ready after a burn.

  startRecording() sets lastRecordingURL = url at line 700.
  burnRecording() does not clear it. After a burn, revealLastRecording()
  falls through to lastRecordingURL, which points to a deleted file.
  trimLastRecording() can then open the trim modal on that missing file.
  The burned filename also stays in memory.

  The method sets .idle. Other reset paths, such as dismissError and
  deleteLastRecordingArtifacts, use displays.isEmpty ? .idle : .ready.
  Use the same logic here.

  Set the final status after await session.burn() returns. The
  CaptureSession race comment explains why.


  🐛 Proposed fix

  -        status = .idle
  +        status = .stopping
  +        self.lastRecordingURL = nil
   ...
           await session.burn()
  +        status = displays.isEmpty ? .idle : .ready
           restoreWindowIfNeeded()


────────────────────────────────────────────────────────────────────────
  trivial [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Dev/mac-screen-record/Tests/MacScreenRecordTests/MenuBarAndSessionCompanionTests.swift:81Tests/MacScreenRecordTests/MenuBarAndSessionCompanionTests.swift:81-92]8;;

  Make the burn test check the session and the file, not only the view-model
  status.

  setStatusForTesting puts the view model in .recording, but
  CaptureSession stays in .idle. session.burn() therefore returns at
  its guard and runs no teardown. The test passes no matter what burn()
  does. Hard Burn promises that the file is deleted, and nothing tests that.

  Add a CaptureCore test that does these steps:
  1. Start a VideoEncoder on a temporary URL.
  2. Append a synthetic frame.
  3. Call cancel(). Also cover the failed-writer path.
  4. Check that no file exists at the URL.

  The existing TrimTests synthetic-movie helper can generate the frames.


────────────────────────────────────────────────────────────────────────
  minor [Functional Correctness]
  → ]8;;vscode://file//Users/cl0rkster/Dev/mac-screen-record/Sources/RecorderUI/MenuBarController.swift:167Sources/RecorderUI/MenuBarController.swift:167]8;;

  Build shortcut labels from the current bindings, not fixed strings.

  The menu titles hard-code ⌥Space, ⌃⌥⌘S, ⌃⌥⌘⌫, ⌃⌥P, and ⌃⌥K.
  Users can remap all of these in Settings (settings.hotkeyBindings).
  After a remap, the menu shows the wrong shortcut. For Hard Burn this is a
  real risk: a user can press a combination they think is safe and destroy
  the recording.


  🐛 Proposed fix

  +    private func shortcut(_ action: HotkeyAction) -> String {
  +        guard let vm else { return "" }
  +        let b = vm.settings.hotkeyBindings[action] ?? HotkeyBinding.defaultBinding(for: action)
  +        return "  " + b.displayString
  +    }
   ...
  -        let pauseTitle = isPaused ? "Resume Recording  ⌥Space" : "Pause Recording  ⌥Space"
  +        let pauseTitle = (isPaused ? "Resume Recording" : "Pause Recording") + shortcut(.togglePause)
   ...
  -        let stopItem = NSMenuItem(title: "Stop Recording  ⌃⌥⌘S", ...
  +        let stopItem = NSMenuItem(title: "Stop Recording" + shortcut(.stopRecording), ...
   ...
  -        let burnItem = NSMenuItem(title: "Hard Burn (Discard)  ⌃⌥⌘⌫", ...
  +        let burnItem = NSMenuItem(title: "Hard Burn (Discard)" + shortcut(.burnRecording), ...

  Make the same change for the Facecam and Keystroke titles.





  Also applies to: 175-175, 183-183, 237-237, 242-242


────────────────────────────────────────────────────────────────────────
  minor [Maintainability & Code Quality]
  → ]8;;vscode://file//Users/cl0rkster/Dev/mac-screen-record/docs/ROADMAP.md:153docs/ROADMAP.md:153-155]8;;

  Remove the Phase 12 claims that the code does not implement.

  These documented behaviors do not match the code:
  - Line 169: "Aborts pending Evidence Seal checksum workers and clears
  volatile in-memory keystroke buffers and audio level monitors."
  burnRecording() and CaptureSession.burn() do not touch keystrokes,
  levels, or library seal tasks.
  - Line 168: "Directly unlinks partial video artifacts from disk." No
  explicit unlink exists. The code only calls encoder?.cancel(), which
  does not delete the file if the writer has failed. See the CaptureSession
  comment.
  - Line 153: "Pulsing red indicator." The icon is a static SF Symbol. The
  time format is MM:SS under one hour, not 00:02:45.
  - Line 155: The tooltip does not show the capture target or the encoding
  profile. It shows only the elapsed time.

  This repository uses Scripts/audit-claims.py to enforce documented
  guarantees. Privacy claims that the code does not meet are a governance
  defect. Implement the behavior or change the text.






  Also applies to: 166-169


────────────────────────────────────────────────────────────────────────
  major [Stability & Availability]
  → ]8;;vscode://file//Users/cl0rkster/Dev/mac-screen-record/Sources/CaptureCore/CaptureSession.swift:225Sources/CaptureCore/CaptureSession.swift:225-233]8;;

  Keep burn() in a non-startable state until teardown completes.

  burn() sets _state = .idle at line 228. It then waits on
  stream?.stopCapture(). The start() guard accepts .idle. A new
  start() can therefore run during the burn await. That start() assigns
  a new self.encoder and self.stream. When burn() resumes, lines
  243-245 cancel the new encoder and clear the new stream. The new recording
  is destroyed, and the stream keeps capturing with no encoder reference.

  RecordingViewModel.burnRecording() makes this path reachable. That
  method sets status = .idle (RecordingViewModel.swift line 837) before
  await session.burn(). The .startRecording hotkey handler and
  toggleRecording() accept .idle. A user who presses ⌃⌥⌘R right after
  Hard Burn triggers the race. stopCapture() can take hundreds of
  milliseconds, so the window is not small.

  .stopping in the accepted set causes the same kind of conflict. If
  stop() is waiting on encoder.finish(), burn() cancels that same
  writer while finishWriting is in progress.

  Fix:
  - Set _state = .stopping in burn(). Set .idle only at the end of
  burn().
  - Remove .stopping from the accepted states in burn().
  - Capture stream, encoder, and micCapture into locals and clear the
  properties before the first await. Tear down the locals after that.
  - In the view model, keep status = .stopping until session.burn()
  returns. Set the final status after that.


  🔒️ Proposed fix

       public func burn() async {
           let canBurn: Bool = stateLock.withLock {
               switch _state {
  -            case .recording, .paused, .failed, .stopping:
  -                _state = .idle
  +            case .recording, .paused, .failed:
  +                _state = .stopping
                   return true
               default:
                   return false
               }
           }
           guard canBurn else { return }
  +        let stream = self.stream, encoder = self.encoder, mic = self.micCapture
  +        self.stream = nil; self.encoder = nil; self.micCapture = nil
   
           do {
  -            try await stream?.stopCapture()
  +            try await stream?.stopCapture()
           } catch {
               log.error("burn stopCapture failed: \(error.localizedDescription, privacy: .public)")
           }
  -        micCapture?.stop()
  -        micCapture = nil
  -        encoder?.cancel()
  -        encoder = nil
  -        stream = nil
  +        mic?.stop()
  +        encoder?.cancel()
           state = .idle
       }

  The sample handler at line 270 reads self.encoder on videoQueue.
  Capturing locals stops new frames from reaching the canceled encoder. It
  does not make that unsynchronized property access safe in general.






  Also applies to: 245-246


────────────────────────────────────────
Review complete
Review completed
5 findings ✔

Major    1
Minor    3
Trivial  1

12 files reviewed:
  - README.md
  - Sources/CaptureCore/CaptureSession.swift
  - Sources/MacScreenRecord/App.swift
  - Sources/RecorderUI/AppSettings.swift
  - Sources/RecorderUI/GlobalHotkeys.swift
  - Sources/RecorderUI/MenuBarController.swift
  - Sources/RecorderUI/RecordingViewModel.swift
  - Sources/RecorderUI/SettingsView.swift
  - Tests/MacScreenRecordTests/HotkeyTests.swift
  - Tests/MacScreenRecordTests/MenuBarAndSessionCompanionTests.swift
  ... and 2 more files
────────────────────────────────────────

Print all AI prompts: coderabbit review --show-prompts
