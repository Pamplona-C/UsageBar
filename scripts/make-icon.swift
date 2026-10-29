// Desenha o ícone do app e gera o .icns com iconutil.
// Uso: swift scripts/make-icon.swift <saida.icns>
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("uso: swift scripts/make-icon.swift <saida.icns>\n".data(using: .utf8)!)
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

/// Desenha em uma grade de 1024 pontos, escalada para `pixels`.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // Fundo: quadrado arredondado na grade de ícones do macOS (824 pt com margem de 100).
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedWhite: 0.20, alpha: 1),
               ending: NSColor(calibratedWhite: 0.09, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    // Trilho da barra.
    let track = NSRect(x: 212, y: 452, width: 600, height: 120)
    NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
    NSBezierPath(roundedRect: track, xRadius: 60, yRadius: 60).fill()

    // Preenchimento em ~75%. O gradiente ocupa o trilho inteiro, para as cores baterem com as marcas.
    let fill = NSRect(x: track.minX, y: track.minY, width: track.width * 0.75, height: track.height)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: fill, xRadius: 60, yRadius: 60).addClip()
    NSGradient(colors: [.systemGreen, .systemGreen, .systemYellow, .systemRed],
               atLocations: [0, 0.4, 0.6, 0.85], colorSpace: .deviceRGB)!
        .draw(in: track, angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    // Marcas de 60% e 85%, os limites entre as cores.
    NSColor(calibratedWhite: 1, alpha: 0.35).setFill()
    for fraction in [0.6, 0.85] {
        let x = track.minX + track.width * fraction
        NSBezierPath(roundedRect: NSRect(x: x - 6, y: 360, width: 12, height: 56), xRadius: 6, yRadius: 6).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("UsageBar-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
