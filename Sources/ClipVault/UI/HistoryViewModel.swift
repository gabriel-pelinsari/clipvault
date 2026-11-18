import Foundation
import Observation

/// State and actions for the history panel, independent of how it's drawn.
@Observable
final class HistoryViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tudo"
        case text = "Texto"
        case images = "Imagens"
        case pinned = "Fixados"

        var id: Self { self }
    }

    struct Actions {
        var paste: (ClipItem, _ autoPaste: Bool) -> Void = { _, _ in }
        var close: () -> Void = {}
        var openSettings: () -> Void = {}
    }

    let store: HistoryStore
    let settings: AppSettings
    @ObservationIgnored var actions = Actions()

    var query = "" {
        didSet { if query != oldValue { selectFirst() } }
    }
    var filter: Filter = .all {
        didSet { if filter != oldValue { selectFirst() } }
    }
    var selectedID: UUID?
    /// Bumped each time the panel opens so the view refocuses the search field.
    private(set) var focusRequest = 0

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    /// Pinned items first, then the rest, both most recent first.
    var visibleItems: [ClipItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = store.items.filter { item in
            let passesFilter = switch filter {
            case .all: true
            case .text: !item.isImage
            case .images: item.isImage
            case .pinned: item.isPinned
            }
            return passesFilter && (query.isEmpty || item.matches(query))
        }
        return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.first { $0.id == selectedID } ?? items.first
    }

    var willPaste: Bool { settings.autoPaste && Paster.canPostEvents }

    func prepareForPresentation() {
        query = ""
        filter = .all
        selectFirst()
        focusRequest += 1
    }

    func moveSelection(by delta: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedItem?.id } ?? 0
        selectedID = items[min(max(current + delta, 0), items.count - 1)].id
    }

    func activateSelected(paste: Bool = true) {
        guard let item = selectedItem else { return }
        actions.paste(item, paste)
    }

    func activate(_ item: ClipItem) {
        actions.paste(item, true)
    }

    func activate(at index: Int) {
        let items = visibleItems
        guard items.indices.contains(index) else { return }
        actions.paste(items[index], true)
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        togglePin(item)
    }

    func togglePin(_ item: ClipItem) {
        store.togglePin(item.id)
        selectedID = item.id
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func delete(_ item: ClipItem) {
        let items = visibleItems
        let index = items.firstIndex { $0.id == item.id } ?? 0
        store.delete(item.id)
        let remaining = visibleItems
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    func cycleFilter(forward: Bool) {
        let all = Filter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }

    private func selectFirst() {
        selectedID = visibleItems.first?.id
    }
}
