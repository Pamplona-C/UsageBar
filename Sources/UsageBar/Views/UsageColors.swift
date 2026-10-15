import AppKit
import SwiftUI

extension UsageLevel {
    var nsColor: NSColor {
        switch self {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

enum StatusDot {
    /// Bolinha colorida para a barra de menu. Precisa ser `NSImage` não-template: a barra de menu
    /// pinta imagens template e símbolos SwiftUI de uma cor só.
    static func image(color: NSColor, diameter: CGFloat = 8) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
