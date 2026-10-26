// Renders the SaveLink app icon (1024×1024) in light, dark and tinted variants.
// Usage: swift Tools/make_icon.swift SaveLink/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

/// Bookmark ribbon: rounded top, V notch at the bottom (y-down coordinates).
func bookmarkPath() -> CGPath {
    let left: CGFloat = 287, right: CGFloat = 737, top: CGFloat = 190, bottom: CGFloat = 840
    let radius: CGFloat = 72, notch: CGFloat = 150
    let p = CGMutablePath()
    p.move(to: CGPoint(x: left, y: bottom))
    p.addLine(to: CGPoint(x: left, y: top + radius))
    p.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + radius, y: top), radius: radius)
    p.addLine(to: CGPoint(x: right - radius, y: top))
    p.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top + radius), radius: radius)
    p.addLine(to: CGPoint(x: right, y: bottom))
    // Rounded inner corners of the notch
    p.addLine(to: CGPoint(x: size / 2 + 22, y: bottom - notch + 14))
    p.addQuadCurve(to: CGPoint(x: size / 2 - 22, y: bottom - notch + 14), control: CGPoint(x: size / 2, y: bottom - notch - 4))
    p.closeSubpath()
    return p
}

/// One chain link: a stroked capsule along a 45° axis.
func linkCapsule(offset: CGFloat) -> CGPath {
    let length: CGFloat = 270, height: CGFloat = 128
    let rect = CGRect(x: -length / 2 + offset, y: -height / 2, width: length, height: height)
    var transform = CGAffineTransform(translationX: size / 2, y: 470).rotated(by: -.pi / 4)
    return CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: &transform)
}

/// Two interlocked chain links. Each link gets a thin gap painted with the
/// bookmark's own fill where it passes in front of the other one.
func drawChain(in ctx: CGContext, colors: [CGColor], paintBookmark: () -> Void) {
    let lineWidth: CGFloat = 44
    let gap: CGFloat = 24
    let a = linkCapsule(offset: -72)
    let b = linkCapsule(offset: 72)
    let fill = gradient(colors)

    func paint(_ path: CGPath, width: CGFloat, extraClip: (() -> Void)?, body: () -> Void) {
        ctx.saveGState()
        extraClip?()
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        body()
        ctx.restoreGState()
    }

    func link(_ path: CGPath, extraClip: (() -> Void)? = nil) {
        paint(path, width: lineWidth + gap, extraClip: extraClip, body: paintBookmark)
        paint(path, width: lineWidth, extraClip: extraClip) {
            ctx.drawLinearGradient(fill, start: CGPoint(x: 330, y: 300), end: CGPoint(x: 700, y: 650), options: [])
        }
    }

    link(a)
    link(b)

    // Weave: on the upper-left side of the chain axis, A passes back in front of B.
    // Clip to that half-plane and to B's band so only the crossing is redrawn.
    link(a) {
        let halfPlane = CGMutablePath()
        halfPlane.addLines(between: [CGPoint(x: size / 2 - 2000, y: 470 + 2000),
                                     CGPoint(x: size / 2 + 2000, y: 470 - 2000),
                                     CGPoint(x: -3000, y: -3000)])
        halfPlane.closeSubpath()
        ctx.addPath(halfPlane)
        ctx.clip()
        ctx.addPath(b)
        ctx.setLineWidth(lineWidth + gap + 2)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
    }
}

enum Variant { case light, dark, tinted }

/// Colors of the light icon: background gradient (start, middle, end) and chain gradient.
struct Palette {
    var start = (0.27, 0.50, 0.95)
    var middle = (0.20, 0.40, 0.80)
    var end = (0.42, 0.32, 0.86)

    static let brand = Palette()
    static let sunset = Palette(start: (1.00, 0.62, 0.25), middle: (0.98, 0.38, 0.38), end: (0.85, 0.24, 0.55))
    static let mint = Palette(start: (0.25, 0.85, 0.70), middle: (0.12, 0.68, 0.60), end: (0.10, 0.48, 0.62))
    static let graphite = Palette(start: (0.40, 0.42, 0.47), middle: (0.24, 0.25, 0.29), end: (0.12, 0.12, 0.15))
}

