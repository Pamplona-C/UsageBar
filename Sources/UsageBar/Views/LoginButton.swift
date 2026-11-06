import SwiftUI

/// Botão que abre o Terminal com `claude auth login`. Aparece quando a consulta falhou por falta de login.
struct LoginButton: View {
    @State private var isOpening = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isOpening = true
                failure = nil
                Task {
                    failure = await ClaudeLogin.open()?.message
                    isOpening = false
                }
            } label: {
                Label("Fazer login no Claude Code", systemImage: "person.crop.circle.badge.checkmark")
            }
            .disabled(isOpening)
            .help("Abre o Terminal com claude auth login. Depois de entrar, clique em atualizar.")

            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
