import Foundation
import Observation

nonisolated enum Retention: Int, CaseIterable, Identifiable, Sendable {
    case oneHour = 3_600
    case oneDay = 86_400
    case oneWeek = 604_800
    case oneMonth = 2_592_000
    case forever = 0

    var id: Int { rawValue }

    var interval: TimeInterval? { self == .forever ? nil : TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .oneHour: "1 hora"
        case .oneDay: "1 dia"
        case .oneWeek: "7 dias"
        case .oneMonth: "30 dias"
        case .forever: "Nunca"
        }
    }
}

nonisolated struct ExcludedApp: Codable, Hashable, Identifiable, Sendable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// User preferences, persisted in `UserDefaults` (never any clipboard content).
@Observable
final class AppSettings {
    static let maxItemsOptions = [50, 100, 200, 500, 1000]

    /// Password managers and system credential stores. Most of them also mark their
    /// copies as concealed, which is always honored; this list is a second line of defense.
    static let defaultExcludedApps: [ExcludedApp] = [
        ExcludedApp(bundleID: "com.apple.keychainaccess", name: "Acesso às Chaves"),
        ExcludedApp(bundleID: "com.apple.Passwords", name: "Senhas"),
        ExcludedApp(bundleID: "com.1password.1password", name: "1Password"),
        ExcludedApp(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        ExcludedApp(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
        ExcludedApp(bundleID: "com.lastpass.LastPass", name: "LastPass"),
        ExcludedApp(bundleID: "org.keepassxc.keepassxc", name: "KeePassXC"),
    ]

    @ObservationIgnored private let defaults: UserDefaults

    var maxItems: Int { didSet { defaults.set(maxItems, forKey: Key.maxItems) } }
    var retention: Retention { didSet { defaults.set(retention.rawValue, forKey: Key.retention) } }
    var autoPaste: Bool { didSet { defaults.set(autoPaste, forKey: Key.autoPaste) } }
    var isCapturePaused: Bool { didSet { defaults.set(isCapturePaused, forKey: Key.paused) } }
    var excludedApps: [ExcludedApp] {
        didSet { defaults.set(try? JSONEncoder().encode(excludedApps), forKey: Key.excludedApps) }
    }
    var openHistoryShortcut: KeyCombo? {
        didSet { Self.store(openHistoryShortcut, in: defaults, key: Key.openHistoryShortcut) }
    }
    var togglePauseShortcut: KeyCombo? {
        didSet { Self.store(togglePauseShortcut, in: defaults, key: Key.togglePauseShortcut) }
    }
    var didOfferLoginItem: Bool { didSet { defaults.set(didOfferLoginItem, forKey: Key.didOfferLoginItem) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMax = defaults.integer(forKey: Key.maxItems)
        maxItems = Self.maxItemsOptions.contains(storedMax) ? storedMax : 200
        retention = (defaults.object(forKey: Key.retention) as? Int).flatMap(Retention.init) ?? .oneMonth
        autoPaste = defaults.object(forKey: Key.autoPaste) as? Bool ?? true
        isCapturePaused = defaults.bool(forKey: Key.paused)
        excludedApps = defaults.data(forKey: Key.excludedApps)
            .flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) }
            ?? Self.defaultExcludedApps
        openHistoryShortcut = Self.load(from: defaults, key: Key.openHistoryShortcut, default: .defaultOpenHistory)
        togglePauseShortcut = Self.load(from: defaults, key: Key.togglePauseShortcut, default: nil)
        didOfferLoginItem = defaults.bool(forKey: Key.didOfferLoginItem)
    }

    func isExcluded(bundleID: String) -> Bool {
        excludedApps.contains { $0.bundleID == bundleID }
    }

    // A cleared shortcut is stored as empty data so it stays cleared instead of
    // falling back to the default on the next launch.
    private static func store(_ combo: KeyCombo?, in defaults: UserDefaults, key: String) {
        let data = combo.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String, default fallback: KeyCombo?) -> KeyCombo? {
        guard let data = defaults.data(forKey: key) else { return fallback }
        guard !data.isEmpty else { return nil }
        return (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? fallback
    }

    private enum Key {
        static let maxItems = "maxItems"
        static let retention = "retention"
        static let autoPaste = "autoPaste"
        static let paused = "capturePaused"
        static let excludedApps = "excludedApps"
        static let openHistoryShortcut = "shortcut.openHistory"
        static let togglePauseShortcut = "shortcut.togglePause"
        static let didOfferLoginItem = "didOfferLoginItem"
    }
}
