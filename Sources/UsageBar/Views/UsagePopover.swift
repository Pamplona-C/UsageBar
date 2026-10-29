import SwiftUI

/// Conteúdo que abre ao clicar no label da barra de menu.
struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let state = store.state
        let now = store.now

        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Code")
                .font(.headline)

            if state.hasData {
                HStack(alignment: .top, spacing: 8) {
                    UsageRing(title: "5 horas", window: state.fiveHour, now: now)
                    UsageRing(title: "Semana", window: state.sevenDay, now: now)
                }
            } else if store.isCheckingServer {
                Label("Consultando o servidor…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Sem dados ainda — use o Claude Code uma vez", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                    Text("Se ainda não configurou, abra Configurações → Configurar statusline.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            TokenCard(tokens: store.tokens, window: state.fiveHour, now: now)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let updatedAt = state.updatedAt {
                    if state.isStale(at: now) {
                        Label("Dados antigos (> 1h) · \(Format.updated(updatedAt, now: now).lowercased())",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text(Format.updated(updatedAt, now: now))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if store.isCheckingServer {
                    ProgressView().controlSize(.small)
                } else {
                    Button { store.checkServer(force: true) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Atualizar: consultar o uso no servidor")
                    .accessibilityLabel("Atualizar")
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let error = store.serverError {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Configurações") {
                    NSApp.activate()
                    openSettings()
                }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
        }
        .font(.callout)
        .padding(16)
        .frame(width: 300)
        .onAppear {
            store.checkServer()
            store.tokens.refresh(window: state.fiveHour, force: true)
        }
    }
}
