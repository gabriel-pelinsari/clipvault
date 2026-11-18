import SwiftUI

struct HistoryView: View {
    static let size = CGSize(width: 740, height: 470)

    @Bindable var model: HistoryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            banners
            content
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear { isSearchFocused = true }
        .onChange(of: model.focusRequest) { isSearchFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Buscar no histórico", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isSearchFocused)
            Picker("Filtro", selection: $model.filter) {
                ForEach(HistoryViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Trocar filtro (⇥)")
            HeaderButton(
                systemImage: model.settings.isCapturePaused ? "play.fill" : "pause.fill",
                help: model.settings.isCapturePaused ? "Retomar captura" : "Pausar captura"
            ) { model.settings.isCapturePaused.toggle() }
            HeaderButton(systemImage: "gearshape", help: "Ajustes (⌘,)") { model.actions.openSettings() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var banners: some View {
        if model.settings.isCapturePaused {
            Banner(systemImage: "pause.circle.fill", tint: .orange,
                   text: "Captura pausada — novas cópias não estão sendo salvas.",
                   actionTitle: "Retomar") { model.settings.isCapturePaused = false }
        }
        if model.settings.autoPaste, !Paster.canPostEvents {
            Banner(systemImage: "hand.tap.fill", tint: .accentColor,
                   text: "Para colar direto no campo de texto, ative o ClipVault em Acessibilidade.",
                   actionTitle: "Permitir…") {
                model.actions.close()
                Paster.requestAccess()
                Paster.openAccessibilitySettings()
            }
        }
        if !model.store.isPersistent {
            Banner(systemImage: "exclamationmark.triangle.fill", tint: .red,
                   text: "Sem acesso ao Keychain: o histórico fica só na memória e some ao sair.",
                   actionTitle: nil, action: {})
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        let items = model.visibleItems
        if let selected = model.selectedItem {
            HStack(spacing: 0) {
                list(items, selectedID: selected.id)
                    .frame(width: 320)
                Divider()
                PreviewPane(item: selected, model: model)
            }
        } else {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func list(_ items: [ClipItem], selectedID: UUID) -> some View {
        let pinnedCount = items.prefix { $0.isPinned }.count
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if pinnedCount > 0, index == 0 {
                            SectionLabel(title: "Fixados")
                        }
                        if pinnedCount > 0, index == pinnedCount {
                            SectionLabel(title: "Recentes")
                        }
                        ItemRow(
                            item: item,
                            shortcutNumber: index < 9 ? index + 1 : nil,
                            isSelected: item.id == selectedID,
                            thumbnail: item.isImage ? model.store.image(for: item.id) : nil
                        )
                        .id(item.id)
                        .onTapGesture { model.activate(item) }
                        .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.automatic)
            .onChange(of: selectedID) { _, id in
                proxy.scrollTo(id)
            }
        }
    }

    @ViewBuilder private func contextMenu(for item: ClipItem) -> some View {
        Button("Colar") { model.actions.paste(item, true) }
        Button("Só copiar") { model.actions.paste(item, false) }
        Divider()
        Button(item.isPinned ? "Desafixar" : "Fixar") { model.togglePin(item) }
        Button("Apagar", role: .destructive) { model.delete(item) }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if model.filter != .all {
            ContentUnavailableView(
                "Nada em “\(model.filter.rawValue)”",
                systemImage: model.filter == .pinned ? "pin" : "tray",
                description: Text(model.filter == .pinned
                    ? "Fixe itens com ⌘P para mantê-los para sempre."
                    : "Nenhum item deste tipo no histórico.")
            )
        } else {
            ContentUnavailableView(
                "Nada copiado ainda",
                systemImage: "list.clipboard",
                description: Text("Copie um texto ou uma imagem e ele aparece aqui.")
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Label {
                Text("\(model.store.items.count) \(model.store.items.count == 1 ? "item" : "itens")")
            } icon: {
                Image(systemName: model.store.isPersistent ? "lock.fill" : "lock.open")
            }
            .help(model.store.isPersistent ? "Histórico criptografado no disco" : "Histórico apenas na memória")
            Spacer()
            KeyHint(key: "↩", label: model.willPaste ? "Colar" : "Copiar")
            KeyHint(key: "⌘P", label: "Fixar")
            KeyHint(key: "⌘⌫", label: "Apagar")
            KeyHint(key: "esc", label: "Fechar")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Rows

private struct ItemRow: View {
    let item: ClipItem
    let shortcutNumber: Int?
    let isSelected: Bool
    let thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? " " : item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let shortcutNumber {
                Text("⌘\(shortcutNumber)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : isHovered ? Color.primary.opacity(0.05) : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        let time = Formatting.relativeTime(item.lastCopiedAt)
        guard let app = item.sourceAppName else { return time }
        return "\(app) · \(time)"
    }

    @ViewBuilder private var leading: some View {
        if item.isImage {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    }
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        } else if let icon = AppIcons.icon(for: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 26, height: 26)
        } else {
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }
}

// MARK: - Preview

private struct PreviewPane: View {
    let item: ClipItem
    let model: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            details
        }
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case .text(let text):
            ScrollView {
                Text(String(text.prefix(20_000)))
                    .font(.system(size: 12.5, design: Self.looksLikeCode(text) ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
        case .image:
            if let image = model.store.image(for: item.id) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                    .padding(18)
            } else {
                ContentUnavailableView("Imagem indisponível", systemImage: "photo")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                DetailRow(label: "Origem", value: item.sourceAppName ?? "Desconhecida")
                DetailRow(label: "Copiado", value: Formatting.dateTime(item.lastCopiedAt))
                DetailRow(label: "Conteúdo", value: item.sizeDescription)
            }
            HStack(spacing: 8) {
                Button {
                    model.activate(item)
                } label: {
                    Label(model.willPaste ? "Colar" : "Copiar", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut(.defaultAction)
                Button {
                    model.togglePin(item)
                } label: {
                    Label(item.isPinned ? "Desafixar" : "Fixar", systemImage: item.isPinned ? "pin.slash" : "pin")
                }
                Spacer()
                Button(role: .destructive) {
                    model.delete(item)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Apagar (⌘⌫)")
            }
            .controlSize(.small)
        }
        .padding(14)
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let markers = ["{", "};", "=>", "func ", "def ", "const ", "import ", "</", "\t", "    "]
        return text.contains("\n") && markers.contains { text.contains($0) }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11.5))
    }
}

// MARK: - Small pieces

private struct HeaderButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct Banner: View {
    let systemImage: String
    let tint: Color
    let text: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tint.opacity(0.1))
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label)
        }
    }
}
