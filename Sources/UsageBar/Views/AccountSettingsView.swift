import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var accounts: UsageAccounts
    @State private var page = "accounts"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Configurações", selection: $page) {
                Text("Contas").tag("accounts")
                Text("Geral e Claude").tag("general")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if page == "accounts" {
                ConnectionsSettingsView(accounts: accounts, codex: accounts.codex)
            } else {
                SettingsView(store: accounts.claude)
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ConnectionsSettingsView: View {
    @ObservedObject var accounts: UsageAccounts
    @ObservedObject var codex: CodexStore
    @State private var showConnection = false
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section("Popover") {
                Picker("Serviço selecionado", selection: $accounts.selected) {
                    ForEach(UsageProvider.allCases) { provider in
                        Text(provider.name).tag(provider)
                    }
                }
                Text("A barra de menu mostra os percentuais dos dois serviços. Os símbolos no popover alternam os detalhes de cada um.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Conexões") {
                HStack(spacing: 10) {
                    ProviderIcon(provider: .claude, size: 25)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Claude Code").fontWeight(.medium)
                        Text("Usa o login do Claude Code neste Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    LoginButton()
                        .labelStyle(.iconOnly)
                }
                HStack(spacing: 10) {
                    ProviderIcon(provider: .codex, size: 25)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Codex").fontWeight(.medium)
                        Text(codex.report != nil ? "Conectado com ChatGPT" : "Conecte sua conta do ChatGPT")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if codex.report != nil || codex.isAwaitingLogin {
                        Button("Desconectar…") { confirmDisconnect = true }
                    } else {
                        Button("Conectar…") { showConnection = true }
                    }
                }
            }
            Section("Limites do Codex") {
                LabeledContent("Última consulta") {
                    Text(codex.checkedAt.map { Format.ago($0, now: codex.now) } ?? "Nenhuma ainda")
                        .foregroundStyle(.secondary)
                }
                Text("O UsageBar consulta os limites pelo próprio Codex a cada 5 min. O login fica sob responsabilidade do Codex.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = codex.error {
                    Text(error.message).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if codex.isChecking { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Atualizar agora") { codex.check(force: true) }
                        .disabled(codex.isChecking || !codex.isEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { codex.check() }
        .sheet(isPresented: $showConnection) { CodexConnectionView(store: codex) }
        .confirmationDialog("Desconectar o Codex do UsageBar?", isPresented: $confirmDisconnect) {
            Button("Desconectar do UsageBar") { codex.disconnect() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O UsageBar para de acompanhar esta conta e remove seu cache local. O login do Codex no Terminal continua disponível.")
        }
    }
}
