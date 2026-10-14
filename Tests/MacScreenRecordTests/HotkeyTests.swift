import Carbon.HIToolbox
import Foundation
@testable import RecorderUI

@MainActor
final class HotkeyTests {

    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    func withLifecycle(_ body: () async throws -> Void) async throws {
        suiteName = "com.macscreenrecord.tests.hotkeys.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        defer {
            if let suiteName {
                isolatedDefaults?.removePersistentDomain(forName: suiteName)
            }
        }
        try await body()
    }

    /// Verifies canonical default bindings and user-facing display string generation.
    func testDefaultHotkeyBindingsAndDisplayStrings() throws {
        let defaults = HotkeyBinding.defaultBindings
        try checkEqual(defaults.count, HotkeyAction.allCases.count, "All hotkey actions have default bindings")

        let start = try unwrap(defaults[.startRecording])
        try checkEqual(start.displayString, "⌃⌥⌘R", "Start recording canonical shortcut")

        let stop = try unwrap(defaults[.stopRecording])
        try checkEqual(stop.displayString, "⌃⌥⌘S", "Stop recording canonical shortcut")

        let pause = try unwrap(defaults[.togglePause])
        try checkEqual(pause.displayString, "⌥Space", "Pause/Resume canonical shortcut")

        let facecam = try unwrap(defaults[.toggleFacecam])
        try checkEqual(facecam.displayString, "⌃⌥P", "Toggle Facecam canonical shortcut")

        let keystrokes = try unwrap(defaults[.toggleKeystrokes])
        try checkEqual(keystrokes.displayString, "⌃⌥K", "Toggle Keystroke overlay canonical shortcut")

        // Test display strings with various modifier combinations
        let combo1 = HotkeyBinding(keyCode: kVK_ANSI_A, modifiers: cmdKey | shiftKey)
        try checkEqual(combo1.displayString, "⇧⌘A")

        let combo2 = HotkeyBinding(keyCode: kVK_ANSI_Z, modifiers: controlKey | optionKey | shiftKey | cmdKey)
        try checkEqual(combo2.displayString, "⌃⌥⇧⌘Z")
    }

    /// Verifies JSON encoding, decoding, and persistence of custom hotkey configurations.
    func testHotkeyBindingCustomizationAndPersistence() throws {
        var customBindings = HotkeyBinding.defaultBindings
        let customPause = HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: cmdKey | optionKey)
        customBindings[.togglePause] = customPause

        let encoder = JSONEncoder()
        let data = try encoder.encode(customBindings)
        let decoded = try JSONDecoder().decode([HotkeyAction: HotkeyBinding].self, from: data)

        try checkEqual(decoded[.togglePause], customPause)
        try checkEqual(decoded[.startRecording], HotkeyBinding.defaultBinding(for: .startRecording))

        // Verify AppSettings integration using isolatedDefaults
        let settings = AppSettings(defaults: isolatedDefaults)

        let setResult = settings.setHotkeyBinding(customPause, for: .togglePause)
        try checkTrue(setResult, "Custom binding successfully registered")
        try checkEqual(settings.hotkeyBindings[.togglePause], customPause)

        // Verify duplicate prevention
        let duplicateResult = settings.setHotkeyBinding(customPause, for: .startRecording)
        try checkFalse(duplicateResult, "Duplicate binding assignment prevented")

        settings.resetHotkeyBindingsToDefaults()
        try checkEqual(settings.hotkeyBindings[.togglePause], HotkeyBinding.defaultBinding(for: .togglePause))
    }

    /// Verifies lifecycle and runtime rebinding without crashing or memory leaks.
    func testGlobalHotkeyControllerLifecycle() throws {
        let controller = GlobalHotkeyController()
        var triggeredStart = false
        var triggeredStop = false

        let handlers: [HotkeyAction: GlobalHotkeyController.ActionHandler] = [
            .startRecording: { triggeredStart = true },
            .stopRecording: { triggeredStop = true }
        ]

        controller.install(bindings: HotkeyBinding.defaultBindings, handlers: handlers)
        try checkEqual(controller.registeredActions.count, 2)
        try checkTrue(controller.registeredActions.contains(.startRecording))
        try checkTrue(controller.registeredActions.contains(.stopRecording))

        // Runtime rebinding of specific action
        let newBinding = HotkeyBinding(keyCode: kVK_ANSI_T, modifiers: cmdKey | optionKey)
        let updateResult = controller.updateBinding(for: .startRecording, binding: newBinding)
        try checkTrue(updateResult, "Rebinding succeeded")
        try checkTrue(controller.registeredActions.contains(.startRecording))

        // Suspend and resume lifecycle
        controller.suspend()
        try checkTrue(controller.registeredActions.isEmpty, "Hotkeys unregistered when suspended")
        controller.resume()
        try checkEqual(controller.registeredActions.count, 2, "Hotkeys restored when resumed")

        // Rebinding all actions simultaneously
        controller.updateBindings(HotkeyBinding.defaultBindings)
        try checkEqual(controller.registeredActions.count, 2)

        // Cleanup
        controller.uninstall()
        try checkTrue(controller.registeredActions.isEmpty, "All hotkeys unregistered on uninstall")
        try checkFalse(triggeredStart)
        try checkFalse(triggeredStop)
    }
}
