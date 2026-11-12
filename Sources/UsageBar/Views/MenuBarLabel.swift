import SwiftUI

struct AccountMenuBarLabel: View {
    @ObservedObject private var claude: UsageStore
    @ObservedObject private var codex: CodexStore
    @Environment(\.colorScheme) private var colorScheme

    init(accounts: UsageAccounts) {
        claude = accounts.claude
        codex = accounts.codex
    }

    var body: some View {
        Group {
            if let image = renderedImage {
                Image(nsImage: image)
                    .renderingMode(.original)
            } else {
                Text("\(Format.percent(claudePercentage)) | \(Format.percent(codexPercentage))")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(summary)
        .help(summary)
    }

    private var claudePercentage: Double? { claude.state.fiveHour?.percentage(at: claude.now) }
    private var codexPercentage: Double? { codex.report?.primary?.window.percentage(at: codex.now) }

    private var summary: String {
        let claudeText = claudePercentage.map { "\(Format.percent($0)) usado" } ?? "sem dados"
        let codexText = codexPercentage.map { "\(Format.percent($0)) usado" } ?? "sem dados"
        return "Claude Code: \(claudeText). Codex: \(codexText)."
    }

    // MenuBarExtra extrai só um Text e um Image de um label composto. Renderiza o conjunto
    // primeiro, para que os dois símbolos e percentuais cheguem inteiros ao NSStatusBarButton.
    private var renderedImage: NSImage? {
        let renderer = ImageRenderer(content: content
            .font(.system(size: 13))
            .environment(\.colorScheme, colorScheme)
            .fixedSize())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }

    private var content: some View {
        HStack(spacing: 8) {
            ProviderMenuBarValue(provider: .claude,
                                 primary: claudePercentage,
                                 secondary: claude.state.sevenDay?.percentage(at: claude.now),
                                 windowTitle: "5 horas")
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 12)
                .accessibilityHidden(true)
            ProviderMenuBarValue(provider: .codex,
                                 primary: codexPercentage,
                                 secondary: codex.report?.secondary?.window.percentage(at: codex.now),
                                 windowTitle: codex.report?.primary?.title(fallback: "janela atual") ?? "janela atual")
        }
    }
}

/// Os dois serviços ficam sempre visíveis, mesmo quando um deles ainda não tem dados.
/// Cada bolinha conserva o indicador de cor da segunda janela daquele serviço.
private struct ProviderMenuBarValue: View {
    let provider: UsageProvider
    let primary: Double?
    let secondary: Double?
    let windowTitle: String

    var body: some View {
        let dotColor = secondary.map { UsageLevel(percentage: $0).nsColor } ?? .tertiaryLabelColor

        HStack(spacing: 4) {
            ProviderIcon(provider: provider, size: 14)
            Image(nsImage: StatusDot.image(color: dotColor))
            Text(Format.percent(primary))
                .monospacedDigit()
        }
        .help(summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        guard let primary else { return "\(provider.name): sem dados disponíveis." }
        let other = secondary.map { " Outra janela: \(Format.percent($0)) usado." } ?? ""
        return "\(provider.name): \(Format.percent(primary)) usado em \(windowTitle).\(other)"
    }
}
