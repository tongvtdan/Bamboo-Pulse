#!/usr/bin/env swift
import AppKit

// Original geometric bamboo mark. Run only when intentionally regenerating assets.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, 1])!
}
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.addPath(CGPath(roundedRect: CGRect(x: 32, y: 32, width: 960, height: 960),
                               cornerWidth: 208, cornerHeight: 208, transform: nil))
        context.setFillColor(color(0.09, 0.17, 0.13)); context.fillPath()
        let gradient = CGGradient(colorsSpace: space,
            colors: [color(0.30, 0.45, 0.25), color(0.68, 0.79, 0.43), color(0.35, 0.51, 0.28)] as CFArray,
            locations: [0, 0.42, 1])!
        context.saveGState()
        context.addPath(CGPath(roundedRect: CGRect(x: 400, y: 138, width: 224, height: 748),
                               cornerWidth: 36, cornerHeight: 36, transform: nil))
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: 400, y: 512), end: CGPoint(x: 624, y: 512), options: [])
        context.restoreGState()
        for y in [367, 625] {
            context.addPath(CGPath(roundedRect: CGRect(x: 384, y: y, width: 256, height: 32),
                                   cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.setFillColor(color(0.76, 0.79, 0.57)); context.fillPath()
            context.setFillColor(color(0.24, 0.36, 0.22))
            context.fill(CGRect(x: 400, y: y - 8, width: 224, height: 8))
        }
        let filename = "appicon-\(points)@\(scale)x.png"
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
