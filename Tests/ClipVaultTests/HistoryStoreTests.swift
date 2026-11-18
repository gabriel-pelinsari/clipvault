import AppKit
import CryptoKit
import Foundation
import Testing
@testable import ClipVault

struct HistoryStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "clipvault-tests-\(UUID().uuidString)")
    let key = SymmetricKey(size: .bits256)
    let source = SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")

    private func makeStore(key: SymmetricKey? = nil) throws -> HistoryStore {
        HistoryStore(storage: try EncryptedStore(directory: directory, key: key ?? self.key))
    }

    @Test func `newest item comes first`() throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 1_000)
        store.add(.text("first"), source: source, now: start)
        store.add(.text("second"), source: source, now: start.addingTimeInterval(1))

        #expect(store.items.map(\.text) == ["second", "first"])
    }

    @Test func `copying the same content again moves it to the top instead of duplicating`() throws {
        let store = try makeStore()
        let start = Date(timeIntervalSince1970: 1_000)
        store.add(.text("a"), source: source, now: start)
        store.add(.text("b"), source: source, now: start.addingTimeInterval(1))
        store.add(.text("a"), source: source, now: start.addingTimeInterval(2))

        #expect(store.items.map(\.text) == ["a", "b"])
    }

    @Test func `max items drops the oldest unpinned items but keeps pinned ones`() throws {
        let store = try makeStore()
        store.limits = .init(maxItems: 2, retention: nil)
        let start = Date(timeIntervalSince1970: 1_000)
        let pinned = try #require(store.add(.text("pinned"), source: source, now: start))
        store.togglePin(pinned.id)
        for index in 1...4 {
            store.add(.text("item \(index)"), source: source, now: start.addingTimeInterval(Double(index)))
        }

        #expect(Set(store.items.compactMap(\.text)) == ["pinned", "item 4", "item 3"])
    }

    @Test func `retention expires old unpinned items`() throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 100_000)
        store.add(.text("old"), source: source, now: now.addingTimeInterval(-7_200))
        let oldPinned = try #require(store.add(.text("old pinned"), source: source, now: now.addingTimeInterval(-7_200)))
        store.togglePin(oldPinned.id)
        store.add(.text("fresh"), source: source, now: now.addingTimeInterval(-60))

        store.limits = .init(maxItems: 100, retention: 3_600)
        store.enforceLimits(now: now)

        #expect(Set(store.items.compactMap(\.text)) == ["old pinned", "fresh"])
    }

    @Test func `history survives a relaunch with the same key`() throws {
        let png = try Self.samplePNG()
        do {
            let store = try makeStore()
            store.add(.text("persisted"), source: source)
            store.add(.image(png: png, width: 4, height: 4), source: source)
        }
        let reloaded = try makeStore()

        #expect(reloaded.items.count == 2)
        let image = try #require(reloaded.items.first { $0.isImage })
        #expect(reloaded.imageData(for: image.id) == png)
        #expect(reloaded.items.contains { $0.text == "persisted" })
    }

    @Test func `history written with another key is discarded`() throws {
        do {
            let store = try makeStore()
            store.add(.image(png: try Self.samplePNG(), width: 4, height: 4), source: source)
        }
        let reloaded = try makeStore(key: SymmetricKey(size: .bits256))

        #expect(reloaded.items.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func `deleting an image removes its file`() throws {
        let store = try makeStore()
        let item = try #require(store.add(.image(png: try Self.samplePNG(), width: 4, height: 4), source: source))
        store.delete(item.id)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["history.v1"])
    }

    @Test func `clearing keeps pinned items when asked`() throws {
        let store = try makeStore()
        let pinned = try #require(store.add(.text("keep"), source: source))
        store.togglePin(pinned.id)
        store.add(.text("drop"), source: source)

        store.clear(keepingPinned: true)
        #expect(store.items.map(\.text) == ["keep"])
        store.clear(keepingPinned: false)
        #expect(store.items.isEmpty)
    }

    @Test func `works in memory without storage`() throws {
        let store = HistoryStore(storage: nil)
        let png = try Self.samplePNG()
        let item = try #require(store.add(.image(png: png, width: 4, height: 4), source: nil))

        #expect(store.imageData(for: item.id) == png)
        #expect(!store.isPersistent)
    }

    static func samplePNG() throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}
