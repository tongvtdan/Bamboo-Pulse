import AppKit
import SwiftUI
import PulseCore

// Use production artwork and labels. Reproduce BambooStalk's underline here:
// ImageRenderer cannot export its AppKit visibility helper or animation timeline.
private struct StatusCard: View {
    let state: SessionState
    let cue: String
    let section: Int

    var body: some View {
        VStack(spacing: 16) {
            Text(state.label)
                .font(.system(size: 24, weight: .semibold))
            VStack(spacing: 3) {
                BambooStatusArtwork(state: state, phase: nil)
                ZStack(alignment: .leading) {
                    Color.clear
                    Capsule().fill(.primary.opacity(0.75))
                        .frame(width: 16, height: 2)
                        .offset(x: CGFloat(section) * 32 + 8)
                }
                .frame(width: 96, height: 2)
            }
                .scaleEffect(2.5)
                .frame(width: 240, height: 55)
            Text(cue)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, height: 184)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
    }
}

@main @MainActor
private enum RenderStatusImages {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DocumentationImages", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected repository root"])
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let textureURL = root.appendingPathComponent("Resources/Assets.xcassets/BambooTexture.imageset/bamboo-neutral.png")
        guard let texture = NSImage(contentsOf: textureURL), texture.setName("BambooTexture") else {
            throw NSError(domain: "DocumentationImages", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot load bamboo texture"])
        }
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        let states: [(SessionState, String, String, Int)] = [
            (.working, "working", "Right section · green", 2),
            (.needsAttention, "needs-you", "Left section · red-orange", 0),
            (.turnEnded, "turn-ended", "Middle section · amber", 1),
        ]
        let output = root.appendingPathComponent("docs/images", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (state, name, cue, section) in states {
            let renderer = ImageRenderer(content: StatusCard(state: state, cue: cue, section: section))
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "DocumentationImages", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot render \(name)"])
            }
            let destination = output.appendingPathComponent("status-\(name).png")
            try png.write(to: destination, options: .atomic)
            print("Rendered \(destination.lastPathComponent)")
        }
        withExtendedLifetime(texture) {}
    }
}
