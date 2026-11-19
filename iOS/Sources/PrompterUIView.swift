import Aligner
import Combine
import QuartzCore
import SightlineCore
import UIKit

/// Draws the teleprompter text word by word. The iPhone counterpart of the macOS PrompterView: reading
/// state is per-word colors on a shared NSTextStorage, scroll position lives in ScrollEngine and is
/// applied at draw time. Where the text sits and where the reading line is come from CameraLayout.
@MainActor
final class PrompterUIView: UIView {
    private struct Word {
        let range: NSRange
        let paragraph: Int
        var rect: CGRect = .zero
    }

    // Colour order (spec 8.1): the text the eyes work on is brightest, what is read is clearly done.
    private static let dimColor = UIColor(white: 1, alpha: CGFloat(PrompterTypography.colorReadAlpha))
    private static let normalColor = UIColor(white: 1, alpha: 1)
    private static let currentColor = UIColor(red: 1, green: 0.86, blue: 0.4, alpha: 1)
    private static let highlightFill = UIColor(red: 1, green: 0.86, blue: 0.4, alpha: 0.16)
    private static let readingLineColor = UIColor(white: 1, alpha: 0.18)

    private let settings: PhoneSettings
    private var language: ScriptLanguage = .named("en-US")
    private let scroll = ScrollEngine()
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
    private var cancellables = Set<AnyCancellable>()
    private var frameLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var settleTask: Task<Void, Never>?

    private var script = ""
    private var fontSize: CGFloat
    private var words: [Word] = []
    private var cues: [PrompterText.CueRun] = []
    private var cueRects: [CGRect] = []
    private var paragraphStarts: [Int] = []
    private var cursorIndex = 0
    private var textFrame: CGRect = .zero
    private var readingLineY: CGFloat = 0
    private var cameraMode = false
    private var previewFrame: CGRect?
    /// Backing-plate opacity per text line (keyed by the line's first glyph), eased towards what the picture behind needs.
    private var lineAlpha: [Int: CGFloat] = [:]
    private var lastBackdrop: CFTimeInterval = 0
    private var cursorMoved: CFTimeInterval = 0
    private var dragging = false
    /// Plate opacity for a line nobody has measured yet (no camera picture, store screenshots).
    private static let defaultPlateAlpha: CGFloat = 0.35

    var currentWordIndex: Int { cursorIndex }
    /// Width the text column has, in points.
    var textWidth: CGFloat { textFrame.width }
    /// Where the camera picture is on screen, for mapping text lines onto it. nil without a camera.
    var cameraPreviewFrame: CGRect? { previewFrame }
    /// Seconds since the reading position last moved on.
    var secondsSinceCursorMove: Double { CACurrentMediaTime() - cursorMoved }
    var isDragging: Bool { dragging }
    var isPlaying: Bool { scroll.isPlaying }

    /// Called once manual scrolling settles, with the word now on the reading line.
    var onManualScrollEnded: ((Int) -> Void)?
    /// Called on a tap on the text. The owner decides what a tap does.
    var onTap: (() -> Void)?
    /// Called when the text is pressed and held, to start moving and resizing it.
    var onLongPress: (() -> Void)?

    /// Screen y where the text starts at zero scroll offset.
    private var contentTop: CGFloat { textFrame.minY }

