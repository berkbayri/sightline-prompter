import AppKit
import Aligner
import CoreImage
import SightlineCore

// Renders the iPhone camera prompter the way iOS/Sources/PrompterUIView.swift and PrompterScreen.swift draw it.
// Text building, layout geometry, scrolling and typography come from the shared app code; the draw pass is a
// line-by-line port of PrompterUIView.draw(_:). Usage: prompter-render config.json

struct Config: Decodable {
    var out: String
    var width: CGFloat = 402
    var height: CGFloat = 874
    var scale: CGFloat = 3
    /// Safe-area insets in points: top, left, bottom, right (iPhone 17 Pro portrait: 62, 0, 34, 0).
    var insets: [CGFloat] = [62, 0, 34, 0]
    var camera = true
    var script: String
    var language = "en-US"
    var fontSize: CGFloat = 39
    var background: String?
    var fps: Double = 30
    /// 0 renders one still at `stillAt` seconds of speech.
    var duration: Double = 0
    var stillAt: Double = 4
    /// Speech starts this many seconds into the clip.
    var lead: Double = 0.6
    var recording = true
    var recordStart = 11
    var controls = true
    var tracking = true
    var roll: Double = -2
    var pitch: Double = 6
    var portraitLines: CGFloat = 3
    var videoAspect: CGFloat = 16.0 / 9.0
    /// Still mode: show this word as current with the scroll settled on it, instead of a speech time.
    var cursor: Int = -1
    /// false draws only the picture and the app's chrome; the website lays the live prompter over it.
    var text = true
    /// Prints the script's words as the app segments them (ScriptTokenizer) as JSON, then exits.
    var dump = false
}

let args = CommandLine.arguments
guard args.count > 1, let data = FileManager.default.contents(atPath: args[1]) else {
    FileHandle.standardError.write("usage: prompter-render config.json\n".data(using: .utf8)!)
    exit(2)
}
// Decodable ignores property defaults, so the defaults are merged under the given keys first.
let defaults: [String: Any] = ["width": 402, "height": 874, "scale": 3, "insets": [62, 0, 34, 0], "camera": true, "language": "en-US",
                               "fontSize": 39, "fps": 30, "duration": 0, "stillAt": 4, "lead": 0.6, "recording": true, "recordStart": 11,
                               "controls": true, "tracking": true, "roll": -2, "pitch": 6, "portraitLines": 3, "videoAspect": 16.0 / 9.0, "cursor": -1, "text": true, "dump": false]
let given = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let config = try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: defaults.merging(given) { $1 }))

// MARK: - Colors (PrompterUIView, PrompterScreen, Brand.swift)

let dimColor = NSColor(white: 1, alpha: CGFloat(PrompterTypography.colorReadAlpha))
let normalColor = NSColor(white: 1, alpha: 1)
let currentColor = NSColor(srgbRed: 1, green: 0.86, blue: 0.4, alpha: 1)
let highlightFill = NSColor(srgbRed: 1, green: 0.86, blue: 0.4, alpha: 0.16)
let readingLineColor = NSColor(white: 1, alpha: 0.18)
/// SwiftUI Color.yellow in dark appearance (Color.sightline).
let sightline = NSColor(srgbRed: 1, green: 0.839, blue: 0.039, alpha: 1)

// MARK: - Speech timeline

/// Seconds each word takes to say, plus the pause after it. Spaced languages ~155 wpm, CJK ~7 characters a second.
func wordTimes(_ tokens: [String], spaced: Bool) -> [Double] {
    var t = 0.0
    var ends: [Double] = []
    for word in tokens {
        let letters = Double(word.filter { $0.isLetter || $0.isNumber }.count)
        t += spaced ? 0.15 + 0.052 * letters : 0.145 * max(letters, 1)
        ends.append(t)
        if let last = word.last {
            if ".!?。！？".contains(last) { t += 0.45 } else if ",;:，、；：".contains(last) { t += 0.2 }
        }
    }
    return ends
}

// MARK: - Bitmap helpers

func loadCI(_ path: String) -> CIImage? {
    CIImage(contentsOf: URL(fileURLWithPath: path))
}

let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

