import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    @State private var bridgeInstalled = BridgeInstaller.isInstalled()
    @State private var pendingAction: BridgeInstaller.Action?
    @State private var running = false
    @State private var output: BridgeInstaller.Output?
    @State private var loginStatus = LaunchAtLogin.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Geral") {
                Toggle("Abrir ao iniciar sessão", isOn: launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                if !LaunchAtLogin.isAvailable {
                    Text("Disponível no UsageBar.app instalado pelo build-app.sh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if loginStatus == .requiresApproval {
                    HStack {
                        Text("Aprove o UsageBar nos Itens de Início.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Abrir Ajustes") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Consulta ao servidor") {
                LabeledContent("Última consulta") {
                    Text(store.state.serverCheckedAt.map { Format.ago($0, now: store.now) } ?? "Nenhuma ainda")
                        .foregroundStyle(.secondary)
                }
                Text("A cada 5 min o app roda o /usage do Claude Code, que traz do servidor o uso real da conta, incluindo o da web. A consulta não gasta limite.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = store.serverError {
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                HStack {
                    if store.isCheckingServer { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Atualizar agora") { store.checkServer(force: true) }
                        .disabled(store.isCheckingServer)
                }
            }

            Section("Statusline do Claude Code") {
                LabeledContent("Bridge") {
                    Label(bridgeInstalled ? "Instalado" : "Não instalado",
                          systemImage: bridgeInstalled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(bridgeInstalled ? .green : .secondary)
                }
                Text("O bridge grava os dados de uso que o Claude Code envia à statusline, o que atualiza a barra a cada resposta entre uma consulta e outra. Ele repassa tudo para a sua statusline atual, que continua aparecendo.")
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
        .onAppear {
            bridgeInstalled = BridgeInstaller.isInstalled()
            loginStatus = LaunchAtLogin.status
        }
        .alert(alertTitle, isPresented: isConfirming, presenting: pendingAction) { action in
            Button(action == .install ? "Configurar" : "Remover") { perform(action) }
            Button("Cancelar", role: .cancel) {}
        } message: { action in
            Text(alertMessage(for: action))
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: { enabled in
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                }
                loginStatus = LaunchAtLogin.status
            })
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
