// Builds the MacBook Pro 14-inch screen (1512 × 982 pt at 2x) around a panel frame the Mac app rendered itself
// (SIGHTLINE_RENDER_FRAMES): desktop, Finder menu bar, a camera window, and the panel at the top centre where
// NotchPanel puts it (520 × 220 pt by default). The notch comes from Apple's bezel, drawn over this later.
// camera.png is one picture (a recording: camera window with a REC timer) or several, comma separated (a video call:
// the speaker first, then the others, in a generic call window).
// Usage: swift mac-screen.swift panel.png camera.png[,more.png...] out.png [clock] [menus]
import AppKit

let args = CommandLine.arguments
/// "none" leaves the panel out (a video overlays the app's own frames there later).
let panel = args[1] == "none" ? nil : NSImage(contentsOfFile: args[1])!
// "path@0.62" crops around that horizontal position (the face) instead of the middle.
let cameraSpecs = args[2].split(separator: ",").map { spec -> (NSImage, CGFloat) in
    // Only a trailing "@<number>" is a focus; paths themselves may contain "@".
    if let at = spec.lastIndex(of: "@"), let focus = Double(spec[spec.index(after: at)...]) {
        return (NSImage(contentsOfFile: String(spec[..<at]))!, CGFloat(focus))
    }
    return (NSImage(contentsOfFile: String(spec))!, 0.5)
}
let cameras = cameraSpecs.map(\.0)
let clock = args.count > 4 ? args[4] : "Fri 21 Nov  9:41"
/// Finder's menu titles in the page language, comma separated, the app name first.
let menus = (args.count > 5 ? args[5] : "Finder,File,Edit,View,Go,Window,Help").split(separator: ",").map(String.init)
let size = CGSize(width: 1512, height: 982)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3024, pixelsHigh: 1964, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
// A y-down context that AppKit knows is flipped, so text and images draw upright.
let base = NSGraphicsContext(bitmapImageRep: rep)!
base.cgContext.translateBy(x: 0, y: size.height)
base.cgContext.scaleBy(x: 1, y: -1)  // rep.size in points already carries the 2x
NSGraphicsContext.current = NSGraphicsContext(cgContext: base.cgContext, flipped: true)
let ctx = NSGraphicsContext.current!

// Desktop: a plain dark wallpaper.
NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.20, alpha: 1), NSColor(srgbRed: 0.03, green: 0.04, blue: 0.07, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), relativeCenterPosition: NSPoint(x: 0, y: 0.2))

