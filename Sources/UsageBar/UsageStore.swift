import Foundation

/// Mantém o `UsageState` em dia observando o `state.json` gravado pelo bridge.
///
/// O bridge troca o arquivo com `mv` atômico, o que muda o inode; por isso a observação é feita
/// no diretório, não no arquivo. Um timer de fallback relê o arquivo e atualiza o relógio da UI.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState
    /// Relógio da UI: janelas que passaram do reset e "atualizado há X min" dependem dele.
    @Published private(set) var now = Date()

    let fileURL: URL
    private let defaults: UserDefaults
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pendingReload: DispatchWorkItem?

    static let fallbackInterval: TimeInterval = 30
    private static let cacheKey = "usageState"

    init(fileURL: URL = StateFile.defaultURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        // O cache guarda o melhor valor já visto: o state.json atual pode ter vindo de uma sessão parada.
        state = defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode(UsageState.self, from: $0) } ?? UsageState()
        reload()
        startWatching()
        startTimer()
    }

    func reload() {
        now = Date()
        guard let contents = try? StateFile.load(from: fileURL) else { return }
        var next = state
        next.absorb(contents.snapshot, receivedAt: contents.modifiedAt)
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
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