    init(settings: PhoneSettings) {
        self.settings = settings
        self.fontSize = CGFloat(settings.fontSize)
        super.init(frame: .zero)

        backgroundColor = .black
        isOpaque = true

        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        cursorMoved = CACurrentMediaTime()
        scroll.onChange = { [weak self] in self?.invalidateText() }
        scroll.autoSpeed = CGFloat(settings.autoSpeed)
        scroll.stickMaxSpeed = CGFloat(settings.stickMaxSpeed)

        installGestures()
        observeSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Area, in window coordinates, where the SwiftUI controls sit. Touches there pass through to them.
    var passThroughRect: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if passThroughRect.contains(convert(point, to: nil)) {
            return nil
        }
        // In camera mode only the text band is ours; the rest belongs to the preview beneath.
        if cameraMode, !textFrame.insetBy(dx: -12, dy: 0).contains(point) {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLink()
    }

    /// Camera mode: the view is transparent over the live preview, and the text column gets a dark backing
    /// so it stays readable on any scene.
    func setCameraMode(_ on: Bool) {
        backgroundColor = on ? .clear : .black
        isOpaque = !on
        // Normal compositing: legibility over the video comes from the veil and halo drawn in draw(_:).
        cameraMode = on
        setNeedsDisplay()
    }

    /// Redraws only the text band in camera mode, so a scroll frame does not repaint the whole screen.
    private func invalidateText() {
        if cameraMode, !textFrame.isEmpty {
            setNeedsDisplay(textFrame.insetBy(dx: -16, dy: -1.3 * fontSize))
        } else {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard !words.isEmpty, let context = UIGraphicsGetCurrentContext() else {
            drawPlaceholder()
            return
        }

        let origin = CGPoint(x: textFrame.minX, y: contentTop - scroll.offset)
        let visible = CGRect(x: 0, y: scroll.offset - contentTop - 40,
                             width: textFrame.width, height: textFrame.height + 80)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)

        // Plates are not clipped to the text band: their feathered edge fades out past it instead of ending in a line.
        if cameraMode {
            drawPlates(in: context, lines: lineRects(glyphs: glyphs, origin: origin))
        }

        // Text is clipped to the band between the camera area and the controls, but never hard-cut mid-glyph:
        // a 0.6 em alpha feather at both edges, and the bottom edge sits 0.3 em lower so descenders survive.
        let clipRect = CGRect(x: 0, y: textFrame.minY, width: bounds.width, height: textFrame.height + 0.3 * fontSize)
        context.saveGState()
        context.clip(to: clipRect)
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        // The reading line only ticks in the margins, so it never crosses the text.
        Self.readingLineColor.setFill()
        for x in [textFrame.minX - 12, textFrame.maxX + 2] {
            UIRectFill(CGRect(x: x, y: readingLineY, width: 10, height: 1))
        }

        let wordRect = words[cursorIndex].rect
        let glyph = layoutManager.glyphIndexForCharacter(at: words[cursorIndex].range.location)
        let metrics = glyphMetrics(glyph: glyph)
        let band = PrompterTypography.highlightBand(baseline: Double(metrics.baseline), capHeight: Double(metrics.cap), fontSize: Double(fontSize))
        let pad = 0.12 * fontSize
        let highlight = CGRect(x: wordRect.minX - pad, y: CGFloat(band.top), width: wordRect.width + 2 * pad,
                               height: CGFloat(band.bottom - band.top))
            .offsetBy(dx: origin.x, dy: origin.y)
        Self.highlightFill.setFill()
        UIBezierPath(roundedRect: highlight, cornerRadius: 0.2 * fontSize).fill()

        layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
        if cameraMode {
            // Over the camera picture the text is backed by the plates drawn above, and every glyph gets a
            // two-layer halo in em, so it scales with the text size (spec 8.3).
            context.setShadow(offset: .zero, blur: 0.28 * fontSize, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
            context.setShadow(offset: CGSize(width: 0, height: 0.03 * fontSize), blur: 0.07 * fontSize,
                              color: UIColor.black.withAlphaComponent(0.9).cgColor)
        }
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)

        // Feather mask: keeps the layer's alpha only where the gradient is opaque, so the video behind stays visible.
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setBlendMode(.destinationIn)
        let feather = min(0.6 * fontSize / clipRect.height, 0.5)
        let clear = UIColor.clear.cgColor, opaque = UIColor.black.cgColor
        if let mask = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [clear, opaque, opaque, clear] as CFArray,
                                 locations: [0, feather, 1 - feather, 1]) {
            context.drawLinearGradient(mask, start: CGPoint(x: 0, y: clipRect.minY), end: CGPoint(x: 0, y: clipRect.maxY), options: [])
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: - Backing plates

    /// Baseline (container coordinates) and cap height of the line that holds `glyph`.
    private func glyphMetrics(glyph: Int) -> (baseline: CGFloat, cap: CGFloat) {
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let char = layoutManager.characterIndexForGlyph(at: glyph)
        let font = textStorage.attribute(.font, at: char, effectiveRange: nil) as? UIFont ?? .systemFont(ofSize: fontSize)
        return (fragment.minY + layoutManager.location(forGlyphAt: glyph).y, font.capHeight)
    }

    /// The glyph boxes of the lines in `glyphs` (cap top to under the baseline, not the taller line box), in view
    /// coordinates, inflated to the plate size (0.6 em across, 0.22 em up and down).
    private func lineRects(glyphs: NSRange, origin: CGPoint) -> [(key: Int, rect: CGRect)] {
        var lines: [(key: Int, rect: CGRect)] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, range, _ in
            let metrics = self.glyphMetrics(glyph: range.location)
            let band = PrompterTypography.highlightBand(baseline: Double(metrics.baseline), capHeight: Double(metrics.cap), fontSize: Double(self.fontSize))
            let box = CGRect(x: used.minX, y: CGFloat(band.top), width: used.width, height: CGFloat(band.bottom - band.top))
            lines.append((range.location, box.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -0.6 * self.fontSize, dy: -0.22 * self.fontSize)))
        }
        return lines
    }