/// The image scaled to fill `size` (points) and cropped to it, as a bitmap at `scale`.
func filled(_ image: CIImage, size: CGSize, scale: CGFloat, blur: CGFloat = 0) -> CGImage {
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let k = max(target.width / image.extent.width, target.height / image.extent.height)
    var scaled = image.transformed(by: CGAffineTransform(scaleX: k, y: k))
    scaled = scaled.transformed(by: CGAffineTransform(translationX: -(scaled.extent.width - target.width) / 2 - scaled.extent.minX,
                                                      y: -(scaled.extent.height - target.height) / 2 - scaled.extent.minY))
    if blur > 0 {
        scaled = scaled.clampedToExtent().applyingGaussianBlur(sigma: blur * scale)
    }
    return ci.createCGImage(scaled, from: CGRect(origin: .zero, size: target))!
}

/// Draws a CGImage into a y-down context.
func draw(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: size, weight: weight))!
    return NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func drawCentered(_ image: NSImage, at center: CGPoint) {
    let rect = CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2,
                      width: image.size.width, height: image.size.height)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

// MARK: - Render

if config.dump {
    let language = ScriptLanguage.named(config.language)
    let parsed = ScriptTokenizer.parse(config.script, language: language)
    let out: [String: Any] = ["spaced": language.spaced, "words": parsed.tokens.map(\.display), "paragraphs": parsed.tokens.map(\.paragraph)]
    print(String(data: try JSONSerialization.data(withJSONObject: out), encoding: .utf8)!)
    exit(0)
}

