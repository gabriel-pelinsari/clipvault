import Carbon.HIToolbox
import Observation

/// System-wide shortcuts via Carbon's `RegisterEventHotKey`, which works inside the
/// App Sandbox and needs no Accessibility or Input Monitoring permission.
@Observable
final class HotKeyCenter {
    enum Action: UInt32, CaseIterable {
        case openHistory = 1
        case togglePause = 2
    }

    static let shared = HotKeyCenter()

    /// Actions whose shortcut is already taken by another app.
    private(set) var conflicts: Set<Action> = []

    @ObservationIgnored private var entries: [Action: (combo: KeyCombo?, handler: () -> Void)] = [:]
    @ObservationIgnored private var registered: [Action: EventHotKeyRef] = [:]
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var isSuspended = false

    private static let signature: OSType = 0x434C_5654 // "CLVT"

    private init() {}

    func register(_ action: Action, combo: KeyCombo?, handler: @escaping () -> Void) {
        entries[action] = (combo, handler)
        guard !isSuspended else { return }
        activate(action)
    }

    /// Releases every shortcut so a recorder can capture key presses that would otherwise trigger them.
    func suspend() {
        isSuspended = true
        Action.allCases.forEach(deactivate)
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        Action.allCases.forEach(activate)
    }

    fileprivate func fire(_ rawID: UInt32) {
        guard let action = Action(rawValue: rawID) else { return }
        entries[action]?.handler()
    }

    private func activate(_ action: Action) {
        deactivate(action)
        guard let combo = entries[action]?.combo else { return }
        installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            registered[action] = ref
        } else {
            conflicts.insert(action)
        }
    }

    private func deactivate(_ action: Action) {
        conflicts.remove(action)
        if let ref = registered.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, &eventHandler)
    }
}

/// Carbon delivers hot key events on the main thread's event loop.
private nonisolated func hotKeyHandler(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let rawID = hotKeyID.id
    MainActor.assumeIsolated { HotKeyCenter.shared.fire(rawID) }
    return noErr
}
