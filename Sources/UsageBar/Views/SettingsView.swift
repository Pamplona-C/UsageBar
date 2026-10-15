import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("Dados") {
                LabeledContent("Arquivo observado") {
                    Text(store.fileURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
