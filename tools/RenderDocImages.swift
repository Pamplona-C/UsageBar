import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Imagens de documentação: nenhuma leitura de conta, histórico real ou área de trabalho.
@main
struct RenderDocImages {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        NSTimeZone.default = TimeZone(identifier: "America/Sao_Paulo")!
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let suite = "UsageBarDocImages-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let primaryReset = now.addingTimeInterval(2 * 3600 + 40 * 60)
        let limits = RateLimits(fiveHour: UsageWindow(usedPercentage: 25, resetsAt: primaryReset),
                                sevenDay: UsageWindow(usedPercentage: 56, resetsAt: now.addingTimeInterval(3 * 86400)))
        let tokens = TokenStore(scan: { _ in
            var buckets = TokenBuckets()
            let start = primaryReset.addingTimeInterval(-5 * 3600)
            for (index, values) in [(0, (8_700_000, 41_000)), (1, (14_200_000, 53_000)), (2, (20_800_000, 129_000))] {
                buckets.add(TokenEvent(key: "documentation-\(index)", date: start.addingTimeInterval(Double(index) * 3600 + 60),
                                       count: TokenCount(total: values.0, written: values.1)))
            }
            return buckets
        })
        let claude = UsageStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                defaults: defaults, fetchReport: { .success(limits) }, tokens: tokens)
        let codexReport = CodexUsageReport(
            primary: CodexUsageWindow(usedPercent: 20, windowDurationMins: 300,
                                      resetsAt: now.addingTimeInterval(3 * 3600 + 15 * 60).timeIntervalSince1970),
            secondary: CodexUsageWindow(usedPercent: 37, windowDurationMins: 10080,
                                        resetsAt: now.addingTimeInterval(5 * 86400).timeIntervalSince1970), planType: "plus")
        let codex = CodexStore(defaults: defaults, fetch: { .success(codexReport) },
                               openLogin: { .notFound }, startAutomatically: false)
        codex.check(force: true)
        for _ in 0..<200 where claude.isCheckingServer || codex.isChecking || tokens.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let accounts = UsageAccounts(defaults: defaults, claude: claude, codex: codex)
        let menubar = VStack(spacing: 0) {
            AccountMenuBarLabel(accounts: accounts)
                .environment(\.colorScheme, .light)
                .padding(14).frame(maxWidth: .infinity).background(Color.white)
            AccountMenuBarLabel(accounts: accounts)
                .environment(\.colorScheme, .dark)
                .padding(14).frame(maxWidth: .infinity).background(Color(white: 0.12))
        }
        try await capture(menubar, width: 240, to: destination.appendingPathComponent("menubar.png"))
        accounts.selected = .claude
        try await capture(UsagePopover(accounts: accounts), width: 300, to: destination.appendingPathComponent("popover.png"))
        accounts.selected = .codex
        try await capture(UsagePopover(accounts: accounts), width: 300, to: destination.appendingPathComponent("codex-popover.png"))
        try await capture(AccountSettingsView(accounts: accounts), width: 480, to: destination.appendingPathComponent("accounts.png"))
        codex.disconnect()
        try await capture(CodexConnectionView(store: codex), width: 350, to: destination.appendingPathComponent("codex-connect.png"))
        print("Cinco imagens nativas geradas com dados fictícios; nenhum CLI ou login foi executado.")
    }

    @MainActor private static func capture<V: View>(_ content: V, width: CGFloat, to url: URL) async throws {
        let host = NSHostingView(rootView: content.environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor)).fixedSize(horizontal: false, vertical: true))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        let height = max(host.fittingSize.height, 1)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        host.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 350_000_000)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "UsageBar.Documentation", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let captured = bitmap.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: captured.width, height: captured.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "UsageBar.Documentation", code: 2)
        }
        context.draw(captured, in: CGRect(x: 0, y: 0, width: captured.width, height: captured.height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "UsageBar.Documentation", code: 2)
        }
        // Exporta só os pixels. Não leva EXIF, XMP ou campos de texto do bitmap temporário.
        CGImageDestinationAddImage(destination, image, [:] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "UsageBar.Documentation", code: 3) }
        // O encoder pode acrescentar EXIF automaticamente. Remove os chunks de metadados,
        // preservando os bytes dos pixels e o perfil sRGB público acima.
        let encoded = try Data(contentsOf: url)
        var clean = Data(encoded.prefix(8))
        var offset = 8
        let excluded: Set<String> = ["eXIf", "tEXt", "zTXt", "iTXt"]
        while offset + 12 <= encoded.count {
            let length = encoded[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            let end = offset + length + 12
            guard end <= encoded.count else { throw NSError(domain: "UsageBar.Documentation", code: 4) }
            let kind = String(decoding: encoded[offset + 4..<offset + 8], as: UTF8.self)
            if !excluded.contains(kind) { clean.append(encoded[offset..<end]) }
            offset = end
        }
        try clean.write(to: url, options: .atomic)
        window.orderOut(nil)
    }
}
