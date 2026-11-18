import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A floating panel that takes keyboard focus without activating the app,
/// so the app you were typing in stays frontmost and can receive the paste.
private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelController: NSObject, NSWindowDelegate {
    enum Anchor {
        case statusItem(NSRect)
        case screenCenter
    }

    private let panel: HistoryPanel
    private let model: HistoryViewModel
    private var keyMonitor: Any?
    private var lastClosedAt = Date.distantPast

    var isVisible: Bool { panel.isVisible }

    init(model: HistoryViewModel) {
        self.model = model
        panel = HistoryPanel(
            contentRect: NSRect(origin: .zero, size: HistoryView.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.delegate = self

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        let hosting = NSHostingView(rootView: HistoryView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // The transparent title bar exists only for rounded corners and a shadow; don't inset content for it.
        hosting.safeAreaRegions = []
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event)
        }
    }

    func toggle(anchor: Anchor) {
        if panel.isVisible {
            close()
        } else if Date.now.timeIntervalSince(lastClosedAt) > 0.25 {
            // Clicking the status item while open first resigns key (closing the panel),
            // then delivers the click; the debounce stops that click from reopening it.
            show(anchor: anchor)
        }
    }

    func show(anchor: Anchor) {
        model.prepareForPresentation()
        panel.setFrameOrigin(origin(for: anchor))
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard panel.isVisible else { return }
        lastClosedAt = .now
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func origin(for anchor: Anchor) -> NSPoint {
        let size = panel.frame.size
        switch anchor {
        case .statusItem(let rect):
            let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? rect
            let x = min(max(rect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            return NSPoint(x: x, y: rect.minY - size.height - 6)
        case .screenCenter:
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.08)
        }
    }

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 0, kVK_ANSI_2: 1, kVK_ANSI_3: 2, kVK_ANSI_4: 3, kVK_ANSI_5: 4,
        kVK_ANSI_6: 5, kVK_ANSI_7: 6, kVK_ANSI_8: 7, kVK_ANSI_9: 8,
    ]

    /// Returns `nil` for keys the panel handles, so they never reach the search field.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        let keyCode = Int(event.keyCode)

        switch keyCode {
        case kVK_DownArrow:
            model.moveSelection(by: 1)
        case kVK_UpArrow:
            model.moveSelection(by: -1)
        case kVK_PageDown:
            model.moveSelection(by: 8)
        case kVK_PageUp:
            model.moveSelection(by: -8)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.activateSelected(paste: !modifiers.contains(.shift))
        case kVK_Escape:
            if model.query.isEmpty { close() } else { model.query = "" }
        case kVK_Tab:
            model.cycleFilter(forward: !modifiers.contains(.shift))
        default:
            guard modifiers == .command else { return event }
            if let index = Self.digitKeys[keyCode] {
                model.activate(at: index)
            } else if keyCode == kVK_ANSI_P {
                model.togglePinSelected()
            } else if keyCode == kVK_Delete {
                model.deleteSelected()
            } else if keyCode == kVK_ANSI_Comma {
                model.actions.openSettings()
            } else if keyCode == kVK_ANSI_W {
                close()
            } else {
                return event
            }
        }
        return nil
    }
}
