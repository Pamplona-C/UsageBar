import Foundation

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var name: String { self == .claude ? "Claude Code" : "Codex" }
}

/// Cada serviço mantém suas leituras e seu cache; a seleção muda os detalhes do popover.
@MainActor
final class UsageAccounts: ObservableObject {
    @Published var selected: UsageProvider {
        didSet { defaults.set(selected.rawValue, forKey: "selectedProvider") }
    }
    let claude: UsageStore
    let codex: CodexStore
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, claude: UsageStore? = nil, codex: CodexStore? = nil) {
        self.defaults = defaults
        self.claude = claude ?? UsageStore()
        self.codex = codex ?? CodexStore()
        selected = defaults.string(forKey: "selectedProvider").flatMap(UsageProvider.init(rawValue:)) ?? .claude
    }
}
