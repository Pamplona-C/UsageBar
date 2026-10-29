import Charts
import SwiftUI

/// Card com os tokens dos históricos locais: total e escritos, e as barras dos modos 5h e Semana.
struct TokenCard: View {
    @ObservedObject var tokens: TokenStore
    let window: UsageWindow?
    let now: Date

    @AppStorage("tokenRange") private var range: TokenRange = .fiveHour
    @State private var selectedLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tokens")
                    .font(.callout.weight(.semibold))
                Spacer()
                Picker("Período", selection: $range) {
                    Text("5h").tag(TokenRange.fiveHour)
                    Text("Semana").tag(TokenRange.week)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch tokens.status {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .failed(let reason):
                Label("Tokens indisponíveis", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(reason)
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .ready(let buckets):
                content(data(buckets))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .help("Tokens só do Claude Code neste Mac. O percentual dos anéis vem do servidor e inclui o uso na web e em outros computadores.")
    }

    private func data(_ buckets: TokenBuckets) -> TokenChartData {
        switch range {
        case .fiveHour: return TokenChart.fiveHour(window: window, now: now, buckets: buckets)
        case .week: return TokenChart.week(now: now, calendar: .current, buckets: buckets)
        }
    }

    @ViewBuilder
    private func content(_ data: TokenChartData) -> some View {
        // Barra futura não tem dado: o mouse sobre ela não troca os números.
        let selected = data.bars.first { label($0) == selectedLabel && !$0.isFuture }
        let shown = selected?.count ?? data.total

        HStack(alignment: .firstTextBaseline) {
            figure(Format.tokens(shown.total), "total")
            Spacer()
            figure(Format.tokens(shown.written), "escritos")
        }

        if data.total.total == 0 {
            Text("Nenhum uso do Claude Code neste período")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64)
        } else {
            chart(data)
        }

        Text(footnote(data, selected: selected))
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("Só o Claude Code deste Mac")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chart(_ data: TokenChartData) -> some View {
        // Barras futuras com uma altura mínima, para o período inteiro aparecer.
        let peak = max(data.bars.map(\.count.written).max() ?? 0, 1)
        return Chart(data.bars) { bar in
            BarMark(x: .value("Período", label(bar)),
                    y: .value("Escritos", bar.isFuture ? Double(peak) * 0.04 : Double(bar.count.written)))
                .foregroundStyle(color(bar))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .annotation(position: .top, spacing: 2) {
                    if bar.isCurrent && range == .fiveHour && !data.isRolling {
                        Text("agora").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis(range == .week ? .automatic : .hidden)
        // Hover explícito: o `chartXSelection` do macOS pode exigir clique e arraste.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            selectedLabel = proxy.value(atX: location.x - geometry[plot].origin.x, as: String.self)
                        case .ended:
                            selectedLabel = nil
                        }
                    }
            }
        }
        .frame(height: 72)
    }

    private func color(_ bar: TokenBar) -> AnyShapeStyle {
        if bar.isFuture { return AnyShapeStyle(.quaternary) }
        let green = UsageLevel.normal.color
        if selectedLabel == label(bar) { return AnyShapeStyle(green) }
        return AnyShapeStyle(bar.isCurrent ? green : green.opacity(0.6))
    }

    /// Rótulo de cada barra: "09:20" no modo 5h, "seg" no modo Semana.
    private func label(_ bar: TokenBar) -> String {
        switch range {
        case .fiveHour: return Self.time.string(from: bar.start)
        case .week: return Self.weekday.string(from: bar.start).replacingOccurrences(of: ".", with: "")
        }
    }

    private func footnote(_ data: TokenChartData, selected: TokenBar?) -> String {
        if let selected {
            switch range {
            case .fiveHour:
                return "\(Self.time.string(from: selected.start))–\(Self.time.string(from: selected.end))"
            case .week:
                return Self.day.string(from: selected.start)
            }
        }
        switch range {
        case .fiveHour:
            if data.isRolling { return "últimas 5h · desde \(Self.time.string(from: data.periodStart))" }
            let reset = data.bars.last.map { Self.time.string(from: $0.end) } ?? ""
            return "desde \(Self.time.string(from: data.periodStart)) · reset \(reset)"
        case .week:
            return "desde seg 00:00"
        }
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = format
        return formatter
    }

    private static let time = formatter("HH:mm")
    private static let weekday = formatter("EEE")
    private static let day = formatter("EEEE, dd/MM")
}