MainActor.assumeIsolated {
    let size = CGSize(width: config.width, height: config.height)
    let isLandscape = size.width > size.height
    let insets = ScreenInsets(top: config.insets[0], left: config.insets[1], bottom: config.insets[2], right: config.insets[3])
    let language = ScriptLanguage.named(config.language)
    let fontSize = config.fontSize
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    // PrompterScreen.lineHeight: UIFont.lineHeight × line spacing.
    let lineHeight = (font.ascender - font.descender + font.leading) * CGFloat(PrompterTypography.lineHeightMultiple)
    let band = CameraLayout.RecordingBand(lineHeight: lineHeight, portraitLines: config.portraitLines, videoAspect: config.videoAspect)
    let layout = CameraLayout.make(size: size, insets: insets, isLandscape: isLandscape, cameraEdge: isLandscape ? .left : .top,
                                   readingDistanceCm: 0.5, landscapeColumnWidth: 480, recording: band)
    let textFrame = layout.textFrame
    let readingLineY = layout.readingLineY

    // Text storage, exactly as PrompterUIView.buildText / relayout.
    let storage = NSTextStorage()
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: max(textFrame.width, 40), height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)

    var cursor = 0
    func color(_ index: Int) -> NSColor { index < cursor ? dimColor : index == cursor ? currentColor : normalColor }
    let built = PrompterText.build(script: config.script, language: language, fontSize: fontSize, cursor: 0, wordColor: color)
    storage.setAttributedString(built.attributed)
    manager.ensureLayout(for: container)
    let wordRects = built.words.map { word in
        manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: word.range, actualCharacterRange: nil), in: container)
    }
    func recolor() {
        storage.beginEditing()
        for (i, word) in built.words.enumerated() { storage.addAttribute(.foregroundColor, value: color(i), range: word.range) }
        for cue in built.cues {
            storage.addAttribute(.foregroundColor, value: PrompterText.cueColor(wordsBefore: cue.wordsBefore, cursor: cursor), range: cue.range)
            storage.addAttribute(.backgroundColor, value: PrompterText.cueBackground(wordsBefore: cue.wordsBefore, cursor: cursor), range: cue.range)
        }
        storage.endEditing()
    }

    let scroll = ScrollEngine()
    let contentTop = textFrame.minY
    if let last = wordRects.last { scroll.maxOffset = max(0, contentTop + last.midY - readingLineY) }
    func targetOffset(_ i: Int) -> CGFloat { contentTop + wordRects[i].midY - readingLineY }

    let parsed = ScriptTokenizer.parse(config.script, language: language)
    let ends = wordTimes(parsed.tokens.map(\.display), spaced: language.spaced)
    /// The word being read at speech time t: the first one not yet finished, seen 0.15 s late like recognition.
    func cursorAt(_ t: Double) -> Int { min(ends.firstIndex { $0 > t - 0.15 } ?? ends.count - 1, wordRects.count - 1) }

    // Camera picture: the preview frame and the dimmed, blurred backdrop behind it (PrompterScreen.previewBackdrop).
    let scale = config.scale
    let pixel = CGSize(width: size.width * scale, height: size.height * scale)
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
    func makeContext() -> CGContext {
        let ctx = CGContext(data: nil, width: Int(pixel.width), height: Int(pixel.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: pixel.height)
        ctx.scaleBy(x: scale, y: -scale)
        return ctx
    }

    var scene: CGImage?
    if config.camera, let path = config.background, let photo = loadCI(path), let preview = layout.previewFrame {
        let ctx = makeContext()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        draw(filled(photo, size: size, scale: scale, blur: 24 / 2), in: CGRect(origin: .zero, size: size), ctx)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: preview, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.clip()
        draw(filled(photo, size: preview.size, scale: scale), in: preview, ctx)
        ctx.restoreGState()
        scene = ctx.makeImage()
    }

    // Encoded luma behind a rect: 90th percentile over an 8 × 8 grid (FrameAnalyzer.luma).
    let sceneRep = scene.map { NSBitmapImageRep(cgImage: $0) }
    func luma(_ rect: CGRect) -> Double {
        guard let rep = sceneRep else { return 0 }
        var values: [Double] = []
        for i in 0..<8 { for j in 0..<8 {
            let x = Int((rect.minX + rect.width * (CGFloat(i) + 0.5) / 8) * scale)
            let y = Int((rect.minY + rect.height * (CGFloat(j) + 0.5) / 8) * scale)
            guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y) else { continue }
            values.append(0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent)
        } }
        guard !values.isEmpty else { return 0 }
        return values.sorted()[min(Int(Double(values.count) * 0.9), values.count - 1)]
    }

    func glyphMetrics(_ glyph: Int) -> (baseline: CGFloat, cap: CGFloat) {
        let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let char = manager.characterIndexForGlyph(at: glyph)
        let f = storage.attribute(.font, at: char, effectiveRange: nil) as? NSFont ?? font
        return (fragment.minY + manager.location(forGlyphAt: glyph).y, f.capHeight)
    }

    func lineRects(_ glyphs: NSRange, origin: CGPoint) -> [CGRect] {
        var lines: [CGRect] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, range, _ in
            let m = glyphMetrics(range.location)
            let b = PrompterTypography.highlightBand(baseline: Double(m.baseline), capHeight: Double(m.cap), fontSize: Double(fontSize))
            let box = CGRect(x: used.minX, y: CGFloat(b.top), width: used.width, height: CGFloat(b.bottom - b.top))
            lines.append(box.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -0.6 * fontSize, dy: -0.22 * fontSize))
        }
        return lines
    }

    // PrompterUIView.drawPlates. CG shadows are in device space, so blur and offset are scaled here.
    func drawPlates(_ ctx: CGContext, _ lines: [CGRect]) {
        guard let first = lines.first, let last = lines.last else { return }
        let sigma = 0.3 * fontSize, radius = 0.5 * fontSize
        let top = first.minY - 2 * sigma, bottom = max(last.maxY + 2 * sigma, top + 1)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let shift: CGFloat = 1000
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: -shift * scale, height: 0), blur: 2 * sigma * scale, color: NSColor.black.cgColor)
        let shape = CGMutablePath()
        for line in lines { shape.addPath(CGPath(roundedRect: line.offsetBy(dx: shift, dy: 0), cornerWidth: radius, cornerHeight: radius, transform: nil)) }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(shape)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.setBlendMode(.destinationIn)
        var colors = lines.map { NSColor.black.withAlphaComponent(CGFloat(PrompterTypography.scrimAlpha(backgroundLuma: luma($0)))).cgColor }
        var places = lines.map { min(max(($0.midY - top) / (bottom - top), 0), 1) }
        colors = [colors[0]] + colors + [colors[colors.count - 1]]
        places = [0] + places + [1]
        if let gradient = CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: places) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.endTransparencyLayer()
        ctx.setBlendMode(.normal)
    }

    // PrompterUIView.draw(_:)
    @MainActor func drawPrompter(_ ctx: CGContext) {
        let origin = CGPoint(x: textFrame.minX, y: contentTop - scroll.offset)
        let visible = CGRect(x: 0, y: scroll.offset - contentTop - 40, width: textFrame.width, height: textFrame.height + 80)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        if config.camera { drawPlates(ctx, lineRects(glyphs, origin: origin)) }

        let clipRect = CGRect(x: 0, y: textFrame.minY, width: size.width, height: textFrame.height + 0.3 * fontSize)
        ctx.saveGState()
        ctx.clip(to: clipRect)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        ctx.setFillColor(readingLineColor.cgColor)
        for x in [textFrame.minX - 12, textFrame.maxX + 2] { ctx.fill(CGRect(x: x, y: readingLineY, width: 10, height: 1)) }

        let wordRect = wordRects[cursor]
        let glyph = manager.glyphIndexForCharacter(at: built.words[cursor].range.location)
        let m = glyphMetrics(glyph)
        let b = PrompterTypography.highlightBand(baseline: Double(m.baseline), capHeight: Double(m.cap), fontSize: Double(fontSize))
        let pad = 0.12 * fontSize
        let highlight = CGRect(x: wordRect.minX - pad, y: CGFloat(b.top), width: wordRect.width + 2 * pad, height: CGFloat(b.bottom - b.top))
            .offsetBy(dx: origin.x, dy: origin.y)
        ctx.setFillColor(highlightFill.cgColor)
        ctx.addPath(CGPath(roundedRect: highlight, cornerWidth: 0.2 * fontSize, cornerHeight: 0.2 * fontSize, transform: nil))
        ctx.fillPath()

        manager.drawBackground(forGlyphRange: glyphs, at: origin)
        if config.camera {
            ctx.setShadow(offset: .zero, blur: 0.28 * fontSize * scale, color: NSColor.black.withAlphaComponent(0.55).cgColor)
            manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
            // UIKit's +y offset is downwards; this context's device space is y-up.
            ctx.setShadow(offset: CGSize(width: 0, height: -0.03 * fontSize * scale), blur: 0.07 * fontSize * scale,
                          color: NSColor.black.withAlphaComponent(0.9).cgColor)
        }
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)

        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setBlendMode(.destinationIn)
        let feather = min(0.6 * fontSize / clipRect.height, 0.5)
        let mask = CGGradient(colorsSpace: rgb, colors: [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor] as CFArray,
                              locations: [0, feather, 1 - feather, 1])!
        ctx.drawLinearGradient(mask, start: CGPoint(x: 0, y: clipRect.minY), end: CGPoint(x: 0, y: clipRect.maxY), options: [])
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // LevelOverlay, centered on the preview.
    func drawLevel(_ ctx: CGContext) {
        guard config.camera, let preview = layout.previewFrame else { return }
        let isLevel = abs(config.roll) <= 1, isPlumb = abs(config.pitch) <= 2
        let color = isLevel ? NSColor.systemGreen : NSColor(white: 1, alpha: 0.85)
        let length = min(preview.width, preview.height) * 0.14
        let c = CGPoint(x: preview.midX, y: preview.midY)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 1.5 * scale, color: NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(-config.roll * .pi / 180))
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: -length, y: -0.5, width: length * 2, height: 1), cornerWidth: 0.5, cornerHeight: 0.5, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.setStrokeColor((isPlumb ? NSColor.systemGreen : NSColor(white: 1, alpha: 0.6)).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13))
        let dy = CGFloat(max(-1, min(1, config.pitch / 20))) * 4
        ctx.setFillColor((isPlumb ? NSColor.systemGreen : NSColor(white: 1, alpha: 0.85)).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - 2, y: c.y - 2 + dy, width: 4, height: 4))
        let label = NSAttributedString(string: String(format: "%+.0f°", config.roll), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: color,
        ])
        let s = label.size()
        label.draw(at: CGPoint(x: c.x - s.width / 2, y: c.y + 18 - s.height / 2))
        ctx.restoreGState()
    }

    // ControlsPane: a row along the bottom in portrait, a column on the far edge in landscape, under the REC timer.
    // The iOS 26 Liquid Glass surface is approximated: blurred picture, light tint, edge.
    func drawControls(_ ctx: CGContext, seconds: Int) {
        guard config.controls else { return }
        let frame = layout.controlsFrame
        let size: CGFloat = isLandscape ? 38 : 40, record: CGFloat = isLandscape ? 54 : 58
        let statusHeight: CGFloat = config.recording ? 22 : 0
        let statusGap: CGFloat = config.recording ? 6 : 0
        let bar: CGRect
        let statusTop: CGFloat
        if isLandscape {
            // The column fills the rail's height: 6 pt inner padding across, 2 pt outside.
            let width = record + 12
            bar = CGRect(x: frame.midX - width / 2, y: frame.minY + statusHeight + statusGap, width: width,
                         height: frame.height - statusHeight - statusGap)
            statusTop = frame.minY
        } else {
            let height = record + 12
            let top = frame.minY + (frame.height - height - statusHeight - statusGap) / 2
            bar = CGRect(x: 10, y: top + statusHeight + statusGap, width: frame.width - 20, height: height)
            statusTop = top
        }
        if config.recording {
            let text = NSAttributedString(string: String(format: "%02d:%02d", seconds / 60, seconds % 60), attributes: [
                .font: NSFont(descriptor: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold).fontDescriptor.withDesign(.rounded)!, size: 13)!,
                .foregroundColor: NSColor.white,
            ])
            let ts = text.size()
            let w = 10 + 7 + 6 + ts.width + 10
            let pill = CGRect(x: frame.midX - w / 2, y: statusTop, width: w, height: statusHeight)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: statusHeight / 2, cornerHeight: statusHeight / 2, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(NSColor.red.cgColor)
            ctx.fillEllipse(in: CGRect(x: pill.minX + 10, y: pill.midY - 3.5, width: 7, height: 7))
            text.draw(at: CGPoint(x: pill.minX + 23, y: pill.midY - ts.height / 2))
        }
        let radius = min(34, min(bar.width, bar.height) / 2)
        let shape = NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).cgPath
        if let scene {
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            let crop = scene.cropping(to: CGRect(x: bar.minX * scale, y: bar.minY * scale, width: bar.width * scale, height: bar.height * scale))!
            draw(filled(CIImage(cgImage: crop), size: bar.size, scale: scale, blur: 8), in: bar, ctx)
            ctx.setFillColor(NSColor(white: 1, alpha: 0.08).cgColor)
            ctx.fill(bar)
            ctx.restoreGState()
        }
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
        ctx.setLineWidth(0.75)
        ctx.addPath(shape)
        ctx.strokePath()

        // Eight items with equal flexible spacers between them, 10 pt in from the ends.
        let length = isLandscape ? bar.height : bar.width
        let spacer = (length - 20 - 7 * size - record) / 7
        var p = (isLandscape ? bar.minY : bar.minX) + 10
        func at(_ extent: CGFloat) -> CGPoint {
            isLandscape ? CGPoint(x: bar.midX, y: p + extent / 2) : CGPoint(x: p + extent / 2, y: bar.midY)
        }
        func icon(_ name: String, active: Bool = false) {
            let center = at(size)
            if active {
                ctx.setFillColor(sightline.withAlphaComponent(0.2).cgColor)
                ctx.fillEllipse(in: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
            }
            drawCentered(symbol(name, size: 19, weight: .semibold, color: active ? sightline : .white), at: center)
            p += size + spacer
        }
        icon("xmark")
        icon("play.fill")
        icon("mic.fill", active: config.tracking)
        icon("pencil")
        let rc = at(record)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3.5)
        ctx.strokeEllipse(in: CGRect(x: rc.x - record / 2 + 1.75, y: rc.y - record / 2 + 1.75, width: record - 3.5, height: record - 3.5))
        ctx.setFillColor(NSColor.red.cgColor)
        if config.recording {
            let s = record * 0.4
            ctx.addPath(CGPath(roundedRect: CGRect(x: rc.x - s / 2, y: rc.y - s / 2, width: s, height: s), cornerWidth: 6, cornerHeight: 6, transform: nil))
            ctx.fillPath()
        } else {
            ctx.fillEllipse(in: CGRect(x: rc.x - (record - 11) / 2, y: rc.y - (record - 11) / 2, width: record - 11, height: record - 11))
        }
        p += record + spacer
        icon("speaker.wave.2")
        let zoom = NSAttributedString(string: "1×", attributes: [
            .font: NSFont(descriptor: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold).fontDescriptor.withDesign(.rounded)!, size: 14)!,
            .foregroundColor: NSColor.white,
        ])
        let zs = zoom.size(), zc = at(size)
        zoom.draw(at: CGPoint(x: zc.x - zs.width / 2, y: zc.y - zs.height / 2))
        p += size + spacer
        icon("ellipsis")
    }

    // VerticalCropGuide, landscape only: the centred 9:16 strip of the picture, sides dimmed, edges and thirds marked.
    func drawCropGuide(_ ctx: CGContext) {
        guard config.camera, isLandscape, let preview = layout.previewFrame else { return }
        let strip = CameraLayout.verticalCropStrip(in: preview, videoAspect: layout.previewAspect)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(CGRect(x: preview.minX, y: preview.minY, width: strip.minX - preview.minX, height: preview.height))
        ctx.fill(CGRect(x: strip.maxX, y: preview.minY, width: preview.maxX - strip.maxX, height: preview.height))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.fill(CGRect(x: strip.minX, y: preview.minY, width: 1, height: preview.height))
        ctx.fill(CGRect(x: strip.maxX - 1, y: preview.minY, width: 1, height: preview.height))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        for i in 1..<3 {
            ctx.fill(CGRect(x: strip.minX + strip.width * CGFloat(i) / 3, y: preview.minY, width: 0.5, height: preview.height))
            ctx.fill(CGRect(x: strip.minX, y: preview.minY + preview.height * CGFloat(i) / 3, width: strip.width, height: 0.5))
        }
    }

    @MainActor func frame(speech t: Double, clip: Double) -> CGImage {
        let ctx = makeContext()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        if let scene { draw(scene, in: CGRect(origin: .zero, size: size), ctx) } else {
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        drawCropGuide(ctx)
        drawLevel(ctx)
        if config.text { drawPrompter(ctx) }
        drawControls(ctx, seconds: config.recordStart + Int(clip))
        NSGraphicsContext.current = nil
        return ctx.makeImage()!
    }

    func write(_ image: CGImage, _ path: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    try? FileManager.default.createDirectory(atPath: config.out, withIntermediateDirectories: true)
    // The display link runs at 120 Hz on ProMotion iPhones; scroll state advances in those steps.
    let tickRate = 120.0
    @MainActor func advance(to t: Double, from previous: inout Double) {
        while previous < t {
            let next = cursorAt(previous)
            if next != cursor {
                cursor = next
                recolor()
                scroll.followTarget = targetOffset(cursor)
            }
            scroll.tick(dt: CGFloat(1 / tickRate))
            previous += 1 / tickRate
        }
    }

    var clock = -config.lead
    if config.duration <= 0 {
        if config.cursor >= 0 {
            cursor = min(config.cursor, wordRects.count - 1)
            recolor()
            scroll.offset = min(max(targetOffset(cursor), 0), scroll.maxOffset)
        } else {
            advance(to: config.stillAt, from: &clock)
        }
        write(frame(speech: config.stillAt, clip: config.stillAt), config.out + "/still.png")
    } else {
        let count = Int(config.duration * config.fps)
        for i in 0..<count {
            let clip = Double(i) / config.fps
            advance(to: clip - config.lead, from: &clock)
            write(frame(speech: clip - config.lead, clip: clip), String(format: "%@/f%04d.png", config.out, i))
        }
    }
    print("words \(wordRects.count), font \(fontSize), lineHeight \(lineHeight), textFrame \(textFrame), readingLine \(readingLineY), preview \(layout.previewFrame.map { "\($0)" } ?? "none")")
}
