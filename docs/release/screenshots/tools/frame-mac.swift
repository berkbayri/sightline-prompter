// Builds the Mac App Store screenshots (2880x1800, 16:10) from raw captures in <base>/raw.
// Usage: swiftc -O frame-mac.swift -o frame-mac && ./frame-mac <base-dir> <out-dir>
import AppKit
import CoreGraphics

let W: CGFloat = 2880, H: CGFloat = 1800
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
    rep.size = NSSize(width: W, height: H)
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
        out.append(NSAttributedString(string: String(part), attributes: [.font: fnt(display, size), .foregroundColor: accent ? yellow : color, .paragraphStyle: p, .kern: size * 0.005]))
        accent.toggle()
    }
    return out
}
func para(_ text: String, size: CGFloat, align: NSTextAlignment, alpha: CGFloat = 0.82) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineHeightMultiple = 1.18
    return NSAttributedString(string: text, attributes: [.font: fnt(body, size), .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: p])
}
/// Draw text with its TOP edge at `top` (distance from canvas top).
func drawTop(_ s: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
    let b = s.boundingRect(with: NSSize(width: width, height: 4000), options: [.usesLineFragmentOrigin])
    let h = ceil(b.height) + 8
    s.draw(in: CGRect(x: x, y: H - top - h, width: width, height: h))
    return h
}

func background(_ ctx: CGContext, glow: CGPoint) {
    ctx.setFillColor(ink.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let cs = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: cs, colors: [yellow.withAlphaComponent(0.34).cgColor, yellow.withAlphaComponent(0.10).cgColor, yellow.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(g, startCenter: glow, startRadius: 0, endCenter: glow, endRadius: max(W, H) * 0.62, options: [])
    let v = CGGradient(colorsSpace: cs, colors: [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.55).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(v, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: min(W, H) * 0.5, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: max(W, H) * 0.85, options: [])
}

/// Chip row from (x, top). Wraps inside maxWidth.
func pills(_ ctx: CGContext, _ items: [String], x: CGFloat, top: CGFloat, size: CGFloat, maxWidth: CGFloat) {
    var cx = x, cy = H - top
    let attrs: [NSAttributedString.Key: Any] = [.font: fnt(label, size), .foregroundColor: yellow, .kern: size * 0.12]
    for t in items {
        let s = NSAttributedString(string: t, attributes: attrs)
        let tw = s.size().width, th = s.size().height
        let w = tw + size * 1.5, h = th + size * 0.7
        if cx + w > x + maxWidth { cx = x; cy -= h + size * 0.45 }
        let r = CGRect(x: cx, y: cy - h, width: w, height: h)
        let path = CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
        ctx.addPath(path); ctx.setFillColor(yellow.withAlphaComponent(0.12).cgColor); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(yellow.withAlphaComponent(0.85).cgColor); ctx.setLineWidth(3); ctx.strokePath()
        s.draw(at: CGPoint(x: cx + size * 0.75, y: cy - h + size * 0.35))
        cx += w + size * 0.5
    }
}

/// Image with a rounded frame, soft shadow; rect in CG coordinates.
func card(_ ctx: CGContext, _ img: NSImage, _ rect: CGRect, radius: CGFloat, frame: Bool = true) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 90, color: NSColor(white: 0, alpha: 0.7).cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
    img.draw(in: rect)
    ctx.restoreGState()
    if frame {
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerWidth: radius + 3, cornerHeight: radius + 3, transform: nil))
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.24).cgColor); ctx.setLineWidth(6); ctx.strokePath()
    }
}

/// Top of a MacBook display (wallpaper, menu bar, notch) cropped by the canvas bottom. Content gets the full display rect (the panel hangs from its top edge).
@discardableResult
func macScreenTop(_ ctx: CGContext, x: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat, dim: Bool = false, content: ((CGContext, CGRect) -> Void)? = nil) -> CGRect {
    let r = CGRect(x: x, y: H - top - h, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 90, color: NSColor(white: 0, alpha: 0.7).cgColor)
    ctx.addPath(CGPath(roundedRect: r.insetBy(dx: -22, dy: -22), cornerWidth: 70, cornerHeight: 70, transform: nil))
    ctx.setFillColor(NSColor(white: 0.04, alpha: 1).cgColor); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 50, cornerHeight: 50, transform: nil)); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let wall = CGGradient(colorsSpace: cs, colors: [NSColor(red: 0.16, green: 0.14, blue: 0.09, alpha: 1).cgColor, NSColor(red: 0.07, green: 0.075, blue: 0.10, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(wall, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.minY), options: [])
    // menu bar
    let bar: CGFloat = 58
    ctx.setFillColor(NSColor(white: 0, alpha: dim ? 0.55 : 0.35).cgColor)
    ctx.fill(CGRect(x: r.minX, y: r.maxY - bar, width: w, height: bar))
    ctx.setFillColor(NSColor(white: 1, alpha: 0.35).cgColor)
    for i in 0..<5 { ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + 150 + CGFloat(i) * 110, y: r.maxY - bar / 2 - 6, width: 70, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath() }
    for i in 0..<3 { ctx.addPath(CGPath(roundedRect: CGRect(x: r.maxX - 130 - CGFloat(i) * 72, y: r.maxY - bar / 2 - 6, width: 40, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath() }
    // notch
    let nw: CGFloat = 330
    let notch = CGRect(x: r.midX - nw / 2, y: r.maxY - bar, width: nw, height: bar)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(CGPath(roundedRect: notch.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: 30), cornerWidth: 30, cornerHeight: 30, transform: nil)); ctx.fillPath()
    content?(ctx, r)
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: r.insetBy(dx: -3, dy: -3), cornerWidth: 53, cornerHeight: 53, transform: nil))
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.24).cgColor); ctx.setLineWidth(6); ctx.strokePath()
    return r
}

