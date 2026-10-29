import Foundation

/// Mantém os tokens dos históricos do Claude Code em dia, lendo fora da main thread.
@MainActor
final class TokenStore: ObservableObject {
    enum Status: Equatable {
        case loading
        case ready(TokenBuckets)
        case failed(String)
    }

    @Published private(set) var status: Status = .loading
    @Published private(set) var isScanning = false

    /// Intervalo mínimo entre leituras sem `force`.
    static let throttle: TimeInterval = 30

    private let scan: @Sendable (Date) throws -> TokenBuckets
    private var lastRefresh: Date?

    init(scan: @escaping @Sendable (Date) throws -> TokenBuckets = SharedScanner.scan) {
        self.scan = scan
    }

    /// Lê os históricos desde o início do período mais longo exibido, calculado com a janela de 5h atual.
    func refresh(window: UsageWindow?, force: Bool = false) {
        let now = Date()
        guard !isScanning else { return }
        if !force, let lastRefresh, now.timeIntervalSince(lastRefresh) < Self.throttle { return }
        lastRefresh = now
        isScanning = true
        let since = TokenChart.earliestStart(window: window, now: now, calendar: .current)
        let scan = self.scan
        Task {
            let result = await Task.detached { Result { try scan(since) } }.value
            switch result {
            case .success(let buckets): status = .ready(buckets)
            case .failure(let error): status = .failed(error.localizedDescription)
            }
            isScanning = false
        }
    }
}

/// O leitor do app, numa fila serial: o `TranscriptScanner` guarda estado e não pode ser usado de duas threads.
enum SharedScanner {
    private final class Box: @unchecked Sendable {
        let queue = DispatchQueue(label: "UsageBar.TranscriptScanner")
        let scanner = TranscriptScanner()
    }

    private static let box = Box()

    @Sendable static func scan(since: Date) throws -> TokenBuckets {
        try box.queue.sync { try box.scanner.scan(since: since) }
    }
}
