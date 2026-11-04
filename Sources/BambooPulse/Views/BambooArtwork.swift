import AppKit
import PulseCore

@MainActor
enum BambooArtwork {
    private static let images: [SessionState: NSImage] = {
        guard let source = NSImage(named: "BambooTexture")?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let texture = source.cropping(to: CGRect(x: 95, y: 200, width: 1982, height: 350)) else {
            assertionFailure("The bundled bamboo texture is missing")
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: SessionState.allCases.map { state in
            (state, render(texture: texture, state: state))
        })
    }()

    static func image(for state: SessionState) -> NSImage {
        images[state] ?? NSImage(size: NSSize(width: 216, height: 50))
    }

    private static func render(texture: CGImage, state: SessionState) -> NSImage {
        let width = texture.width
        let height = texture.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(cgImage: texture, size: .zero)
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(texture, in: bounds)
        if state != .unknown {
            context.saveGState()
            context.clip(to: bounds, mask: texture)
            context.setBlendMode(.color)
            // Body ranges belong to this texture; cut ends and node rings retain their natural material.
            let ranges: [(CGFloat, CGFloat)] = [(0.065, 0.333), (0.369, 0.649), (0.684, 0.963)]
            for (index, range) in ranges.enumerated() {
                let color: NSColor
                switch (index, state) {
                case (0, .needsAttention): color = NSColor(srgbRed: 1, green: 0.23, blue: 0.12, alpha: 1)
                case (1, .turnEnded): color = NSColor(srgbRed: 1, green: 0.64, blue: 0, alpha: 1)
                case (2, .working): color = NSColor(srgbRed: 0.28, green: 0.78, blue: 0.09, alpha: 1)
                default: color = NSColor(srgbRed: 0.56, green: 0.63, blue: 0.39, alpha: 1)
                }
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: range.0 * bounds.width, y: 0,
                                    width: (range.1 - range.0) * bounds.width, height: bounds.height))
            }
            context.restoreGState()
        }
        return NSImage(cgImage: context.makeImage() ?? texture, size: NSSize(width: 216, height: 38))
    }
}
