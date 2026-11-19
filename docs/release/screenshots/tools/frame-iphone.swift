import AppKit
import CoreGraphics

var W: CGFloat = 1320, H: CGFloat = 2868
let yellow = NSColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 1)
let ink = NSColor(red: 0.027, green: 0.031, blue: 0.047, alpha: 1)

func fnt(_ names: [String], _ size: CGFloat) -> NSFont {
    for n in names { if let f = NSFont(name: n, size: size) { return f } }
    return NSFont.systemFont(ofSize: size, weight: .heavy)
}
let display = ["AvenirNextCondensed-Heavy", "HelveticaNeue-CondensedBlack"]
let body = ["AvenirNext-DemiBold", "HelveticaNeue-Medium"]
let label = ["AvenirNextCondensed-Bold", "HelveticaNeue-Bold"]

func png(_ img: NSImage, to path: String) {
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func canvas(_ draw: (CGContext) -> Void) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: NSSize(width: W, height: H)); img.addRepresentation(rep); return img
}

/// Headline with *accent* words in yellow. Lines split by \n.
func headline(_ text: String, size: CGFloat, align: NSTextAlignment, color: NSColor = .white) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineHeightMultiple = 0.86
    let out = NSMutableAttributedString()
    var accent = false
    for part in text.split(separator: "*", omittingEmptySubsequences: false) {
        out.append(NSAttributedString(string: String(part), attributes: [
            .font: fnt(display, size), .foregroundColor: accent ? yellow : color, .paragraphStyle: p, .kern: size * 0.005]))
        accent.toggle()
    }
    return out
}
func para(_ text: String, size: CGFloat, align: NSTextAlignment, alpha: CGFloat = 0.82) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineHeightMultiple = 1.18
    return NSAttributedString(string: text, attributes: [.font: fnt(body, size), .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: p])
}

func background(_ ctx: CGContext, glow: CGPoint) {
    ctx.setFillColor(ink.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let cs = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: cs, colors: [yellow.withAlphaComponent(0.34).cgColor, yellow.withAlphaComponent(0.10).cgColor, yellow.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(g, startCenter: glow, startRadius: 0, endCenter: glow, endRadius: max(W, H) * 0.62, options: [])
    // faint vignette to keep the corners deep
    let v = CGGradient(colorsSpace: cs, colors: [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.55).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(v, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: min(W, H) * 0.5, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: max(W, H) * 0.85, options: [])
}

/// Pills in a row from the left edge; returns nothing. y is the baseline box bottom in CG coordinates.
func pills(_ ctx: CGContext, _ items: [String], x: CGFloat, y: CGFloat, size: CGFloat, maxWidth: CGFloat) {
    var cx = x, cy = y
    let attrs: [NSAttributedString.Key: Any] = [.font: fnt(label, size), .foregroundColor: yellow, .kern: size * 0.12]
    for t in items {
        let s = NSAttributedString(string: t, attributes: attrs)
        let tw = s.size().width, th = s.size().height
        let w = tw + size * 1.5, h = th + size * 0.7
        if cx + w > x + maxWidth { cx = x; cy -= h + size * 0.45 }
        let r = CGRect(x: cx, y: cy, width: w, height: h)
        let path = CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
        ctx.addPath(path); ctx.setFillColor(yellow.withAlphaComponent(0.12).cgColor); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(yellow.withAlphaComponent(0.85).cgColor); ctx.setLineWidth(3); ctx.strokePath()
        s.draw(at: CGPoint(x: cx + size * 0.75, y: cy + size * 0.35))
        cx += w + size * 0.5
    }
}

func device(_ ctx: CGContext, _ shot: NSImage, _ rect: CGRect, radius: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 90, color: NSColor(white: 0, alpha: 0.7).cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
    shot.draw(in: rect); ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerWidth: radius + 4, cornerHeight: radius + 4, transform: nil))
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.28).cgColor); ctx.setLineWidth(8); ctx.strokePath()
}

enum Kind { case phone(String), landscape(String), languages, specs, sync }
struct Item { let kind: Kind; var headSize: CGFloat = 215; let head: String; let sub: String; let chips: [String]; let out: String }

