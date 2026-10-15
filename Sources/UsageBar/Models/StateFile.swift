import Foundation

enum StateFileError: Error, Equatable {
    case notFound
    case unreadable
    case invalidJSON
}

/// Conteúdo lido de `state.json`, com a data em que o bridge o gravou.
struct StateFileContents: Equatable {
    var snapshot: UsageSnapshot
    var modifiedAt: Date
}

/// Lê o `state.json` que o bridge grava com o payload bruto da statusline.
enum StateFile {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/usagebar/state.json")
    }

    static func parse(_ data: Data) throws -> UsageSnapshot {
        do {
            return try JSONDecoder().decode(UsageSnapshot.self, from: data)
        } catch {
            throw StateFileError.invalidJSON
        }
    }

    static func load(from url: URL = defaultURL) throws -> StateFileContents {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw StateFileError.notFound
        } catch {
            throw StateFileError.unreadable
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes?[.modificationDate] as? Date ?? Date()
        return StateFileContents(snapshot: try parse(data), modifiedAt: modifiedAt)
    }
}
