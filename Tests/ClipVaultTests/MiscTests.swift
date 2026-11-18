import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ClipVault

struct KeyComboTests {
    @Test func `global shortcuts need command, option or control`() {
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift]).isValidGlobalShortcut)
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.option]).isValidGlobalShortcut)
        #expect(!KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.shift]).isValidGlobalShortcut)
        #expect(!KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: []).isValidGlobalShortcut)
    }

    @Test func `modifiers render in Apple's order`() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift, .option, .control])
        #expect(combo.modifierSymbols == "⌃⌥⇧⌘")
        #expect(combo.carbonModifiers == UInt32(cmdKey | shiftKey | optionKey | controlKey))
    }

    @Test func `ignores irrelevant modifier flags`() {
        let combo = KeyCombo(keyCode: 1, modifiers: [.command, .capsLock, .function])
        #expect(combo.modifiers == .command)
    }
}

struct SettingsTests {
    @Test func `a cleared shortcut stays cleared after relaunch`() throws {
        let suite = "clipvault-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.openHistoryShortcut == .defaultOpenHistory)
        settings.openHistoryShortcut = nil

        #expect(AppSettings(defaults: defaults).openHistoryShortcut == nil)
    }

    @Test func `password managers are excluded by default`() throws {
        let suite = "clipvault-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppSettings(defaults: defaults).isExcluded(bundleID: "com.1password.1password"))
    }
}

struct ClipboardMonitorTests {
    @Test(arguments: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"])
    func `skips content marked sensitive`(marker: String) {
        let types: [NSPasteboard.PasteboardType] = [.string, NSPasteboard.PasteboardType(marker)]
        #expect(ClipboardMonitor.containsSensitiveType(types))
    }

    @Test func `records ordinary text`() {
        #expect(!ClipboardMonitor.containsSensitiveType([.string, .rtf]))
    }
}

struct ViewModelTests {
    @Test func `search matches text and keeps pinned items first`() throws {
        let store = HistoryStore(storage: nil)
        let start = Date(timeIntervalSince1970: 1_000)
        let pinned = try #require(store.add(.text("pinned apple"), source: nil, now: start))
        store.togglePin(pinned.id)
        store.add(.text("apple pie"), source: nil, now: start.addingTimeInterval(1))
        store.add(.text("banana"), source: nil, now: start.addingTimeInterval(2))
        let suite = "clipvault-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = HistoryViewModel(store: store, settings: AppSettings(defaults: defaults))
        model.query = "apple"

        #expect(model.visibleItems.map(\.text) == ["pinned apple", "apple pie"])
        #expect(model.selectedItem?.text == "pinned apple")
        model.moveSelection(by: 5)
        #expect(model.selectedItem?.text == "apple pie")
    }
}
