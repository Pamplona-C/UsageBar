import SwiftUI

/// Label da barra de menu: percentual da janela de 5h e bolinha com a cor do limite semanal.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let state = store.state
        let fiveHour = state.fiveHour?.percentage(at: store.now)
        let sevenDay = state.sevenDay?.percentage(at: store.now)
        let dotColor = sevenDay.map { UsageLevel(percentage: $0).nsColor } ?? .tertiaryLabelColor

        HStack(spacing: 4) {
            Image(nsImage: StatusDot.image(color: dotColor))
            Text(Format.percent(fiveHour))
                .monospacedDigit()
        }
    }
}
