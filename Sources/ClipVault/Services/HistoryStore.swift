import AppKit
import Observation
import os

/// The clipboard history: ordered items plus their encrypted persistence.
///
/// Without `storage` (for example when the Keychain is unavailable) the history
/// lives in memory only and nothing is written to disk.
@Observable
final class HistoryStore {
    nonisolated struct Limits: Equatable, Sendable {
        var maxItems: Int
        var retention: TimeInterval?
    }

    /// Most recently copied first.
    private(set) var items: [ClipItem] = []

    @ObservationIgnored var limits = Limits(maxItems: 200, retention: nil)
    @ObservationIgnored private let storage: EncryptedStore?
    @ObservationIgnored private var volatileImages: [UUID: Data] = [:]
    @ObservationIgnored private let imageCache = NSCache<NSUUID, NSImage>()
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.bundleID, category: "history")

    var isPersistent: Bool { storage != nil }

    init(storage: EncryptedStore?) {
        self.storage = storage
        imageCache.countLimit = 80
        load()
    }

    // MARK: - Mutations

    @discardableResult
    func add(_ captured: CapturedContent, source: SourceApp?, now: Date = .now) -> ClipItem? {
        let digest = captured.digest
        if let index = items.firstIndex(where: { $0.digest == digest }) {
            items[index].lastCopiedAt = now
            if let source {
                items[index].sourceAppName = source.name
                items[index].sourceBundleID = source.bundleID
            }
            let item = items[index]
            sortAndSave()
            return item
        }

        let id = UUID()
        let content: ClipItem.Content
        switch captured {
        case .text(let text):
            content = .text(text)
        case .image(let png, let width, let height):
            do {
                try storeImage(png, for: id)
            } catch {
                log.error("Could not store image: \(String(describing: error), privacy: .public)")
                return nil
            }
            content = .image(width: width, height: height, byteCount: png.count)
        }

        let item = ClipItem(
            id: id, content: content, digest: digest, createdAt: now, lastCopiedAt: now,
            isPinned: false, sourceAppName: source?.name, sourceBundleID: source?.bundleID
        )
        items.insert(item, at: 0)
        if !enforceLimits(now: now) { save() }
        return item
    }

    func markUsed(_ id: UUID, now: Date = .now) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].lastCopiedAt = now
        sortAndSave()
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    func delete(_ id: UUID) {
        remove(ids: [id])
    }

    func clear(keepingPinned: Bool) {
        remove(ids: Set(items.filter { !keepingPinned || !$0.isPinned }.map(\.id)))
    }

    /// Drops expired and overflowing unpinned items. Pinned items are never removed.
    /// Returns whether anything was removed (and therefore saved).
    @discardableResult
    func enforceLimits(now: Date = .now) -> Bool {
        var doomed = Set<UUID>()
        if let retention = limits.retention {
            let cutoff = now.addingTimeInterval(-retention)
            doomed.formUnion(items.filter { !$0.isPinned && $0.lastCopiedAt < cutoff }.map(\.id))
        }
        let keptUnpinned = items.filter { !$0.isPinned && !doomed.contains($0.id) }
        if keptUnpinned.count > limits.maxItems {
            doomed.formUnion(keptUnpinned[limits.maxItems...].map(\.id))
        }
        guard !doomed.isEmpty else { return false }
        remove(ids: doomed)
        return true
    }

    // MARK: - Images

    func imageData(for id: UUID) -> Data? {
        guard let storage else { return volatileImages[id] }
        do {
            return try storage.read(named: Self.imageFileName(id))
        } catch {
            log.error("Could not read image: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func image(for id: UUID) -> NSImage? {
        if let cached = imageCache.object(forKey: id as NSUUID) { return cached }
        guard let data = imageData(for: id), let image = NSImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: id as NSUUID)
        return image
    }

    private func storeImage(_ png: Data, for id: UUID) throws {
        guard let storage else {
            volatileImages[id] = png
            return
        }
        try storage.write(png, named: Self.imageFileName(id))
    }

    // MARK: - Persistence

    private static let indexFileName = "history.v1"

    private static func imageFileName(_ id: UUID) -> String { "image-\(id.uuidString).v1" }

    private func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for item in items where ids.contains(item.id) && item.isImage {
            imageCache.removeObject(forKey: item.id as NSUUID)
            volatileImages[item.id] = nil
            storage?.delete(named: Self.imageFileName(item.id))
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    private func sortAndSave() {
        items.sort { $0.lastCopiedAt > $1.lastCopiedAt }
        save()
    }

    private func save() {
        guard let storage else { return }
        do {
            try storage.write(JSONEncoder().encode(items), named: Self.indexFileName)
        } catch {
            log.error("Could not save history: \(String(describing: error), privacy: .public)")
        }
    }

    private func load() {
        guard let storage else { return }
        do {
            guard let data = try storage.read(named: Self.indexFileName) else { return }
            items = try JSONDecoder().decode([ClipItem].self, from: data)
                .sorted { $0.lastCopiedAt > $1.lastCopiedAt }
            removeOrphanedImages(in: storage)
        } catch {
            // The index can't be authenticated with this key (key rotated or file tampered
            // with), so its contents are unrecoverable. Start over with an empty history.
            log.error("Discarding unreadable history: \(String(describing: error), privacy: .public)")
            storage.deleteAll()
            items = []
        }
    }

    private func removeOrphanedImages(in storage: EncryptedStore) {
        let expected = Set(items.filter(\.isImage).map { Self.imageFileName($0.id) })
        for name in storage.fileNames() where name != Self.indexFileName && !expected.contains(name) {
            storage.delete(named: name)
        }
    }
}