func render(_ it: Item, base: String, out dir: String) {
    var landscape = false
    if case .landscape = it.kind { landscape = true }
    if landscape { W = 2868; H = 1320 } else { W = 1320; H = 2868 }
    let img = canvas { ctx in
        if landscape {
            background(ctx, glow: CGPoint(x: W * 0.62, y: H * 0.3))
            let m: CGFloat = 130
            headline(it.head, size: 150, align: .left).draw(in: CGRect(x: m, y: H - 235, width: W - 2 * m, height: 180))
            para(it.sub, size: 50, align: .left).draw(in: CGRect(x: m, y: H - 330, width: 1500, height: 80))
            pills(ctx, it.chips, x: 1750, y: H - 322, size: 38, maxWidth: W - 1750 - m)
            if case .landscape(let raw) = it.kind {
                let shot = NSImage(contentsOfFile: "\(base)/raw/\(raw).png")!
                let w: CGFloat = 2330, h = w * 1320 / 2868
                device(ctx, shot, CGRect(x: (W - w) / 2, y: H - 400 - h, width: w, height: h), radius: 110)
            }
        } else {
            background(ctx, glow: CGPoint(x: W * 0.5, y: H * 0.42))
            let m: CGFloat = 90
            headline(it.head, size: it.headSize, align: .left).draw(in: CGRect(x: m, y: H - 560, width: W - 2 * m, height: 470))
            para(it.sub, size: 54, align: .left).draw(in: CGRect(x: m, y: H - 760, width: W - 2 * m - 40, height: 170))
            pills(ctx, it.chips, x: m, y: H - 880, size: 40, maxWidth: W - 2 * m)
            switch it.kind {
            case .phone(let raw):
                let shot = NSImage(contentsOfFile: "\(base)/raw/\(raw).png")!
                let w: CGFloat = 1030, h = w * 2868 / 1320
                device(ctx, shot, CGRect(x: (W - w) / 2, y: H - 980 - h, width: w, height: h), radius: 118)
            case .languages:
                let lines = ["ENGLISH · ESPAÑOL", "DEUTSCH · FRANÇAIS", "ITALIANO · PORTUGUÊS", "日本語 · 한국어", "普通话 · 粵語", "TÜRKÇE · +20 MORE"]
                var y = H - 1180
                for (i, l) in lines.enumerated() {
                    let a = headline(l, size: 118, align: .center, color: i % 2 == 0 ? .white : yellow)
                    a.draw(in: CGRect(x: 20, y: y - 140, width: W - 40, height: 150)); y -= 290
                    _ = i
                }
            case .specs:
                let lines = ["4K · 60 FPS", "HDR", "PRORES", "HEVC · H.264"]
                let sizes: [CGFloat] = [230, 230, 230, 150]
                var y = H - 1180
                for (i, l) in lines.enumerated() {
                    headline(l, size: sizes[i], align: .center, color: i == 0 ? yellow : .white).draw(in: CGRect(x: 20, y: y - 270, width: W - 40, height: 300)); y -= 330
                }
                para("Exposure, focus and white-balance locks. Torch, zoom and stabilization.", size: 50, align: .center, alpha: 0.82).draw(in: CGRect(x: 120, y: 190, width: W - 240, height: 160))
                para("Available with Sightline Pro", size: 44, align: .center, alpha: 0.55).draw(in: CGRect(x: 120, y: 110, width: W - 240, height: 60))
            case .sync:
                let mac = NSImage(contentsOfFile: "\(base)/raw/maclib.png")!
                let mw: CGFloat = 1180, mh = mw * 1160 / 1520
                device(ctx, mac, CGRect(x: 70, y: H - 1010 - mh, width: mw, height: mh), radius: 34)
                let phone = NSImage(contentsOfFile: "\(base)/raw/picker.png")!
                let pw: CGFloat = 620, ph = pw * 2868 / 1320
                device(ctx, phone, CGRect(x: W - pw - 50, y: -ph * 0.16, width: pw, height: ph), radius: 80)
            default: break
            }
        }
    }
    png(img, to: "\(dir)/\(it.out)")
}

let a = CommandLine.arguments
let items: [Item] = [
    Item(kind: .phone("rec1"), head: "SPEAK.\n*IT SCROLLS.*", sub: "The teleprompter that follows your voice. Scrolls at your pace, pauses when you do.", chips: ["VOICE FOLLOWING", "31 LANGUAGES"], out: "1-voice.png"),
    Item(kind: .landscape("landscape1"), head: "SHOOT WIDE. *CROP TALL.*", sub: "A live 9:16 guide with rule-of-thirds lines, right in the viewfinder.", chips: ["9:16 GUIDE", "RULE OF THIRDS", "LEVEL LINE"], out: "2-crop-guide.png"),
    Item(kind: .phone("rec2"), head: "LOOK AT\nTHE *LENS.*", sub: "Your script sits right under the camera, so your eyes never leave the viewer.", chips: ["PORTRAIT", "LANDSCAPE", "FRONT + BACK CAMERA"], out: "3-eye-contact.png"),
    Item(kind: .landscape("landscape2"), head: "LANDSCAPE *OR* PORTRAIT.", sub: "The prompter adapts to the way you shoot.", chips: ["ZOOM LENSES", "MONO AUDIO", "ANY ANGLE"], out: "4-landscape.png"),
    Item(kind: .languages, head: "SPEAK ANY\n*LANGUAGE.*", sub: "31 languages. Many recognize speech on your device, no connection needed.", chips: ["ON-DEVICE", "31 LANGUAGES"], out: "5-languages.png"),
    Item(kind: .sync, headSize: 128, head: "WRITE ON MAC.\n*RECORD ON IPHONE.*", sub: "Scripts sync through iCloud. Import Word, PDF, Markdown, RTF and more.", chips: ["ICLOUD", "MAC + IPHONE"], out: "6-sync.png"),
    Item(kind: .phone("camera"), head: "TUNE IT TO\n*YOUR EYES.*", sub: "Size, spacing, speed, microphone. Add [[delivery cues]] you see but never read.", chips: ["USB MIC", "WORDS PER MINUTE", "CUES"], out: "7-tune.png"),
    Item(kind: .specs, head: "STUDIO\n*QUALITY.*", sub: "Record straight to Photos in the quality your channel deserves.", chips: ["UP TO 4K", "PRO CODECS"], out: "8-studio.png"),
]
for it in items { render(it, base: a[1], out: a[2]) }
