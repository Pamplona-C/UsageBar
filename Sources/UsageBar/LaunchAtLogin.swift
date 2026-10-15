import Foundation
import ServiceManagement

/// "Abrir ao iniciar sessão" via `SMAppService.mainApp`.
enum LaunchAtLogin {
    /// Só funciona no .app empacotado; via `swift run` não há bundle para registrar.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
