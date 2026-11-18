import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: HistoryStore

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("Geral", systemImage: "gearshape") }
            ShortcutSettings(settings: settings)
                .tabItem { Label("Atalhos", systemImage: "command") }
            PrivacySettings(settings: settings, store: store)
                .tabItem { Label("Privacidade", systemImage: "lock.shield") }
            AboutView()
                .tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 500)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var canPaste = Paster.canPostEvents

    var body: some View {
        Form {
            Section {
                Toggle("Abrir ao iniciar sessão", isOn: launchAtLogin)
                if loginStatus == .requiresApproval {
                    Text("Aprove o ClipVault em Ajustes do Sistema › Geral › Itens de Início.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Colar automaticamente ao escolher um item", isOn: $settings.autoPaste)
                if settings.autoPaste, !canPaste {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Falta a permissão de Acessibilidade", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Permitir…") {
                            Paster.requestAccess()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("Colar")
            } footer: {
                Text(canPaste || !settings.autoPaste
                    ? "Ao escolher um item ele é colado direto no app em que você estava. ⇧↩ só copia."
                    : "Sem a permissão, o item é copiado e você cola com ⌘V. Ative “ClipVault” em Ajustes do Sistema › Privacidade e Segurança › Acessibilidade.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Histórico") {
                Picker("Guardar no máximo", selection: $settings.maxItems) {
                    ForEach(AppSettings.maxItemsOptions, id: \.self) { Text("\($0) itens").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // Permission is granted in System Settings; keep the UI in sync while visible.
            while !Task.isCancelled {
                canPaste = Paster.canPostEvents
                loginStatus = SMAppService.mainApp.status
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding {
            loginStatus == .enabled || loginStatus == .requiresApproval
        } set: { enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginError = nil
            } catch {
                loginError = "Não foi possível alterar: \(error.localizedDescription)"
            }
            loginStatus = SMAppService.mainApp.status
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @Bindable var settings: AppSettings
    private let hotKeys = HotKeyCenter.shared

    var body: some View {
        Form {
            Section {
                shortcutRow("Abrir histórico", combo: $settings.openHistoryShortcut, action: .openHistory)
                shortcutRow("Pausar / retomar captura", combo: $settings.togglePauseShortcut, action: .togglePause)
            } header: {
                Text("Atalhos globais")
            } footer: {
                Text("Funcionam em qualquer app. Clique no atalho e pressione a nova combinação.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("No painel do histórico") {
                LabeledContent("Navegar", value: "↑ ↓")
                LabeledContent("Colar o item selecionado", value: "↩")
                LabeledContent("Só copiar, sem colar", value: "⇧↩")
                LabeledContent("Colar o item 1 a 9", value: "⌘1 … ⌘9")
                LabeledContent("Fixar / desafixar", value: "⌘P")
                LabeledContent("Apagar item", value: "⌘⌫")
                LabeledContent("Trocar filtro", value: "⇥")
                LabeledContent("Limpar busca / fechar", value: "esc")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, combo: Binding<KeyCombo?>, action: HotKeyCenter.Action) -> some View {
        LabeledContent {
            ShortcutRecorder(combo: combo)
        } label: {
            Text(title)
            if hotKeys.conflicts.contains(action) {
                Text("Em uso por outro app — escolha outra combinação.")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Bindable var settings: AppSettings
    let store: HistoryStore
    @State private var pendingClear: ClearScope?

    private enum ClearScope: Identifiable {
        case unpinned, everything
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Pausar captura", isOn: $settings.isCapturePaused)
                Picker("Apagar itens após", selection: $settings.retention) {
                    ForEach(Retention.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Itens fixados nunca expiram.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Proteções sempre ativas") {
                Label("Histórico criptografado com AES-256-GCM; a chave fica no seu Keychain", systemImage: "lock.fill")
                Label("Senhas que gerenciadores marcam como sensíveis nunca são salvas", systemImage: "key.fill")
                Label("Roda em sandbox, sem nenhum acesso à internet", systemImage: "network.slash")
            }
            .foregroundStyle(.secondary)

            Section {
                ForEach(settings.excludedApps) { app in
                    HStack {
                        if let icon = AppIcons.icon(for: app.bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app").frame(width: 18, height: 18)
                        }
                        Text(app.name)
                        Spacer()
                        Button {
                            settings.excludedApps.removeAll { $0.id == app.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Voltar a registrar cópias deste app")
                    }
                }
                Menu("Adicionar app aberto…") {
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button(app.name) { settings.excludedApps.append(app) }
                    }
                }
                .fixedSize()
            } header: {
                Text("Ignorar cópias feitas nestes apps")
            }

            Section {
                HStack {
                    Button("Limpar histórico…") { pendingClear = .unpinned }
                    Spacer()
                    Button("Apagar tudo, inclusive fixados…", role: .destructive) { pendingClear = .everything }
                }
            }
        }
        .formStyle(.grouped)
        .alert(item: $pendingClear) { scope in
            Alert(
                title: Text(scope == .unpinned ? "Limpar o histórico?" : "Apagar todo o histórico?"),
                message: Text(scope == .unpinned
                    ? "Os itens não fixados serão apagados. Isso não pode ser desfeito."
                    : "Todos os itens, inclusive os fixados, serão apagados. Isso não pode ser desfeito."),
                primaryButton: .destructive(Text("Apagar")) { store.clear(keepingPinned: scope == .unpinned) },
                secondaryButton: .cancel(Text("Cancelar"))
            )
        }
    }

    private var runningApps: [ExcludedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> ExcludedApp? in
                guard let id = app.bundleIdentifier, id != AppInfo.bundleID, !settings.isExcluded(bundleID: id)
                else { return nil }
                return ExcludedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("ClipVault").font(.title2.weight(.semibold))
            Text("Versão \(AppInfo.version)").foregroundStyle(.secondary)
            Text("Histórico de clipboard privado, criptografado e local.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Link("Código-fonte no GitHub", destination: AppInfo.repositoryURL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Window

final class SettingsWindowController {
    private var window: NSWindow?
    private let makeView: () -> SettingsView

    init(makeView: @escaping () -> SettingsView) {
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
            window.title = "Ajustes do ClipVault"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
