import SwiftUI

struct CodexUsageContent: View {
    @ObservedObject var store: CodexStore
    @Binding var showConnection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let report = store.report {
                HStack(alignment: .top, spacing: 8) {
                    UsageRing(title: report.primary?.title(fallback: "Janela atual") ?? "Janela atual",
                              window: report.primary?.window, now: store.now)
                    UsageRing(title: report.secondary?.title(fallback: "Outra janela") ?? "Outra janela",
                              window: report.secondary?.window, now: store.now)
                }
                if let checkedAt = store.checkedAt {
                    HStack {
                        if store.now.timeIntervalSince(checkedAt) > UsageState.staleAfter {
                            Label("Dados antigos (> 1h)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        } else {
                            Text(Format.updated(checkedAt, now: store.now)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        refreshButton
                    }
                    .font(.caption)
                }
            } else if store.isChecking && !store.isAwaitingLogin {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Consultando o Codex…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                VStack(spacing: 12) {
                    ProviderIcon(provider: .codex, size: 38)
                        .padding(14)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 17))
                    Text(store.isAwaitingLogin ? "Falta só o login" : "Seu Codex, aqui.")
                        .font(.title3.weight(.semibold))
                    Text(store.isAwaitingLogin
                         ? "Conclua o login e volte para ver seus limites."
                         : "Conecte sua conta do ChatGPT para acompanhar os limites do Codex.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button { showConnection = true } label: {
                        HStack {
                            ProviderIcon(provider: .codex, size: 15)
                            Text(store.isAwaitingLogin ? "Continuar conexão" : "Conectar Codex")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isOpeningLogin)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            if let error = store.error, !error.offersLogin || store.report != nil {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.report == nil {
                    Button("Tentar atualizar novamente") { store.check(force: true) }
                        .font(.caption)
                        .disabled(store.isChecking || !store.isEnabled)
                }
            }
        }
        .onAppear { store.check(force: store.isAwaitingLogin) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.check(force: store.isAwaitingLogin)
        }
    }

    @ViewBuilder private var refreshButton: some View {
        if store.isChecking {
            ProgressView().controlSize(.small)
        } else {
            Button { store.check(force: true) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .help("Atualizar limites do Codex")
                .accessibilityLabel("Atualizar limites do Codex")
        }
    }
}

struct CodexConnectionView: View {
    @ObservedObject var store: CodexStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("UsageBar · Codex").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar conexão")
            }
            Divider()
            if store.report != nil && !store.isAwaitingLogin && !store.isOpeningLogin {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48)).foregroundStyle(.green)
                Text("Codex conectado.").font(.title2.weight(.semibold))
                Text("Agora você pode alternar entre Claude e Codex.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Ver limites do Codex") { dismiss() }.buttonStyle(.borderedProminent)
            } else {
                ProviderIcon(provider: .codex, size: 42).padding(12)
                Text(store.isAwaitingLogin ? "Conclua seu login" : "Conectar Codex")
                    .font(.title2.weight(.semibold))
                Text(store.isAwaitingLogin
                     ? "Continue o login no Terminal e no navegador. Seus limites aparecem aqui assim que a conexão for confirmada."
                     : "Entre com sua conta do ChatGPT. O Codex abre o navegador para você concluir o login.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if store.isAwaitingLogin {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Aguardando sua conexão…").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Já fiz login — atualizar") { store.check(force: true) }
                        .disabled(store.isChecking)
                    Button("Continuar depois") { store.cancelWaiting(); dismiss() }
                        .font(.caption)
                } else {
                    Button { store.connect() } label: {
                        HStack {
                            ProviderIcon(provider: .codex, size: 17)
                            Text(store.isOpeningLogin ? "Abrindo o Terminal…" : "Entrar com ChatGPT")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isOpeningLogin)
                }
                if let error = store.error, !error.offersLogin {
                    Text(error.message).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("O login é gerenciado pelo próprio Codex.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if store.isAwaitingLogin { store.check(force: true) }
        }
    }
}
