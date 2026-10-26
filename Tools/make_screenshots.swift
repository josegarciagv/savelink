// Renders App Store artwork: screenshots (iPhone 6.9" & 6.3", iPhone Duo, iPad 13") and the
// product page Header and Search Results assets. Brand gradient, headline, real app screens
// in device frames. Output is opaque RGB, as App Store Connect requires.
// Usage: swift Tools/make_screenshots.swift <raw screenshots folder> <output folder>
import AppKit

let rawDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
typealias Palette = (NSColor, NSColor)
let blue: Palette = (rgb(0.27, 0.50, 0.95), rgb(0.42, 0.32, 0.86))
let sunset: Palette = (rgb(1.00, 0.55, 0.30), rgb(0.86, 0.26, 0.52))
let mint: Palette = (rgb(0.15, 0.78, 0.68), rgb(0.12, 0.45, 0.70))
let purple: Palette = (rgb(0.55, 0.36, 0.95), rgb(0.25, 0.30, 0.80))

enum Device {
    case phone, tablet
    /// Screen corner radius as a fraction of the screen width.
    var cornerRatio: CGFloat { self == .phone ? 0.114 : 0.045 }
    var bezelRatio: CGFloat { self == .phone ? 0.025 : 0.022 }
}

struct Copy {
    let title: [String: String]
    let subtitle: [String: String]
}

let copyHome = Copy(title: ["en": "All your links,\nbeautifully organized", "es": "Todos tus enlaces,\nbien organizados"],
                    subtitle: ["en": "Favorites, Read Later and folders at a glance", "es": "Favoritos, Leer después y carpetas de un vistazo"])
let copySearch = Copy(title: ["en": "Find anything\nin seconds", "es": "Encuentra todo\nen segundos"],
                      subtitle: ["en": "Search by name, site, tag or meaning", "es": "Busca por nombre, sitio, etiqueta o significado"])
let copyDetail = Copy(title: ["en": "Read later,\neven offline", "es": "Lee después,\nincluso sin internet"],
                      subtitle: ["en": "Reminders, highlights and AI summaries", "es": "Recordatorios, resaltados y resúmenes con IA"])
let copyFolders = Copy(title: ["en": "Folders with\nyour colors & icons", "es": "Carpetas con\ntus colores e íconos"],
                       subtitle: ["en": "Tags, pins and smart lists", "es": "Etiquetas, fijados y listas inteligentes"])
let copyDuo = Copy(title: ["en": "Made for iPhone Duo", "es": "Hecho para iPhone Duo"],
                   subtitle: ["en": "Save links from Safari, widgets and Siri", "es": "Guarda desde Safari, widgets y Siri"])
let copyReadLater = Copy(title: ["en": "Never lose a link\nyou meant to read", "es": "No pierdas un enlace\nque querías leer"],
                         subtitle: ["en": "Read Later with reminders on every device", "es": "Leer después con recordatorios en todos tus dispositivos"])
let copyBrand = Copy(title: ["en": "SaveLinks", "es": "SaveLinks"],
                     subtitle: ["en": "Save, organize and read\nevery link that matters", "es": "Guarda, organiza y lee\ncada enlace importante"])

// MARK: - Drawing helpers

func image(_ name: String) -> NSImage { NSImage(contentsOf: rawDir.appendingPathComponent(name + ".png"))! }

/// Runs `draw` in an opaque RGB bitmap of `size` and writes it as PNG.
func renderPNG(_ size: CGSize, to url: URL, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    try? NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])?.write(to: url)
}

func drawBackground(_ size: CGSize, _ colors: Palette) {
    NSGradient(starting: colors.0, ending: colors.1)!.draw(in: CGRect(origin: .zero, size: size), angle: -60)
    let glowCenter = CGPoint(x: size.width * 0.15, y: size.height * 0.95)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.25), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: max(size.width, size.height) * 0.8, options: [])
}

