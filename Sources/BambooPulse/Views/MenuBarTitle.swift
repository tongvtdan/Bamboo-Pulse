import AppKit
import PulseCore

@MainActor
enum MenuBarTitle {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private static let badges = Dictionary(uniqueKeysWithValues: SessionState.allCases.map { ($0, badge(for: $0)) })
    private static let emptyBadge = badge(for: nil)
    private static let movingBadges: [SessionState: [NSImage]] = Dictionary(uniqueKeysWithValues:
        [(SessionState.working, 36), (.needsAttention, 48)].map { state, count in
            (state, (0..<count).map { badge(for: state, phase: Double($0) / Double(count)) })
        })

    static func motionEnabled(for summary: MenuBarSummary, reduceMotion: Bool, isVisible: Bool, isAwake: Bool) -> Bool {
        isAwake && !summary.isUnavailable && summary.groups.contains {
            BambooMotion.isEnabled(state: $0.state, reduceMotion: reduceMotion, isVisible: isVisible)
        }
    }

    static func attributedString(for summary: MenuBarSummary, at date: Date? = nil) -> NSAttributedString {
        let title = NSMutableAttributedString(string: summary.isSynthetic ? "Demo  " : "")
        if summary.isUnavailable {
            append(badges[.unknown]!, to: title)
        } else if summary.groups.isEmpty {
            append(emptyBadge, to: title)
            title.append(NSAttributedString(string: " 0"))
        } else {
            for (index, group) in summary.groups.enumerated() {
                if index > 0 { title.append(NSAttributedString(string: "  ")) }
                append(image(for: group.state, at: date), to: title)
                title.append(NSAttributedString(string: " \(group.displayCount)"))
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        title.addAttributes([.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph],
                            range: NSRange(location: 0, length: title.length))
        return title
    }

    private static func image(for state: SessionState, at date: Date?) -> NSImage {
        guard let date, let frames = movingBadges[state] else { return badges[state]! }
        let phase = BambooMotion.phase(at: date, state: state)
        return frames[min(frames.count - 1, Int(phase * Double(frames.count)))]
    }

    private static func append(_ image: NSImage, to text: NSMutableAttributedString) {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
        text.append(NSAttributedString(attachment: attachment))
    }

    private static func badge(for state: SessionState?, phase: Double? = nil) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let color: NSColor
            let symbol: String
            switch state {
            case .needsAttention: color = .systemRed; symbol = "!"
            case .turnEnded: color = .systemOrange; symbol = "−"
            case .working: color = .systemGreen; symbol = ""
            case .unknown: color = .systemGray; symbol = "?"
            case nil: color = .secondaryLabelColor; symbol = ""
            }
            let circle = CGRect(x: 0.5, y: 0.5, width: 11, height: 11)
            if state == nil {
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(1)
                context.strokeEllipse(in: circle)
            } else {
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: circle)
            }
            if let phase {
                context.saveGState()
                context.addEllipse(in: circle)
                context.clip()
                if state == .needsAttention {
                    context.setFillColor(NSColor.white.withAlphaComponent(BambooMotion.pulseOpacity(phase: phase)).cgColor)
                    context.fill(circle)
                } else if state == .working {
                    let bandWidth = circle.width * 0.45
                    let x = circle.minX + (circle.width + bandWidth) * phase - bandWidth
                    let colors = [NSColor.white.withAlphaComponent(0).cgColor,
                                  NSColor.white.withAlphaComponent(0.42).cgColor,
                                  NSColor.white.withAlphaComponent(0).cgColor]
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                 colors: colors as CFArray, locations: [0, 0.5, 1]) {
                        context.drawLinearGradient(gradient, start: CGPoint(x: x, y: 0),
                                                   end: CGPoint(x: x + bandWidth, y: 0), options: [])
                    }
                }
                context.restoreGState()
            }
            if !symbol.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white]
                let text = symbol as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: (12 - size.width) / 2, y: (12 - size.height) / 2), withAttributes: attributes)
            }
            return true
        }
    }
}
