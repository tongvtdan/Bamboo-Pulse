import AppKit
import SwiftUI

struct BambooGlyph: Shape {
    @MainActor static var menuBarImage: NSImage {
        let size = NSSize(width: 9, height: 18)
        let outline = BambooGlyph().path(in: CGRect(origin: .zero, size: size)).cgPath
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.3)
            context.addPath(outline)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect.insetBy(dx: 2, dy: 0.7), cornerSize: CGSize(width: 1, height: 1))
        for fraction in [0.32, 0.67] {
            let y = rect.height * fraction
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}
