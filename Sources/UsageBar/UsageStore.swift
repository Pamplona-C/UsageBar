import Foundation

/// Mantém o `UsageState` em dia com duas fontes: a consulta ao `/usage` a cada 5 min e o `state.json` do bridge.
///
/// O bridge troca o arquivo com `mv` atômico, o que muda o inode; por isso a observação é feita
/// no diretório, não no arquivo. Um timer de fallback relê o arquivo, dispara a consulta e atualiza o relógio da UI.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState
    /// Relógio da UI: janelas que passaram do reset e "atualizado há X min" dependem dele.
    @Published private(set) var now = Date()
    @Published private(set) var isCheckingServer = false
    /// Erro da última consulta ao servidor; `nil` depois de uma consulta que deu certo.
    @Published private(set) var serverError: UsageReportError?

    let fileURL: URL
    private let defaults: UserDefaults
    private let fetchReport: () async -> Result<RateLimits, UsageReportError>
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pendingReload: DispatchWorkItem?
    private var lastServerAttempt: Date?

    static let fallbackInterval: TimeInterval = 30
    static let serverInterval: TimeInterval = 5 * 60
    /// Intervalo mínimo entre consultas disparadas ao abrir o popover.
    static let serverThrottle: TimeInterval = 60
    private static let cacheKey = "usageState"

    init(fileURL: URL = StateFile.defaultURL, defaults: UserDefaults = .standard,
         fetchReport: @escaping () async -> Result<RateLimits, UsageReportError> = UsageReportClient.fetch) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.fetchReport = fetchReport
        // O cache guarda o melhor valor já visto: o state.json atual pode ter vindo de uma sessão parada.
        state = defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode(UsageState.self, from: $0) } ?? UsageState()
        reload()
        startWatching()
        startTimer()
        checkServer(force: true)
    }

    func reload() {
        now = Date()
        guard let contents = try? StateFile.load(from: fileURL) else { return }
        var next = state
        next.absorb(contents.snapshot, receivedAt: contents.modifiedAt)
        commit(next)
    }

    /// Consulta o `/usage`. Sem `force`, só consulta se a última tentativa tiver mais de `serverThrottle`.
    func checkServer(force: Bool = false) {
        let startedAt = Date()
        guard !isCheckingServer else { return }
        if !force, let lastServerAttempt, startedAt.timeIntervalSince(lastServerAttempt) < Self.serverThrottle {
            return
        }
        lastServerAttempt = startedAt
        isCheckingServer = true
        Task {
            let result = await fetchReport()
            isCheckingServer = false
            now = Date()
            switch result {
            case .success(let limits):
                serverError = nil
                var next = state
                next.applyServerReading(limits, checkedAt: startedAt)
                commit(next)
            case .failure(let error):
                serverError = error
            }
        }
    }

    private func commit(_ next: UsageState) {
        guard next != state else { return }
        state = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let directory = fileURL.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        // Diretório ainda não existe (bridge não instalado): o timer tenta de novo.
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !source.data.isDisjoint(with: [.delete, .rename]) {
                    self.stopWatching()
                }
                self.scheduleReload()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    /// Agrupa os eventos do arquivo temporário e do `mv` numa única leitura.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func startTimer() {
        let timer = Timer(timeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.startWatching()
                self.reload()
                if let last = self.lastServerAttempt, self.now.timeIntervalSince(last) >= Self.serverInterval {
                    self.checkServer(force: true)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
