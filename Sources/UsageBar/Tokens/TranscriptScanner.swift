import Foundation

/// Lê os históricos do Claude Code de forma incremental: a cada passada, só o que foi acrescentado aos arquivos.
///
/// Não é isolada: quem usa chama sempre da mesma fila.
final class TranscriptScanner {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    private struct FileState {
        var fileID: UInt64
        /// Bytes já consumidos, sempre até o fim de uma linha completa.
        var offset: UInt64
    }

    let root: URL
    private var files: [String: FileState] = [:]
    private var buckets = TokenBuckets()

    init(root: URL = TranscriptScanner.defaultRoot) {
        self.root = root
    }

    /// Lê os arquivos `.jsonl` modificados a partir de `since` e devolve os baldes acumulados a partir de `since`.
    /// Lança só quando `root` existe e não pode ser listada.
    func scan(since: Date) throws -> TokenBuckets {
        buckets.prune(before: since)
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return buckets
        }
        // Falha ao listar a raiz vira erro; falha em uma subpasta só pula a subpasta.
        _ = try fm.contentsOfDirectory(atPath: root.path)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return buckets }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= since else { continue }
            read(url)
        }
        return buckets
    }

    private func read(_ url: URL) {
        let path = url.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return }

        var state = files[path] ?? FileState(fileID: fileID, offset: 0)
        // Outro arquivo no mesmo caminho, ou o mesmo reescrito menor: relê do início. A deduplicação dos
        // baldes evita contar de novo o que já foi contado.
        if state.fileID != fileID || size < state.offset {
            state = FileState(fileID: fileID, offset: 0)
        }
        guard size > state.offset, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        guard (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }
        // Só até o último "\n": uma linha pela metade ainda está sendo gravada e fica para a próxima passada.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            if let event = TranscriptLine.parse(Data(line)) {
                buckets.add(event)
            }
        }
        state.offset += UInt64(complete.count)
        files[path] = state
    }
}
