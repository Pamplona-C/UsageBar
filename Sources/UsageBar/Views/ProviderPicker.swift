import SwiftUI

/// Proposta C aprovada: os símbolos são atalhos para os dois serviços.
struct ProviderPicker: View {
    @ObservedObject var accounts: UsageAccounts
    @ObservedObject var codex: CodexStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(UsageProvider.allCases) { provider in
                let selected = accounts.selected == provider
                Button { accounts.selected = provider } label: {
                    ProviderIcon(provider: provider, size: 21)
                        .frame(width: 36, height: 36)
                        .background(selected ? Color.green.opacity(0.1) : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(selected ? Color.green.opacity(0.7) : Color.primary.opacity(0.1))
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if provider == .codex && codex.needsConnection {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .primary)
                                    .offset(x: 3, y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(provider == .codex && codex.needsConnection ? "Conectar Codex" : "Ver limites do \(provider.name)")
            }
            Spacer()
            Text(accounts.selected.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct UsagePopover: View {
    @ObservedObject var accounts: UsageAccounts
    @ObservedObject private var codex: CodexStore
    @Environment(\.openSettings) private var openSettings
    @State private var showConnection = false

    init(accounts: UsageAccounts) {
        self.accounts = accounts
        codex = accounts.codex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("UsageBar").font(.headline)
            ProviderPicker(accounts: accounts, codex: codex)
            Divider()
            Group {
                switch accounts.selected {
                case .claude: ClaudeUsageContent(store: accounts.claude)
                case .codex: CodexUsageContent(store: codex, showConnection: $showConnection)
                }
            }
            .id(accounts.selected)

            if accounts.selected == .claude && codex.needsConnection {
                Button {
                    accounts.selected = .codex
                    showConnection = true
                } label: {
                    HStack {
                        ProviderIcon(provider: .codex, size: 15)
                        Text("Conectar Codex")
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Label("Configurações", systemImage: "gearshape")
                }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 300)
        .sheet(isPresented: $showConnection) { CodexConnectionView(store: codex) }
    }
}