/// Draws title + subtitle with their top at `top`, returns the y of the bottom of the text.
@discardableResult
func drawText(_ copy: Copy, lang: String, x: CGFloat, top: CGFloat, width: CGFloat,
              titleSize: CGFloat, subtitleSize: CGFloat, alignment: NSTextAlignment) -> CGFloat {
    let para = NSMutableParagraphStyle()
    para.alignment = alignment
    para.lineHeightMultiple = 0.95
    let title = NSAttributedString(string: copy.title[lang]!, attributes: [
        .font: NSFont.systemFont(ofSize: titleSize, weight: .heavy), .foregroundColor: NSColor.white, .paragraphStyle: para])
    let sub = NSAttributedString(string: copy.subtitle[lang]!, attributes: [
        .font: NSFont.systemFont(ofSize: subtitleSize, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.88), .paragraphStyle: para])
    let titleRect = title.boundingRect(with: CGSize(width: width, height: 10000), options: [.usesLineFragmentOrigin])
    let subRect = sub.boundingRect(with: CGSize(width: width, height: 10000), options: [.usesLineFragmentOrigin])
    title.draw(with: CGRect(x: x, y: top - titleRect.height, width: width, height: titleRect.height), options: [.usesLineFragmentOrigin])
    let subTop = top - titleRect.height - subtitleSize * 0.6
    sub.draw(with: CGRect(x: x, y: subTop - subRect.height, width: width, height: subRect.height), options: [.usesLineFragmentOrigin])
    return subTop - subRect.height
}

/// Draws a device with `screen` inside; `screenRect` is the visible screen area.
func drawDevice(_ screen: NSImage, in screenRect: CGRect, device: Device, ctx: CGContext) {
    let corner = screenRect.width * device.cornerRatio
    let bezel = screenRect.width * device.bezelRatio
    let frameRect = screenRect.insetBy(dx: -bezel, dy: -bezel)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -bezel * 1.5), blur: bezel * 3.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(white: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: frameRect, xRadius: corner + bezel, yRadius: corner + bezel).fill()
    ctx.restoreGState()
    NSColor(white: 0.35, alpha: 1).setStroke()
    let inset = bezel * 0.12
    let edge = NSBezierPath(roundedRect: frameRect.insetBy(dx: inset, dy: inset), xRadius: corner + bezel - inset, yRadius: corner + bezel - inset)
    edge.lineWidth = bezel * 0.16
    edge.stroke()
    ctx.saveGState()
    NSBezierPath(roundedRect: screenRect, xRadius: corner, yRadius: corner).addClip()
    screen.draw(in: screenRect)
    ctx.restoreGState()
}

// MARK: - Screenshot: headline on top, one device bleeding off the bottom

func renderScreenshot(raw: String, copy: Copy, colors: Palette, size: CGSize, device: Device, lang: String, to url: URL) {
    let screen = image(raw)
    renderPNG(size, to: url) { ctx in
        drawBackground(size, colors)
        let unit = size.width / 1320
        let tablet = device == .tablet
        let textBottom = drawText(copy, lang: lang, x: 60 * unit, top: size.height - (tablet ? 110 : 150) * unit,
                                  width: size.width - 120 * unit,
                                  titleSize: (tablet ? 80 : 108) * unit, subtitleSize: (tablet ? 38 : 50) * unit, alignment: .center)
        let width = size.width * (tablet ? 0.84 : 0.80)
        let height = screen.size.height * width / screen.size.width
        let rect = CGRect(x: (size.width - width) / 2, y: textBottom - 80 * unit - height, width: width, height: height)
        drawDevice(screen, in: rect, device: device, ctx: ctx)
    }
}

// MARK: - Wide banners (product page Header / Search Results)

/// Text on the left, three phones fanned out on the right.
func renderHeader(size: CGSize, lang: String, to url: URL) {
    let screens = [image("raw-search"), image("raw-home"), image("raw-detail")]
    renderPNG(size, to: url) { ctx in
        drawBackground(size, blue)
        let h = size.height
        drawText(copyBrand, lang: lang, x: size.width * 0.06, top: h * 0.68, width: size.width * 0.40,
                 titleSize: h * 0.13, subtitleSize: h * 0.055, alignment: .left)
        let phoneHeight = h * 0.86
        let phoneWidth = phoneHeight * screens[0].size.width / screens[0].size.height
        let centerX = size.width * 0.72
        let offsets: [(dx: CGFloat, dy: CGFloat)] = [(-phoneWidth * 1.05, -h * 0.10), (phoneWidth * 1.05, -h * 0.10), (0, h * 0.02)]
        for (index, offset) in offsets.enumerated() {
            let screen = [screens[0], screens[2], screens[1]][index]
            let rect = CGRect(x: centerX - phoneWidth / 2 + offset.dx, y: (h - phoneHeight) / 2 + offset.dy, width: phoneWidth, height: phoneHeight)
            drawDevice(screen, in: rect, device: .phone, ctx: ctx)
        }
    }
}