func header(_ ctx: CGContext, head: String, sub: String, chips: [String], headSize: CGFloat = 140, subWidth: CGFloat = 1700) {
    let m: CGFloat = 130
    let hh = drawTop(headline(head, size: headSize, align: .left), x: m, top: 90, width: W - 2 * m)
    let sh = drawTop(para(sub, size: 46, align: .left), x: m, top: 90 + hh + 24, width: subWidth)
    pills(ctx, chips, x: 1950, top: 90 + hh + 30, size: 36, maxWidth: W - 1950 - m)
    _ = sh
}

struct Item { let id: String; let head: String; let sub: String; let chips: [String]; let out: String }

func render(_ it: Item, base: String, out dir: String) {
    func load(_ n: String) -> NSImage { NSImage(contentsOfFile: "\(base)/raw/\(n).png")! }
    let img = canvas { ctx in
        background(ctx, glow: CGPoint(x: W * 0.5, y: H * 0.35))
        header(ctx, head: it.head, sub: it.sub, chips: it.chips)
        let contentTop: CGFloat = 690
        switch it.id {
        case "notch":
            let panel = load("panel_hover")
            let sw: CGFloat = 2220
            macScreenTop(ctx, x: (W - sw) / 2, top: contentTop, w: sw, h: H - contentTop + 120) { c, under in
                let pw: CGFloat = 1500, ph = pw * 520 / 1280
                let lib = load("library"), lw: CGFloat = 1560, lh = lw * 1360 / 1800
                card(c, lib, CGRect(x: under.midX - lw / 2, y: under.maxY - ph - 110 - lh, width: lw, height: lh), radius: 30, frame: false)
                card(c, panel, CGRect(x: under.midX - pw / 2, y: under.maxY - ph, width: pw, height: ph), radius: 30, frame: false)
            }
        case "calls":
            let photo = load("scene1")
            let pw: CGFloat = 2300, ph = pw * 864 / 1536
            card(ctx, photo, CGRect(x: (W - pw) / 2, y: H - 640 - ph, width: pw, height: ph), radius: 60)
        case "hidden":
            let panel = load("panel_clean")
            let cw: CGFloat = 1260, gap: CGFloat = 100
            let x0 = (W - 2 * cw - gap) / 2
            for (i, title) in ["YOU SEE", "THEY SEE"].enumerated() {
                let x = x0 + CGFloat(i) * (cw + gap)
                let t = headline(title, size: 66, align: .left, color: i == 0 ? yellow : NSColor(white: 1, alpha: 0.7))
                _ = drawTop(t, x: x + 10, top: 660, width: 600)
                macScreenTop(ctx, x: x, top: 760, w: cw, h: H - 760 + 100, dim: i == 1) { c, under in
                    // same shared slide on both sides: neutral blocks, no readable content
                    c.setFillColor(NSColor(white: 1, alpha: 0.12).cgColor)
                    c.addPath(CGPath(roundedRect: CGRect(x: under.minX + 120, y: under.maxY - 330, width: 620, height: 48), cornerWidth: 24, cornerHeight: 24, transform: nil)); c.fillPath()
                    c.setFillColor(NSColor(white: 1, alpha: 0.07).cgColor)
                    for k in 0..<3 { c.addPath(CGPath(roundedRect: CGRect(x: under.minX + 120, y: under.maxY - 420 - CGFloat(k) * 70, width: 960 - CGFloat(k) * 160, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil)); c.fillPath() }
                    c.setFillColor(NSColor(white: 1, alpha: 0.14).cgColor)
                    for k in 0..<6 { let bh = 160 + CGFloat((k * 97) % 230); c.fill(CGRect(x: under.minX + 140 + CGFloat(k) * 170, y: under.maxY - 1000, width: 100, height: bh)) }
                    if i == 0 {
                        let pw: CGFloat = 900, ph = pw * 520 / 1280
                        card(c, panel, CGRect(x: under.midX - pw / 2, y: under.maxY - ph, width: pw, height: ph), radius: 22, frame: false)
                    }
                }
            }
        case "languages":
            let panel = load("panel_hover")
            let pw: CGFloat = 1500, ph = pw * 520 / 1280
            card(ctx, panel, CGRect(x: 130, y: H - contentTop - 40 - ph, width: pw, height: ph), radius: 40)
            let lines = ["ENGLISH · ESPAÑOL", "DEUTSCH · FRANÇAIS", "ITALIANO · PORTUGUÊS", "日本語 · 한국어", "普通话 · 粵語", "TÜRKÇE · +20 MORE"]
            var top: CGFloat = contentTop + 10
            for (i, l) in lines.enumerated() {
                _ = drawTop(headline(l, size: 112, align: .center, color: i % 2 == 0 ? .white : yellow), x: 1700, top: top, width: W - 1700 - 80)
                top += 150
            }
            _ = drawTop(para("Available with Sightline Pro", size: 44, align: .left, alpha: 0.55), x: 130, top: contentTop + 40 + ph + 120, width: 1500)
        case "sync":
            let lib = load("library")
            let lw: CGFloat = 1800, lh = lw * 1360 / 1800
            card(ctx, lib, CGRect(x: 130, y: H - 700 - lh, width: lw, height: lh), radius: 36)
            // right column: delivery cue explainer, raw block shown as the app shows it
            let cx: CGFloat = 2090
            _ = drawTop(headline("IMPORT\n*ANYTHING.*", size: 120, align: .left), x: cx, top: 760, width: 700)
            pills(ctx, ["WORD", "PDF", "MARKDOWN", "RTF", "HTML", "ODT"], x: cx, top: 1050, size: 40, maxWidth: 700)
            _ = drawTop(para("Add [[delivery cues]] you see but never read.", size: 46, align: .left), x: cx, top: 1320, width: 660)
        case "tune":
            let set = load("settings_b")
            let sw: CGFloat = 1180, sh = sw * 1416 / 1080
            card(ctx, set, CGRect(x: W - 130 - sw, y: H - 700 - sh, width: sw, height: sh), radius: 32)
            let lines = [("148 WPM", true), ("2:14 LEFT", false), ("DUALSENSE", false), ("[[PAUSE]]", true)]
            var top: CGFloat = contentTop + 20
            for (l, acc) in lines {
                _ = drawTop(headline(l, size: 210, align: .left, color: acc ? yellow : .white), x: 130, top: top, width: 1500)
                top += 215
            }
            _ = drawTop(para("Available with Sightline Pro", size: 44, align: .left, alpha: 0.55), x: 130, top: top + 40, width: 1500)
        default: break
        }
    }
    png(img, to: "\(dir)/\(it.out)")
}

let a = CommandLine.arguments
let items = [
    Item(id: "notch", head: "TELEPROMPTER\n*UNDER THE NOTCH.*", sub: "Your script sits right below the camera, so your eyes never leave the lens.", chips: ["UNDER THE NOTCH", "ALWAYS ON TOP"], out: "1-notch.png"),
    Item(id: "calls", head: "PRESENT WITH\n*CONFIDENCE.*", sub: "Look at your audience on every video call, keynote and recording.", chips: ["VIDEO CALLS", "KEYNOTES", "WEBINARS"], out: "2-present.png"),
    Item(id: "hidden", head: "INVISIBLE TO\n*EVERYONE ELSE.*", sub: "Hide the prompter from screen sharing and recording. Only you see your script.", chips: ["HIDDEN FROM SHARING", "HIDDEN FROM RECORDING"], out: "3-hidden.png"),
    Item(id: "languages", head: "SPEAK ANY\n*LANGUAGE.*", sub: "Voice following in 31 languages, many of them on-device.", chips: ["VOICE FOLLOWING", "31 LANGUAGES"], out: "4-languages.png"),
    Item(id: "sync", head: "WRITE ON MAC.\n*RECORD ON IPHONE.*", sub: "Scripts sync through iCloud. Import Word, PDF, Markdown and more.", chips: ["ICLOUD", "MAC + IPHONE"], out: "5-sync.png"),
    Item(id: "tune", head: "DIAL IN\n*YOUR PACE.*", sub: "Live words per minute and time left. Drive it with a DualSense controller.", chips: ["WORDS PER MINUTE", "DUALSENSE"], out: "6-pace.png"),
]
for it in items { render(it, base: a[1], out: a[2]) }
