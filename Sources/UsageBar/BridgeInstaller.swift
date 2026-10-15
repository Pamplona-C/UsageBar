import Foundation

/// Roda os mesmos scripts de `scripts/` usados no terminal e diz se o bridge está ativo.
enum BridgeInstaller {
    enum Action {
        case install, uninstall

        var script: String {
            switch self {
            case .install: return "install-bridge.sh"
            case .uninstall: return "uninstall-bridge.sh"
            }
        }
    }

    struct Output {
        let succeeded: Bool
        let text: String
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Só lê o `settings.json`: o bridge está ativo se `statusLine.command` aponta para ele.
    static func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String
        else { return false }
        return command.contains("usagebar-bridge.sh")
    }

    /// `Contents/Resources/scripts` no .app; via `swift run`, a pasta `scripts/` do repositório.
    static var scriptsDirectory: URL? {
        let candidates = [Bundle.main.resourceURL] + ancestors(of: Bundle.main.executableURL)
        return candidates
            .compactMap { $0?.appendingPathComponent("scripts") }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("install-bridge.sh").path) }
    }

    /// Roda o script com `--yes`: a confirmação já foi feita pelo app.
    static func run(_ action: Action) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(action))
            }
        }
    }

    private static func runSync(_ action: Action) -> Output {
        guard let directory = scriptsDirectory else {
            return Output(succeeded: false, text: "Scripts do UsageBar não encontrados.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [directory.appendingPathComponent(action.script).path, "--yes"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Output(succeeded: false, text: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(succeeded: process.terminationStatus == 0,
                      text: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func ancestors(of url: URL?) -> [URL?] {
        var result: [URL?] = []
        var current = url?.deletingLastPathComponent()
        while let directory = current, directory.path != "/" {
            result.append(directory)
            current = directory.deletingLastPathComponent()
        }
        return result
    }
}
