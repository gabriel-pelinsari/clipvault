import AppKit

/// The menu bar icon: left click toggles the history, right click shows a menu.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onClick: (NSRect) -> Void
    private let makeMenu: () -> NSMenu

    init(onClick: @escaping (NSRect) -> Void, makeMenu: @escaping () -> NSMenu) {
        self.onClick = onClick
        self.makeMenu = makeMenu
        super.init()
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipVault")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        setPaused(false)
    }

    func setPaused(_ paused: Bool) {
        statusItem.button?.appearsDisabled = paused
        statusItem.button?.toolTip = paused ? "ClipVault — captura pausada" : "ClipVault"
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = makeMenu()
            sender.performClick(nil)
            statusItem.menu = nil
        } else if let window = sender.window {
            onClick(window.convertToScreen(sender.convert(sender.bounds, to: nil)))
        }
    }
}

/// Builds an `NSMenuItem` that runs a closure. The item keeps its target alive
/// through `representedObject`, since `target` is a weak reference.
func actionMenuItem(_ title: String, keyEquivalent: String = "", handler: @escaping () -> Void) -> NSMenuItem {
    let target = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: keyEquivalent)
    item.target = target
    item.representedObject = target
    return item
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}
