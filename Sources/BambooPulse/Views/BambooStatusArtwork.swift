import SwiftUI
import PulseCore

struct BambooStatusArtwork: View {
    let state: SessionState
    let phase: Double?

    var body: some View {
        artwork
            .overlay {
                if let phase {
                    highlight(phase: phase)
                        .mask(artwork)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 2)
    }

    private var artwork: some View {
        Image(nsImage: BambooArtwork.image(for: state))
            .resizable()
            .interpolation(.high)
            .frame(width: 96, height: 17)
    }

    @ViewBuilder private func highlight(phase: Double) -> some View {
        // Match the texture's body ranges in BambooArtwork; never light the rings
        // or another status section. Base color and underline stay visible.
        if state == .needsAttention {
            Rectangle()
                .fill(.white.opacity(BambooMotion.pulseOpacity(phase: phase)))
                .frame(width: 96 * (0.333 - 0.065), height: 17)
                .frame(width: 96, alignment: .leading)
                .offset(x: 96 * 0.065)
        } else if state == .working {
            let width = 96 * (0.963 - 0.684)
            LinearGradient(colors: [.clear, .white.opacity(0.42), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 12, height: 17)
                .offset(x: (width + 12) * phase - 12)
                .frame(width: width, alignment: .leading)
                .clipped()
                .frame(width: 96, alignment: .leading)
                .offset(x: 96 * 0.684)
        }
    }

}