func render(_ variant: Variant, palette: Palette = .brand, to url: URL, pixels: Int = 1024) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // y-down coordinates
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let paletteStart = rgb(palette.start.0, palette.start.1, palette.start.2)
    let brandBlue = rgb(palette.middle.0, palette.middle.1, palette.middle.2)
    let brandPurple = rgb(palette.end.0, palette.end.1, palette.end.2)

    // Background
    switch variant {
    case .light:
        ctx.drawLinearGradient(gradient([paletteStart, brandBlue, brandPurple]),
                               start: .zero, end: CGPoint(x: size, y: size), options: [])
        ctx.drawRadialGradient(gradient([rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)]),
                               startCenter: CGPoint(x: 220, y: 160), startRadius: 0,
                               endCenter: CGPoint(x: 220, y: 160), endRadius: 620, options: [])
    case .dark:
        ctx.drawLinearGradient(gradient([rgb(0.07, 0.09, 0.20), rgb(0.10, 0.08, 0.22)]),
                               start: .zero, end: CGPoint(x: size, y: size), options: [])
        ctx.drawRadialGradient(gradient([rgb(0.35, 0.40, 0.95, 0.28), rgb(0.35, 0.40, 0.95, 0)]),
                               startCenter: CGPoint(x: size / 2, y: 480), startRadius: 0,
                               endCenter: CGPoint(x: size / 2, y: 480), endRadius: 560, options: [])
    case .tinted:
        ctx.setFillColor(rgb(0, 0, 0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    let paintBookmark: () -> Void = {
        switch variant {
        case .light:
            ctx.setFillColor(rgb(1, 1, 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        case .dark:
            ctx.drawLinearGradient(gradient([rgb(0.36, 0.56, 1.0), brandPurple]),
                                   start: CGPoint(x: 287, y: 190), end: CGPoint(x: 737, y: 840), options: [])
        case .tinted:
            ctx.setFillColor(rgb(0.92, 0.92, 0.92))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    // Bookmark with soft shadow (drawn first as a solid shape, then filled)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 60, color: rgb(0, 0, 0, variant == .light ? 0.28 : 0.5))
    ctx.addPath(bookmarkPath())
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bookmarkPath())
    ctx.clip()
    paintBookmark()
    ctx.restoreGState()

    // Chain
    switch variant {
    case .light: drawChain(in: ctx, colors: [paletteStart, brandPurple], paintBookmark: paintBookmark)
    case .dark: drawChain(in: ctx, colors: [rgb(1, 1, 1), rgb(0.88, 0.90, 1)], paintBookmark: paintBookmark)
    case .tinted: drawChain(in: ctx, colors: [rgb(0.35, 0.35, 0.35), rgb(0.25, 0.25, 0.25)], paintBookmark: paintBookmark)
    }

    var image = ctx.makeImage()!
    if pixels != Int(size) {
        let small = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        image = small.makeImage()!
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// Usage:
//   swift Tools/make_icon.swift <AppIcon.appiconset folder>          main icon (light, dark, tinted)
//   swift Tools/make_icon.swift <Assets.xcassets folder> alternates  alternate icons + in-app previews
let out = URL(fileURLWithPath: CommandLine.arguments[1])
if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "alternates" {
    let alternates: [(String, Palette)] = [("Sunset", .sunset), ("Mint", .mint), ("Graphite", .graphite)]
    let fm = FileManager.default
    for (name, palette) in alternates {
        let iconSet = out.appendingPathComponent("AppIcon-\(name).appiconset")
        let preview = out.appendingPathComponent("IconPreview-\(name).imageset")
        try? fm.createDirectory(at: iconSet, withIntermediateDirectories: true)
        try? fm.createDirectory(at: preview, withIntermediateDirectories: true)
        render(.light, palette: palette, to: iconSet.appendingPathComponent("AppIcon.png"))
        render(.light, palette: palette, to: preview.appendingPathComponent("preview.png"), pixels: 240)
        try? #"{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#
            .write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        try? #"{"images":[{"filename":"preview.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}"#
            .write(to: preview.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }
    let preview = out.appendingPathComponent("IconPreview-Default.imageset")
    try? fm.createDirectory(at: preview, withIntermediateDirectories: true)
    render(.light, to: preview.appendingPathComponent("preview.png"), pixels: 240)
    try? #"{"images":[{"filename":"preview.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}"#
        .write(to: preview.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
} else {
    render(.light, to: out.appendingPathComponent("AppIcon.png"))
    render(.dark, to: out.appendingPathComponent("AppIcon-Dark.png"))
    render(.tinted, to: out.appendingPathComponent("AppIcon-Tinted.png"))
}
print("done")
