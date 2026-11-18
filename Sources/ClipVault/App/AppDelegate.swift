import AppKit
import Observation
import ServiceManagement
import os

/// Composition root: builds the services and wires them to the UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: AppInfo.bundleID, category: "app")
    private let settings = AppSettings()
    private let hotKeys = HotKeyCenter.shared
    private let monitor = ClipboardMonitor()
    private var store: HistoryStore!
    private var model: HistoryViewModel!
    private var panel: PanelController!
    private var statusItem: StatusItemController!
    private var settingsWindow: SettingsWindowController!
    private var maintenanceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()

        store = HistoryStore(storage: makeStorage())
        model = HistoryViewModel(store: store, settings: settings)
        panel = PanelController(model: model)
        settingsWindow = SettingsWindowController { [unowned self] in
            SettingsView(settings: settings, store: store)
        }
        statusItem = StatusItemController(
            onClick: { [unowned self] rect in panel.toggle(anchor: .statusItem(rect)) },
            makeMenu: { [unowned self] in makeStatusMenu() }
        )
        model.actions = .init(
            paste: { [unowned self] item, autoPaste in paste(item, autoPaste: autoPaste) },
            close: { [unowned self] in panel.close() },
            openSettings: { [unowned self] in showSettings() }
        )

        monitor.shouldCapture = { [unowned self] source in
            guard !settings.isCapturePaused else { return false }
            guard let bundleID = source?.bundleID else { return true }
            return bundleID != AppInfo.bundleID && !settings.isExcluded(bundleID: bundleID)
        }
        monitor.onCapture = { [unowned self] content, source in
            store.add(content, source: source)
        }
        monitor.start()

        track({ [unowned self] in (settings.openHistoryShortcut, settings.togglePauseShortcut) }) { [unowned self] open, pause in
            hotKeys.register(.openHistory, combo: open) { [unowned self] in panel.toggle(anchor: .screenCenter) }
            hotKeys.register(.togglePause, combo: pause) { [unowned self] in settings.isCapturePaused.toggle() }
        }
        track({ [unowned self] in HistoryStore.Limits(maxItems: settings.maxItems, retention: settings.retention.interval) }) { [unowned self] limits in
            store.limits = limits
            store.enforceLimits()
        }
        track({ [unowned self] in settings.isCapturePaused }) { [unowned self] paused in
            statusItem.setPaused(paused)
        }

        let timer = Timer(timeInterval: 60, repeats: true) { [unowned self] _ in
            MainActor.assumeIsolated { _ = store.enforceLimits() }
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer

        // Never leave clipboard history on screen behind a locked session.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil
        )

        registerLoginItemOnFirstLaunch()
        if settings.autoPaste, !Paster.canPostEvents {
            // Shows the system prompt (once per install) so paste-on-click works from the start.
            Paster.requestAccess()
        }
    }

    // MARK: - Actions

    private func paste(_ item: ClipItem, autoPaste: Bool) {
        let imageData = item.isImage ? store.imageData(for: item.id) : nil
        guard monitor.write(item, imageData: imageData) else {
            NSSound.beep()
            return
        }
        store.markUsed(item.id)
        panel.close()

        guard autoPaste, settings.autoPaste else { return }
        // Post even when the preflight says no: the check can lag behind a permission the
        // user just granted, and without permission the event is simply dropped.
        if !Paster.canPostEvents { Paster.requestAccess() }
        Task {
            // Let the panel finish closing so the keystroke reaches the app underneath.
            try? await Task.sleep(for: .milliseconds(70))
            Paster.pressCommandV()
        }
    }

    private func showSettings() {
        panel.close()
        settingsWindow.show()
    }

    @objc private func screenLocked() {
        panel.close()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let open = actionMenuItem("Abrir histórico") { [unowned self] in panel.show(anchor: .screenCenter) }
        if let combo = settings.openHistoryShortcut {
            open.title += "  \(combo.displayString)"
        }
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(actionMenuItem(settings.isCapturePaused ? "Retomar captura" : "Pausar captura") { [unowned self] in
            settings.isCapturePaused.toggle()
        })
        menu.addItem(actionMenuItem("Ajustes…", keyEquivalent: ",") { [unowned self] in showSettings() })
        menu.addItem(.separator())
        menu.addItem(actionMenuItem("Sair do ClipVault", keyEquivalent: "q") { NSApp.terminate(nil) })
        return menu
    }

    // MARK: - Setup

    private func makeStorage() -> EncryptedStore? {
        do {
            let key = try KeychainKey.loadOrCreate(service: AppInfo.bundleID, account: "history-encryption-key")
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            return try EncryptedStore(directory: support.appending(path: "ClipVault"), key: key)
        } catch {
            log.error("Encrypted storage unavailable, keeping history in memory: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Keeps the app in the menu bar across restarts, but only for the installed copy
    /// so development builds don't register themselves as login items.
    private func registerLoginItemOnFirstLaunch() {
        guard !settings.didOfferLoginItem, Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        settings.didOfferLoginItem = true
        do {
            try SMAppService.mainApp.register()
        } catch {
            log.error("Login item registration failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Calls `apply` with the current value now and again whenever an observed property read by `read` changes.
@MainActor
func track<Value>(_ read: @escaping @MainActor () -> Value, apply: @escaping @MainActor (Value) -> Void) {
    let value = withObservationTracking(read) {
        Task { @MainActor in track(read, apply: apply) }
    }
    apply(value)
}
