import SwiftUI

/// Anel com o percentual livre de uma janela e, embaixo, o nome e quando ela reinicia.
struct UsageRing: View {
    let title: String
    let window: UsageWindow?
    let now: Date

    var body: some View {
        let used = window?.percentage(at: now)
        let free = used.map { max(0, min(100, 100 - $0)) }
        let level = UsageLevel(percentage: used ?? 0)

        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: (free ?? 0) / 100)
                    .stroke(level.color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: free)
                VStack(spacing: 0) {
                    Text(Format.percent(free))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text("livre")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(Format.percent(free)) livre")

            VStack(spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        guard let window else { return "sem dados" }
        guard let resetsAt = window.resetsAt else { return "reset desconhecido" }
        return Format.resetShort(resetsAt, now: now)
    }
}
