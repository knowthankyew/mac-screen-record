import AppKit
import SwiftUI

/// Helper for configuring windows and sheets so that application termination commands
/// (such as Dock right-click Quit, Cmd+Q, or system logout) are not blocked while modal.
public enum ModalTerminationHelper {
    /// Configures a window so that it does not prevent application termination while modal.
    @MainActor
    public static func configure(window: NSWindow?) {
        window?.preventsApplicationTerminationWhenModal = false
    }

    /// Configures any sheets attached to a window so that they do not prevent application termination.
    @MainActor
    public static func configureSheets(on window: NSWindow?) {
        guard let window else { return }
        window.preventsApplicationTerminationWhenModal = false
        for sheet in window.sheets {
            sheet.preventsApplicationTerminationWhenModal = false
        }
        window.attachedSheet?.preventsApplicationTerminationWhenModal = false
    }

    /// Installs NotificationCenter observers that automatically configure all sheets and key windows
    /// to allow application termination.
    @MainActor
    public static func installObservers() -> [NSObjectProtocol] {
        let sheetObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willBeginSheetNotification,
            object: nil,
            queue: .main
        ) { note in
            DispatchQueue.main.async {
                configureSheets(on: note.object as? NSWindow)
            }
        }

        let keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            DispatchQueue.main.async {
                configureSheets(on: note.object as? NSWindow)
            }
        }

        return [sheetObserver, keyObserver]
    }
}

/// An invisible background bridge that configures the enclosing `NSWindow` / sheet
/// to set `preventsApplicationTerminationWhenModal = false`.
///
/// By default, AppKit sets `preventsApplicationTerminationWhenModal` to `true` on modal windows
/// and sheets. This causes AppKit to silently drop termination events when the user right-clicks
/// the app icon in the Dock / task bar and clicks "Quit", or presses Cmd+Q.
///
/// Attaching this modifier ensures the OS-level quit commands always take precedence over the modal UI.
public struct AllowAppTerminationWhenModalView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            ModalTerminationHelper.configure(window: view?.window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            ModalTerminationHelper.configure(window: nsView?.window)
        }
    }
}

extension View {
    /// Configures the presenting window or sheet so that application termination commands
    /// (such as Dock right-click Quit, Cmd+Q, or system logout) are not blocked while modal.
    public func allowAppTerminationWhenModal() -> some View {
        self.background(AllowAppTerminationWhenModalView())
    }
}
