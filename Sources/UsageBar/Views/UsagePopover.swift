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
                WindowRow(title: "Janela de 5h", window: state.fiveHour, now: now)
                WindowRow(title: "Semanal", window: state.sevenDay, now: now)
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

            Divider()

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
        .frame(width: 280)
        .onAppear { store.checkServer() }
    }
}

private struct WindowRow: View {
    let title: String
    let window: UsageWindow?
    let now: Date

    var body: some View {
        let percentage = window?.percentage(at: now)
        let level = UsageLevel(percentage: percentage ?? 0)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(Format.percent(percentage))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            UsageBarView(fraction: (percentage ?? 0) / 100, color: level.color)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        guard let window else { return "Sem dados desta janela" }
        if window.hasReset(at: now) { return "Janela reiniciada" }
        guard let resetsAt = window.resetsAt else { return "Horário de reset desconhecido" }
        return "Reinicia \(Format.reset(resetsAt, now: now))"
    }
}

private struct UsageBarView: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}