    /// A soft black plate behind each line, only as dark as the picture behind that line needs. The lines'
    /// boxes are united into one shape (so overlaps never double the opacity) and drawn as a Gaussian shadow
    /// (sigma 0.3 em), so no rectangle edge shows; then the opacity is set per line by a vertical ramp
    /// between the lines' own values.
    private func drawPlates(in context: CGContext, lines: [(key: Int, rect: CGRect)]) {
        guard let first = lines.first, let last = lines.last else { return }
        let sigma = 0.3 * fontSize, radius = 0.5 * fontSize
        let top = first.rect.minY - 2 * sigma, bottom = max(last.rect.maxY + 2 * sigma, top + 1)

        context.beginTransparencyLayer(auxiliaryInfo: nil)
        // Fill the shape far off to the side with its shadow brought back: only the blurred shadow lands.
        let shift: CGFloat = 1000
        context.saveGState()
        context.setShadow(offset: CGSize(width: -shift, height: 0), blur: 2 * sigma,
                          color: UIColor.black.cgColor)
        let shape = UIBezierPath()
        for line in lines {
            shape.append(UIBezierPath(roundedRect: line.rect.offsetBy(dx: shift, dy: 0), cornerRadius: radius))
        }
        UIColor.black.setFill()
        shape.fill()
        context.restoreGState()
        context.setBlendMode(.destinationIn)
        var colors = lines.map { UIColor.black.withAlphaComponent(lineAlpha[$0.key] ?? Self.defaultPlateAlpha).cgColor }
        var places = lines.map { min(max(($0.rect.midY - top) / (bottom - top), 0), 1) }
        colors = [colors[0]] + colors + [colors[colors.count - 1]]
        places = [0] + places + [1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: places) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.endTransparencyLayer()
        context.setBlendMode(.normal)
    }

    /// The places on the screen to read the camera picture's brightness at: one per visible line.
    func backdropLines() -> [(key: Int, rect: CGRect)] {
        guard cameraMode, !words.isEmpty, !textFrame.isEmpty else { return [] }
        let origin = CGPoint(x: textFrame.minX, y: contentTop - scroll.offset)
        let visible = CGRect(x: 0, y: scroll.offset - contentTop, width: textFrame.width, height: textFrame.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        return lineRects(glyphs: glyphs, origin: origin).filter { $0.rect.intersects(textFrame) }
    }

    /// The picture's brightness (encoded luma) behind each requested line. Eased over about half a second so a
    /// cut or an exposure change does not make the plates flicker.
    func receiveBackdrop(_ luma: [Int: Double]) {
        let now = CACurrentMediaTime()
        let ease = 1 - exp(-min(now - lastBackdrop, 1) / 0.5)
        lastBackdrop = now
        var next: [Int: CGFloat] = [:]
        for (key, value) in luma {
            let wanted = CGFloat(PrompterTypography.scrimAlpha(backgroundLuma: value))
            next[key] = lineAlpha[key].map { $0 + ease * (wanted - $0) } ?? wanted
        }
        lineAlpha = next
        invalidateText()
    }

    private func drawPlaceholder() {
        let text = NSAttributedString(
            string: "Add a script in Library",
            attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.4),
            ]
        )
        let size = text.size()
        text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    // MARK: - Gestures

    private func installGestures() {
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.5
        addGestureRecognizer(hold)
    }

    @objc private func handleHold(_ hold: UILongPressGestureRecognizer) {
        guard hold.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress?()
    }

    @objc private func handleTap() {
        onTap?()
    }

