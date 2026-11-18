import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Sends ⌘V to the frontmost app after an item is chosen.
///
/// Uses the "post event" privilege (`CGRequestPostEventAccess`), which a sandboxed
/// app may request; it appears under Privacy & Security › Accessibility.
enum Paster {
    static var canPostEvents: Bool { CGPreflightPostEventAccess() }

    @discardableResult
    static func requestAccess() -> Bool { CGRequestPostEventAccess() }

    static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
