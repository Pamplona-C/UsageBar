import Foundation

@MainActor
final class CodexStore: ObservableObject {
    @Published private(set) var report: CodexUsageReport?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var error: CodexUsageError?
    @Published private(set) var now = Date()
    @Published private(set) var isChecking = false
    @Published private(set) var isOpeningLogin = false
    @Published private(set) var isAwaitingLogin = false
    @Published private(set) var isEnabled: Bool

    private struct Cache: Codable { var report: CodexUsageReport; var checkedAt: Date }
    private let defaults: UserDefaults
    private let fetch: () async -> Result<CodexUsageReport, CodexUsageError>
    private let openLogin: () async -> CodexUsageError?
    private var lastAttempt: Date?
    private var timer: Timer?
    private var generation = 0
    private static let cacheKey = "codexUsageState"

    init(defaults: UserDefaults = .standard,
         fetch: @escaping () async -> Result<CodexUsageReport, CodexUsageError> = CodexUsageClient.fetch,
         openLogin: @escaping () async -> CodexUsageError? = CodexLogin.open,
         startAutomatically: Bool = true) {
        self.defaults = defaults
        self.fetch = fetch
        self.openLogin = openLogin
        isEnabled = defaults.object(forKey: "codexEnabled") as? Bool ?? true
        if isEnabled, let data = defaults.data(forKey: Self.cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            report = cache.report
            checkedAt = cache.checkedAt
        }
        if startAutomatically {
            let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            check(force: true)
        }
    }

    var needsConnection: Bool { !isEnabled || error?.offersLogin == true || (report == nil && !isChecking) }

    func check(force: Bool = false) {
        guard isEnabled, !isChecking else { return }
        let startedAt = Date()
        if !force, let lastAttempt, startedAt.timeIntervalSince(lastAttempt) < 60 { return }
        lastAttempt = startedAt
        let generation = self.generation
        isChecking = true
        Task {
            let result = await fetch()
            // Desconectar durante a consulta não pode repovoar o cache ou reativar a conta.
            guard generation == self.generation else { return }
            isChecking = false
            now = Date()
            switch result {
            case .success(let reading):
                report = reading
                checkedAt = startedAt
                error = nil
                isAwaitingLogin = false
                if let data = try? JSONEncoder().encode(Cache(report: reading, checkedAt: startedAt)) {
                    defaults.set(data, forKey: Self.cacheKey)
                }
            case .failure(let failure):
                error = failure
                if failure.offersLogin { clearReading() }
            }
        }
    }

    func connect() {
        guard !isOpeningLogin, !isAwaitingLogin else { return }
        isEnabled = true
        defaults.set(true, forKey: "codexEnabled")
        isOpeningLogin = true
        let generation = self.generation
        Task {
            let failure = await openLogin()
            guard generation == self.generation else { return }
            isOpeningLogin = false
            if let failure { error = failure }
            else { isAwaitingLogin = true }
        }
    }

    /// Para de acompanhar esta conta no UsageBar; não encerra o login compartilhado do CLI.
    func disconnect() {
        generation += 1
        isEnabled = false
        defaults.set(false, forKey: "codexEnabled")
        isChecking = false
        isAwaitingLogin = false
        isOpeningLogin = false
        error = nil
        clearReading()
    }

    func cancelWaiting() { isAwaitingLogin = false }

    private func clearReading() {
        report = nil
        checkedAt = nil
        defaults.removeObject(forKey: Self.cacheKey)
    }

    private func tick() {
        now = Date()
        let interval: TimeInterval = isAwaitingLogin ? 10 : 5 * 60
        if lastAttempt.map({ now.timeIntervalSince($0) >= interval }) ?? true { check(force: true) }
    }
}