    /// Dragging moves the text by the finger; a release flings it. Manual scrolling moves the reading position.
    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            dragging = true
            scroll.halt()
            settleTask?.cancel()
            pan.setTranslation(.zero, in: self)
        case .changed:
            let dy = pan.translation(in: self).y
            pan.setTranslation(.zero, in: self)
            scroll.scroll(by: -dy)
        case .ended, .cancelled:
            dragging = false
            scroll.fling(velocity: -pan.velocity(in: self).y)
            scheduleSettle()
        default:
            break
        }
    }

    /// Waits for the drag and any fling to finish, then makes the word on the reading line the new position.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            while let scroll = self?.scroll, scroll.isCoasting {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled, let self, !self.words.isEmpty else { return }
            let index = self.wordIndexAtReadingLine()
            self.moveCursor(to: index)
            self.onManualScrollEnded?(index)
        }
    }

    // MARK: - Public API

    /// Loads a script: resets the position and segments the text for the language.
    func load(script text: String, language: ScriptLanguage) {
        self.language = language
        script = text
        cursorIndex = 0
        scroll.restart()
        buildText()
        updateDisplayLink()
    }

    /// Applies the camera layout. Re-flows the text and keeps the current word on the reading line.
    func apply(_ layout: CameraLayout) {
        previewFrame = layout.previewFrame
        guard layout.textFrame != textFrame || layout.readingLineY != readingLineY else { return }
        textFrame = layout.textFrame
        readingLineY = layout.readingLineY
        relayout()
        if !words.isEmpty {
            scroll.followTarget = targetOffset(for: cursorIndex)
            updateDisplayLink()
        }
    }

    func setCursor(wordIndex: Int) {
        moveCursor(to: wordIndex)
    }

    func jumpParagraph(forward: Bool) {
        guard !words.isEmpty else { return }
        let paragraph = words[cursorIndex].paragraph
        if forward {
            guard paragraph + 1 < paragraphStarts.count else { return }
            moveCursor(to: paragraphStarts[paragraph + 1])
        } else if cursorIndex > paragraphStarts[paragraph] {
            moveCursor(to: paragraphStarts[paragraph])
        } else {
            moveCursor(to: paragraphStarts[max(paragraph - 1, 0)])
        }
    }

    func restart() {
        scroll.restart()
        cursorIndex = 0
        if !words.isEmpty {
            recolor(0, words.count - 1)
        }
        updateDisplayLink()
        setNeedsDisplay()
    }

    func togglePlay() {
        scroll.isPlaying.toggle()
        updateDisplayLink()
    }

    func adjustSpeed(by delta: CGFloat) {
        let speed = min(max(scroll.autoSpeed + delta, 0), 300)
        scroll.autoSpeed = speed
        settings.autoSpeed = Double(speed)
    }

    func setStick(_ value: CGFloat) {
        scroll.stick = min(max(value, -1), 1)
        updateDisplayLink()
    }

    /// Words whose lines intersect the visible text band, in script indices. nil when nothing is shown.
    func visibleWordRange() -> ClosedRange<Int>? {
        // Camera mode shows only a few lines, so matching reaches a little past them in both directions:
        // speech runs ahead of the scroll and recognition results arrive late.
        let pad: CGFloat = cameraMode ? fontSize * 3.2 : 0
        let top = scroll.offset - contentTop - pad
        let bottom = scroll.offset - contentTop + textFrame.height + pad
        let visible = words.indices.filter { words[$0].rect.maxY >= top && words[$0].rect.minY <= bottom }
        guard let first = visible.first, let last = visible.last else { return nil }
        return first...last
    }

    // MARK: - Settings

    private func observeSettings() {
        Publishers.CombineLatest3(settings.$lineSpacing, settings.$letterSpacing, settings.$wordSpacing)
            .dropFirst()
            .sink { [weak self] _, _, _ in self?.buildText() }
            .store(in: &cancellables)
        settings.$autoSpeed
            .sink { [weak self] speed in self?.scroll.autoSpeed = CGFloat(speed) }
            .store(in: &cancellables)
        settings.$stickMaxSpeed
            .sink { [weak self] speed in self?.scroll.stickMaxSpeed = CGFloat(speed) }
            .store(in: &cancellables)
    }

    /// A new text size, from the Font size setting or from Auto. The word on the reading line stays on it; an
    /// automatic change is eased in with a short cross-fade.
    func setTextSize(_ size: CGFloat, animated: Bool) {
        guard abs(size - fontSize) > 0.01 else { return }
        let change = {
            let anchor = self.words.isEmpty ? nil : self.wordIndexAtReadingLine()
            self.fontSize = size
            self.buildText()
            if let anchor {
                self.scroll.offset = min(max(self.targetOffset(for: anchor), 0), self.scroll.maxOffset)
                if self.scroll.followTarget != nil { self.scroll.followTarget = self.targetOffset(for: self.cursorIndex) }
            }
        }
        if animated, window != nil {
            UIView.transition(with: self, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction], animations: change)
        } else {
            change()
        }
    }

    // MARK: - Text building

    private func buildText() {
        let built = PrompterText.build(
            script: script,
            language: language,
            fontSize: fontSize,
            lineSpacing: CGFloat(settings.lineSpacing),
            letterSpacing: CGFloat(settings.letterSpacing),
            wordSpacing: CGFloat(settings.wordSpacing),
            cursor: cursorIndex,
            wordColor: { [cursorIndex] in Self.color(for: $0, cursor: cursorIndex) }
        )
        textStorage.setAttributedString(built.attributed)
        words = built.words.map { Word(range: $0.range, paragraph: $0.paragraph) }
        cues = built.cues
        paragraphStarts = built.paragraphStarts

        let clamped = min(cursorIndex, max(words.count - 1, 0))
        if clamped != cursorIndex {
            cursorIndex = clamped
            recolor(0, words.count - 1)
        }
        relayout()
    }

    private static func color(for index: Int, cursor: Int) -> UIColor {
        if index < cursor { return dimColor }
        return index == cursor ? currentColor : normalColor
    }

    private func relayout() {
        textContainer.size = CGSize(width: max(textFrame.width, 40), height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        for index in words.indices {
            let glyphs = layoutManager.glyphRange(forCharacterRange: words[index].range, actualCharacterRange: nil)
            words[index].rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        }

        cueRects = cues.map { cue in
            let glyphs = layoutManager.glyphRange(forCharacterRange: cue.range, actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        }

        // Scrolling stops once the last word, or a cue after it, reaches the reading line.
        if let last = words.last {
            let end = max(last.rect.midY, cueRects.last?.midY ?? 0)
            scroll.maxOffset = max(0, contentTop + end - readingLineY)
        } else {
            scroll.maxOffset = 0
        }
        setNeedsDisplay()
    }

    // MARK: - Cursor and highlight

    /// Scroll offset that puts the given word on the reading line.
    private func targetOffset(for index: Int) -> CGFloat {
        contentTop + words[index].rect.midY - readingLineY
    }

    private func moveCursor(to index: Int) {
        guard !words.isEmpty else { return }
        let target = min(max(index, 0), words.count - 1)
        guard target != cursorIndex else { return }

        let previous = cursorIndex
        cursorIndex = target
        cursorMoved = CACurrentMediaTime()
        recolor(previous, target)
        scroll.followTarget = targetOffset(for: target)
        updateDisplayLink()
        setNeedsDisplay()
    }

    /// Re-applies word colors for the inclusive index span, without relayout.
    private func recolor(_ a: Int, _ b: Int) {
        guard !words.isEmpty else { return }
        let lo = max(0, min(a, b))
        let hi = min(words.count - 1, max(a, b))
        textStorage.beginEditing()
        for index in lo...hi {
            textStorage.addAttribute(.foregroundColor,
                                     value: Self.color(for: index, cursor: cursorIndex),
                                     range: words[index].range)
        }
        for cue in cues {
            textStorage.addAttribute(.foregroundColor,
                                     value: PrompterText.cueColor(wordsBefore: cue.wordsBefore, cursor: cursorIndex),
                                     range: cue.range)
            textStorage.addAttribute(.backgroundColor,
                                     value: PrompterText.cueBackground(wordsBefore: cue.wordsBefore, cursor: cursorIndex),
                                     range: cue.range)
        }
        textStorage.endEditing()
    }

    /// Index of the word whose vertical center is closest to the reading line.
    private func wordIndexAtReadingLine() -> Int {
        let target = readingLineY + scroll.offset - contentTop
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in words.indices {
            let distance = abs(words[index].rect.midY - target)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    // MARK: - Animation

    /// Runs the display link only while the view is on screen and scroll has work to do.
    private func updateDisplayLink() {
        guard window != nil else {
            frameLink?.invalidate()
            frameLink = nil
            return
        }
        if frameLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
            link.add(to: .main, forMode: .common)
            frameLink = link
        }
        frameLink?.isPaused = !scroll.isAnimating
        if !scroll.isAnimating {
            lastFrameTime = 0
        }
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrameTime == 0 ? 1.0 / 60.0 : now - lastFrameTime
        lastFrameTime = now
        scroll.tick(dt: CGFloat(dt))
        if !scroll.isAnimating {
            updateDisplayLink()
        }
    }
}
