import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a key combination to set a global shortcut.
/// Esc cancels; ⌫ clears the shortcut.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(size: 13, weight: isRecording ? .regular : .medium, design: .rounded))
                    .foregroundStyle(isRecording ? Color.accentColor : combo == nil ? .secondary : .primary)
                    .frame(minWidth: 150)
            }
            .help(isRecording ? "Esc cancela · ⌫ remove o atalho" : "Clique para gravar um novo atalho")
            if combo != nil, !isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remover atalho")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return rejected ? "Use ⌘, ⌥ ou ⌃…" : "Pressione o atalho…" }
        return combo?.displayString ?? "Nenhum"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        HotKeyCenter.shared.suspend()
        rejected = false
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyCenter.shared.resume()
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        switch Int(event.keyCode) {
        case kVK_Escape where modifiers.isEmpty:
            stopRecording()
        case kVK_Delete where modifiers.isEmpty, kVK_ForwardDelete where modifiers.isEmpty:
            combo = nil
            stopRecording()
        default:
            let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            guard candidate.isValidGlobalShortcut else {
                rejected = true
                NSSound.beep()
                return
            }
            combo = candidate
            stopRecording()
        }
    }
}
