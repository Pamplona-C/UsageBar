import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    @State private var bridgeInstalled = BridgeInstaller.isInstalled()
    @State private var pendingAction: BridgeInstaller.Action?
    @State private var running = false
    @State private var output: BridgeInstaller.Output?

    var body: some View {
        Form {
            Section("Statusline do Claude Code") {
                LabeledContent("Bridge") {
                    Label(bridgeInstalled ? "Instalado" : "Não instalado",
                          systemImage: bridgeInstalled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(bridgeInstalled ? .green : .secondary)
                }
                Text("O bridge grava os dados de uso que o Claude Code envia à statusline e repassa tudo para a sua statusline atual, que continua aparecendo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                    if bridgeInstalled {
                        Button("Remover bridge…") { pendingAction = .uninstall }
                    } else {
                        Button("Configurar statusline…") { pendingAction = .install }
                    }
                }
                .disabled(running)
                if let output {
                    Text(output.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(output.succeeded ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                }
            }

            Section("Dados") {
                LabeledContent("Arquivo observado") {
                    Text(store.fileURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { bridgeInstalled = BridgeInstaller.isInstalled() }
        .alert(alertTitle, isPresented: isConfirming, presenting: pendingAction) { action in
            Button(action == .install ? "Configurar" : "Remover") { perform(action) }
            Button("Cancelar", role: .cancel) {}
        } message: { action in
            Text(alertMessage(for: action))
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }

    private var alertTitle: String {
        pendingAction == .uninstall ? "Remover o bridge?" : "Configurar a statusline?"
    }

    private func alertMessage(for action: BridgeInstaller.Action) -> String {
        switch action {
        case .install:
            return "Um backup do ~/.claude/settings.json será criado (settings.json.bak-…) e o statusLine passará a apontar para o bridge do UsageBar. Sua statusline atual continua aparecendo."
        case .uninstall:
            return "Um backup do ~/.claude/settings.json será criado e o statusLine original será restaurado."
        }
    }

    private func perform(_ action: BridgeInstaller.Action) {
        running = true
        output = nil
        Task {
            let result = await BridgeInstaller.run(action)
            output = result
            running = false
            bridgeInstalled = BridgeInstaller.isInstalled()
            store.reload()
        }
    }
}