func cover(_ image: NSImage, in rect: NSRect, radius: CGFloat, focusX: CGFloat = 0.5) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    let k = max(rect.width / image.size.width, rect.height / image.size.height)
    let drawn = NSSize(width: image.size.width * k, height: image.size.height * k)
    // Tall portraits are cropped around the face (eyes about 37 % down), not the middle.
    let y = drawn.height > rect.height ? min(max(rect.midY - drawn.height * 0.37, rect.maxY - drawn.height), rect.minY) : rect.midY - drawn.height / 2
    let x = min(max(rect.midX - drawn.width * focusX, rect.maxX - drawn.width), rect.minX)
    image.draw(in: NSRect(x: x, y: y, width: drawn.width, height: drawn.height),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
}
func glyph(_ name: String, _ center: NSPoint, size: CGFloat = 17, color: NSColor = .white) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return }
    let tinted = NSImage(size: base.size, flipped: false) { r in base.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
    tinted.draw(in: NSRect(x: center.x - base.size.width / 2, y: center.y - base.size.height / 2, width: base.size.width, height: base.size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
let meeting = cameras.count > 1
// The window, centred under the panel.
let win = meeting ? NSRect(x: 56, y: 46, width: size.width - 112, height: size.height - 46 - 70) : NSRect(x: (size.width - 860) / 2, y: 252, width: 860, height: 512)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.set()
NSColor(white: meeting ? 0.09 : 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: win, xRadius: 12, yRadius: 12).fill()
NSGraphicsContext.restoreGraphicsState()
if meeting {
    // Call window: a 2 x 2 grid, the speaker (you, reading) outlined, and the usual call controls below.
    // A 2 x 2 gallery of 16:9 tiles, centred in the window above the controls.
    let area = NSRect(x: win.minX + 16, y: win.minY + 36, width: win.width - 32, height: win.height - 36 - 76)
    let gap: CGFloat = 8
    var tw = (area.width - gap) / 2, th = tw * 9 / 16
    if 2 * th + gap > area.height { th = (area.height - gap) / 2; tw = th * 16 / 9 }
    let grid = NSRect(x: area.midX - tw - gap / 2, y: area.midY - th - gap / 2, width: 2 * tw + gap, height: 2 * th + gap)
    for (i, image) in cameras.prefix(4).enumerated() {
        let tile = NSRect(x: grid.minX + CGFloat(i % 2) * (tw + gap), y: grid.minY + CGFloat(i / 2) * (th + gap), width: tw, height: th)
        cover(image, in: tile, radius: 10, focusX: cameraSpecs[i].1)
        if i == 0 {
            NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).setStroke()
            let ring = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 9, yRadius: 9)
            ring.lineWidth = 3
            ring.stroke()
        }
        if i > 0 {
            let badge = NSRect(x: tile.minX + 10, y: tile.maxY - 34, width: 24, height: 24)
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: badge).fill()
            glyph("mic.slash.fill", NSPoint(x: badge.midX, y: badge.midY), size: 11)
        }
    }
    let y = win.maxY - 38
    for (j, name) in ["mic.fill", "video.fill", "rectangle.on.rectangle", "face.smiling", "ellipsis"].enumerated() {
        let c = NSPoint(x: win.midX - 170 + CGFloat(j) * 64, y: y)
        NSColor(white: 0.24, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 21, y: c.y - 21, width: 42, height: 42)).fill()
        glyph(name, c)
    }
    let leave = NSRect(x: win.midX + 170, y: y - 21, width: 64, height: 42)
    NSColor(srgbRed: 0.92, green: 0.26, blue: 0.21, alpha: 1).setFill()
    NSBezierPath(roundedRect: leave, xRadius: 21, yRadius: 21).fill()
    glyph("phone.down.fill", NSPoint(x: leave.midX, y: leave.midY))
} else {
    let picture = NSRect(x: win.minX, y: win.minY + 28, width: win.width, height: win.height - 28)
    cover(cameras[0], in: picture, radius: 0)
    // Recording: a red dot and the running time.
    let pill = NSRect(x: picture.minX + 16, y: picture.minY + 16, width: 84, height: 26)
    NSColor.black.withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 13, yRadius: 13).fill()
    NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: pill.minX + 11, y: pill.midY - 4.5, width: 9, height: 9)).fill()
    let t = NSAttributedString(string: "00:12", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
    t.draw(at: NSPoint(x: pill.minX + 28, y: pill.midY - t.size().height / 2))
}
for (i, color) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                   NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: win.minX + 14 + CGFloat(i) * 20, y: win.minY + 8, width: 12, height: 12)).fill()
}

// Menu bar: 32 pt on notched MacBooks, translucent over the wallpaper.
NSColor(white: 0, alpha: 0.32).setFill()
NSRect(x: 0, y: 0, width: size.width, height: 32).fill()
func text(_ s: String, _ x: CGFloat, bold: Bool = false, right: Bool = false) -> CGFloat {
    let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: bold ? .bold : .medium),
                                                      .foregroundColor: NSColor.white])
    let w = a.size().width
    a.draw(at: NSPoint(x: right ? x - w : x, y: 16 - a.size().height / 2))
    return w
}
if let apple = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
    let tinted = NSImage(size: apple.size, flipped: false) { r in apple.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
    tinted.draw(in: NSRect(x: 20, y: 16 - apple.size.height / 2, width: apple.size.width, height: apple.size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
var x: CGFloat = 52
x += text(menus[0], x, bold: true) + 20
for item in menus.dropFirst() { x += text(item, x) + 20 }
_ = text(clock, size.width - 18, right: true)

// The panel, flush with the top edge, centred (NotchPanel.apply with xOffset 0).
let p = NSRect(x: (size.width - 520) / 2, y: 0, width: 520, height: 220)
// CALayer.render(in:) rounds all four corners; on screen only the bottom ones are (maskedCorners), so square the top.
NSColor.black.setFill()
NSRect(x: p.minX, y: 0, width: p.width, height: 20).fill()
panel?.draw(in: p, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
_ = ctx
