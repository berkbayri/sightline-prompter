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

    private static let dimColor = UIColor(white: 1, alpha: 0.35)
    private static let normalColor = UIColor(white: 1, alpha: 0.95)
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

    var currentWordIndex: Int { cursorIndex }
    var isPlaying: Bool { scroll.isPlaying }

    /// Called once manual scrolling settles, with the word now on the reading line.
    var onManualScrollEnded: ((Int) -> Void)?
    /// Called on a tap on the text. The owner decides what a tap does.
    var onTap: (() -> Void)?

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
        cameraMode = on
        setNeedsDisplay()
    }

    /// Redraws only the text band in camera mode, so a scroll frame does not repaint the whole screen.
    private func invalidateText() {
        if cameraMode, !textFrame.isEmpty {
            setNeedsDisplay(textFrame.insetBy(dx: -16, dy: -4))
        } else {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        if cameraMode {
            let backing = UIBezierPath(
                roundedRect: CGRect(x: textFrame.minX - 12, y: textFrame.minY, width: textFrame.width + 24, height: textFrame.height),
                cornerRadius: 14
            )
            UIColor(white: 0, alpha: 0.45).setFill()
            backing.fill()
        }

        guard !words.isEmpty, let context = UIGraphicsGetCurrentContext() else {
            drawPlaceholder()
            return
        }

        let origin = CGPoint(x: textFrame.minX, y: contentTop - scroll.offset)
        let visible = CGRect(x: 0, y: scroll.offset - contentTop - 40,
                             width: textFrame.width, height: textFrame.height + 80)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)

        // Text is clipped to the band between the camera area and the controls.
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: textFrame.minY, width: bounds.width, height: textFrame.height))

        Self.readingLineColor.setFill()
        UIRectFill(CGRect(x: textFrame.minX - 12, y: readingLineY, width: textFrame.width + 24, height: 1))

        let highlight = words[cursorIndex].rect
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: -6, dy: -3)
        Self.highlightFill.setFill()
        UIBezierPath(roundedRect: highlight, cornerRadius: 6).fill()

        layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        context.restoreGState()
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
    }

    @objc private func handleTap() {
        onTap?()
    }

    /// Dragging moves the text by the finger; a release flings it. Manual scrolling moves the reading position.
    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            scroll.halt()
            settleTask?.cancel()
            pan.setTranslation(.zero, in: self)
        case .changed:
            let dy = pan.translation(in: self).y
            pan.setTranslation(.zero, in: self)
            scroll.scroll(by: -dy)
        case .ended, .cancelled:
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
        settings.$fontSize
            .dropFirst()
            .sink { [weak self] size in self?.setFontSize(CGFloat(size)) }
            .store(in: &cancellables)
        settings.$autoSpeed
            .sink { [weak self] speed in self?.scroll.autoSpeed = CGFloat(speed) }
            .store(in: &cancellables)
        settings.$stickMaxSpeed
            .sink { [weak self] speed in self?.scroll.stickMaxSpeed = CGFloat(speed) }
            .store(in: &cancellables)
    }

    private func setFontSize(_ size: CGFloat) {
        fontSize = size
        buildText()
    }

    // MARK: - Text building

    private func buildText() {
        let built = PrompterText.build(
            script: script,
            language: language,
            fontSize: fontSize,
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