/// Headline on top, three phones side by side cropped at the bottom.
func renderSearchResults(size: CGSize, lang: String, to url: URL) {
    let screens = [image("raw-home"), image("raw-search"), image("raw-detail")]
    renderPNG(size, to: url) { ctx in
        drawBackground(size, purple)
        let h = size.height
        let textBottom = drawText(copyHome, lang: lang, x: size.width * 0.05, top: h * 0.92, width: size.width * 0.90,
                                  titleSize: h * 0.07, subtitleSize: h * 0.032, alignment: .center)
        let gap = size.width * 0.04
        let phoneWidth = (size.width * 0.86 - gap * 2) / 3
        let phoneHeight = phoneWidth * screens[0].size.height / screens[0].size.width
        let top = textBottom - h * 0.05
        for (index, screen) in screens.enumerated() {
            let x = size.width * 0.07 + CGFloat(index) * (phoneWidth + gap)
            drawDevice(screen, in: CGRect(x: x, y: top - phoneHeight, width: phoneWidth, height: phoneHeight), device: .phone, ctx: ctx)
        }
    }
}

// MARK: - Output

let iPhone69 = CGSize(width: 1320, height: 2868)
let iPhone63 = CGSize(width: 1206, height: 2622)
let duo = CGSize(width: 1398, height: 2034)
let iPad13 = CGSize(width: 2064, height: 2752)

let phoneSet: [(String, String, Copy, Palette)] = [
    ("01-home", "raw-home", copyHome, blue),
    ("02-search", "raw-search", copySearch, mint),
    ("03-detail", "raw-detail", copyDetail, sunset),
    ("04-folders", "raw-folders", copyFolders, purple),
]
let duoSet: [(String, String, Copy, Palette)] = [
    ("01-home", "raw-duo-home", copyDuo, blue),
    ("02-detail", "raw-duo-detail", copyDetail, sunset),
    ("03-folders", "raw-duo-folders", copyFolders, purple),
]
let iPadSet: [(String, String, Copy, Palette)] = [
    ("01-home", "raw-ipad-home", copyHome, blue),
    ("02-readlater", "raw-ipad-readlater", copyReadLater, sunset),
    ("03-detail", "raw-ipad-detail", copyDetail, mint),
]

for lang in ["en", "es"] {
    let dir = outDir.appendingPathComponent(lang)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, raw, copy, colors) in phoneSet {
        renderScreenshot(raw: raw, copy: copy, colors: colors, size: iPhone69, device: .phone, lang: lang,
                         to: dir.appendingPathComponent("iPhone6.9-\(name).png"))
        renderScreenshot(raw: raw, copy: copy, colors: colors, size: iPhone63, device: .phone, lang: lang,
                         to: dir.appendingPathComponent("iPhone6.3-\(name).png"))
    }
    for (name, raw, copy, colors) in duoSet {
        renderScreenshot(raw: raw, copy: copy, colors: colors, size: duo, device: .phone, lang: lang,
                         to: dir.appendingPathComponent("iPhoneDuo-\(name).png"))
    }
    for (name, raw, copy, colors) in iPadSet {
        renderScreenshot(raw: raw, copy: copy, colors: colors, size: iPad13, device: .tablet, lang: lang,
                         to: dir.appendingPathComponent("iPad13-\(name).png"))
    }
    renderHeader(size: CGSize(width: 3840, height: 1646), lang: lang, to: dir.appendingPathComponent("Header-3840x1646.png"))
    renderSearchResults(size: CGSize(width: 3840, height: 2560), lang: lang, to: dir.appendingPathComponent("SearchResults-3840x2560.png"))
}
print("done")
