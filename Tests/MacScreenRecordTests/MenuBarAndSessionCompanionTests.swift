import Foundation
@testable import RecorderUI

@MainActor
final class MenuBarAndSessionCompanionTests {

    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    func withLifecycle(_ body: () async throws -> Void) async throws {
        suiteName = "com.macscreenrecord.tests.companion.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        defer {
            if let suiteName {
                isolatedDefaults?.removePersistentDomain(forName: suiteName)
            }
        }
        try await body()
    }

    /// Verifies that MenuBarController exhibits zero status bar presence when idle,
    /// dynamically creates the status item upon recording/pause, and completely cleans up on termination.
    func testMenuBarEphemeralLifecycle() throws {
        let controller = MenuBarController()
        defer { controller.removeStatusItem() }

        // 1. Initially idle — must have ZERO status item
        try checkFalse(controller.hasStatusItem, "Status item does not exist while idle")

        // 2. Transition to recording — status item appears with duration
        let twoMinutesAgo = Date().addingTimeInterval(-125) // 02:05
        controller.update(for: .recording(startedAt: twoMinutesAgo))
        try checkTrue(controller.hasStatusItem, "Status item dynamically appears during recording")
        let recordingTitle = try unwrap(controller.currentButtonTitle)
        try checkTrue(recordingTitle.contains("02:05"), "Button title shows elapsed recording duration")

        // 3. Transition to paused — status item persists with (Paused) indicator
        let pauseTime = twoMinutesAgo.addingTimeInterval(120) // 02:00
        controller.update(for: .paused(startedAt: twoMinutesAgo, pausedAt: pauseTime))
        try checkTrue(controller.hasStatusItem, "Status item remains during pause")
        let pausedTitle = try unwrap(controller.currentButtonTitle)
        try checkTrue(pausedTitle.contains("02:00"), "Button title freezes at paused duration")
        try checkTrue(pausedTitle.contains("(Paused)"), "Button title includes (Paused) label")

        // 4. Transition to finished / idle — status item is completely removed (zero bloat)
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy.mp4")
        controller.update(for: .finished(dummyURL))
        try checkFalse(controller.hasStatusItem, "Status item is completely removed upon finishing")

        controller.update(for: .idle)
        try checkFalse(controller.hasStatusItem, "Status item remains absent in idle state")
    }

    /// Verifies duration string formatting across boundary conditions (MM:SS vs HH:MM:SS).
    func testDurationFormatting() throws {
        let controller = MenuBarController()
        defer { controller.removeStatusItem() }

        try checkEqual(controller.formatTime(seconds: 0), "00:00")
        try checkEqual(controller.formatTime(seconds: 59), "00:59")
        try checkEqual(controller.formatTime(seconds: 60), "01:00")
        try checkEqual(controller.formatTime(seconds: 3599), "59:59")
        try checkEqual(controller.formatTime(seconds: 3600), "01:00:00")
        try checkEqual(controller.formatTime(seconds: 7325), "02:02:05")
    }

    /// Verifies persistence and defaults of the distraction-free window auto-minimization setting.
    func testHideWindowDuringRecordingSetting() throws {
        let settings = AppSettings(defaults: isolatedDefaults)
        try checkFalse(settings.hideWindowDuringRecording, "hideWindowDuringRecording defaults to false")

        settings.hideWindowDuringRecording = true
        try checkTrue(settings.hideWindowDuringRecording, "hideWindowDuringRecording toggles to true")

        // Reload from defaults to verify persistence
        let reloaded = AppSettings(defaults: isolatedDefaults)
        try checkTrue(reloaded.hideWindowDuringRecording, "hideWindowDuringRecording persists to UserDefaults")
    }

    /// Verifies that burnRecording cleanly resets recording state back to idle.
    func testBurnRecordingStateReset() async throws {
        let settings = AppSettings(defaults: isolatedDefaults)
        let vm = RecordingViewModel(settings: settings)

        // Force vm into simulated recording state
        let now = Date()
        vm.setStatusForTesting(.recording(startedAt: now))
        try checkEqual(vm.status, .recording(startedAt: now))

        await vm.burnRecording()
        try checkEqual(vm.status, .idle, "burnRecording resets status to .idle")
    }
}
