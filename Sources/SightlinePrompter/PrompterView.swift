import AppKit
import Aligner
import Combine
import QuartzCore

/// Draws the teleprompter text word by word. Reading state is shown with per-word colors
/// on a shared NSTextStorage; scroll position lives in ScrollEngine and is applied at draw time.
@MainActor
final class PrompterView: NSView {
    private struct Word {
        let range: NSRange
        let paragraph: Int
        var rect: CGRect = .zero
    }

    private static let insetX: CGFloat = 24
    private static let insetTop: CGFloat = 12
    private static let readingLineRatio: CGFloat = 0.35

    private static let dimColor = NSColor(white: 1, alpha: 0.35)
    private static let normalColor = NSColor(white: 1, alpha: 0.95)
    private static let currentColor = NSColor(srgbRed: 1, green: 0.86, blue: 0.4, alpha: 1)
    private static let highlightFill = NSColor(srgbRed: 1, green: 0.86, blue: 0.4, alpha: 0.16)

    private let settings: Settings
    private var language: ScriptLanguage
    private let scroll = ScrollEngine()
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    private var cancellables = Set<AnyCancellable>()
    private var frameLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0

    private var script = ""
    private var fontSize: CGFloat
    private var words: [Word] = []
    private var paragraphStarts: [Int] = []
    private var cursorIndex = 0
    private var settleTask: Task<Void, Never>?

    var currentWordIndex: Int { cursorIndex }
    var isPlaying: Bool { scroll.isPlaying }

    private var readingLineY: CGFloat { bounds.height * Self.readingLineRatio }

    init(settings: Settings) {
        self.settings = settings
        self.fontSize = CGFloat(settings.fontSize)
        self.language = .named(settings.scriptLanguage)
        super.init(frame: .zero)

        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor

        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        scroll.onChange = { [weak self] in self?.needsDisplay = true }
        scroll.autoSpeed = CGFloat(settings.autoSpeed)

        setScript(settings.script)

        settings.$script
            .dropFirst()
            .sink { [weak self] text in self?.setScript(text) }
            .store(in: &cancellables)
        settings.$fontSize
            .dropFirst()
            .sink { [weak self] size in self?.setFontSize(CGFloat(size)) }
            .store(in: &cancellables)
        settings.$autoSpeed
            .sink { [weak self] speed in self?.scroll.autoSpeed = CGFloat(speed) }
            .store(in: &cancellables)
        scroll.stickMaxSpeed = CGFloat(settings.stickMaxSpeed)
        settings.$stickMaxSpeed
            .sink { [weak self] speed in self?.scroll.stickMaxSpeed = CGFloat(speed) }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if abs(newSize.width - oldSize.width) > 0.5 || abs(newSize.height - oldSize.height) > 0.5 {
            relayout()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !words.isEmpty else {
            drawPlaceholder()
            return
        }

        let origin = CGPoint(x: Self.insetX, y: Self.insetTop - scroll.offset)
        let contentWidth = textContainer.size.width
        let visible = CGRect(x: 0, y: scroll.offset - Self.insetTop - 40,
                             width: contentWidth, height: bounds.height + 80)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)

        NSColor(white: 1, alpha: 0.18).setFill()
        NSRect(x: Self.insetX - 12, y: readingLineY, width: contentWidth + 24, height: 1).fill()

        let highlight = words[cursorIndex].rect
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: -6, dy: -3)
        Self.highlightFill.setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 6, yRadius: 6).fill()

        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }

    override func scrollWheel(with event: NSEvent) {
        let precise: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let fine: CGFloat = event.modifierFlags.contains(.option) ? 0.25 : 1
        scroll.scroll(by: -event.scrollingDeltaY * precise * fine)
        scheduleSettle()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        togglePlay()
    }

    // MARK: - Public API

    /// Called once manual scrolling pauses, with the word now on the reading line.
    var onManualScrollEnded: ((Int) -> Void)?

    func setScript(_ text: String) {
        script = text
        cursorIndex = 0
        scroll.restart()
        buildText()
        updateDisplayLink()
    }

    /// Re-segments the script for another language. Word indices follow the new segmentation.
    func setLanguage(_ language: ScriptLanguage) {
        guard language != self.language else { return }
        self.language = language
        buildText()
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
        recolor(0, words.count - 1)
        updateDisplayLink()
        needsDisplay = true
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

    // MARK: - Text building

    private func setFontSize(_ size: CGFloat) {
        fontSize = size
        buildText()
    }

    private func buildText() {
        let tokens = ScriptTokenizer.tokenize(script, language: language)
        cursorIndex = min(cursorIndex, max(tokens.count - 1, 0))

        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.35
        style.paragraphSpacing = fontSize * 0.8
        style.lineBreakMode = .byWordWrapping
        style.baseWritingDirection = language.rightToLeft ? .rightToLeft : .natural
        style.alignment = language.rightToLeft ? .right : .left

        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: Self.normalColor,
        ]
        let wordSpacer = language.spaced ? " " : ""

        let text = NSMutableAttributedString()
        var built: [Word] = []
        var starts: [Int] = []

        for (index, token) in tokens.enumerated() {
            if index == 0 || token.paragraph != tokens[index - 1].paragraph {
                if index > 0 {
                    text.append(NSAttributedString(string: "\n", attributes: separatorAttributes))
                }
                starts.append(index)
            } else if !wordSpacer.isEmpty {
                text.append(NSAttributedString(string: wordSpacer, attributes: separatorAttributes))
            }
            let range = NSRange(location: text.length, length: token.display.utf16.count)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: style,
                .foregroundColor: Self.color(for: index, cursor: cursorIndex),
            ]
            text.append(NSAttributedString(string: token.display, attributes: attributes))
            built.append(Word(range: range, paragraph: token.paragraph))
        }

        textStorage.setAttributedString(text)
        words = built
        paragraphStarts = starts
        relayout()
    }

    private static func color(for index: Int, cursor: Int) -> NSColor {
        if index < cursor { return dimColor }
        return index == cursor ? currentColor : normalColor
    }

    private func relayout() {
        textContainer.size = CGSize(width: max(bounds.width - 2 * Self.insetX, 40),
                                    height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        for index in words.indices {
            let glyphs = layoutManager.glyphRange(forCharacterRange: words[index].range,
                                                  actualCharacterRange: nil)
            words[index].rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        }

        // Scrolling stops once the last word reaches the reading line.
        if let last = words.last {
            scroll.maxOffset = max(0, Self.insetTop + last.rect.midY - readingLineY)
        } else {
            scroll.maxOffset = 0
        }
        needsDisplay = true
    }

    // MARK: - Cursor and highlight

    private func moveCursor(to index: Int) {
        guard !words.isEmpty else { return }
        let target = min(max(index, 0), words.count - 1)
        guard target != cursorIndex else { return }

        let previous = cursorIndex
        cursorIndex = target
        recolor(previous, target)
        scroll.followTarget = Self.insetTop + words[target].rect.midY - readingLineY
        updateDisplayLink()
        needsDisplay = true
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
        textStorage.endEditing()
    }

    /// Waits for the wheel to stop, then makes the word on the reading line the new position.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self, !self.words.isEmpty else { return }
            let index = self.wordIndexAtReadingLine()
            self.moveCursor(to: index)
            self.onManualScrollEnded?(index)
        }
    }

    /// Words whose lines intersect the visible area, in script indices. nil when nothing is shown.
    func visibleWordRange() -> ClosedRange<Int>? {
        let top = scroll.offset - Self.insetTop
        let bottom = top + bounds.height
        let visible = words.indices.filter { words[$0].rect.maxY >= top && words[$0].rect.minY <= bottom }
        guard let first = visible.first, let last = visible.last else { return nil }
        return first...last
    }

    /// Index of the word whose vertical center is closest to the reading line.
    private func wordIndexAtReadingLine() -> Int {
        let target = readingLineY + scroll.offset - Self.insetTop
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

    private func drawPlaceholder() {
        let text = NSAttributedString(
            string: "Paste your script in Settings",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor(white: 1, alpha: 0.4),
            ]
        )
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2))
    }

    // MARK: - Animation

    /// Runs the display link only while the window is attached and scroll has work to do.
    private func updateDisplayLink() {
        guard window != nil else {
            frameLink?.invalidate()
            frameLink = nil
            return
        }
        if frameLink == nil {
            let link = displayLink(target: self, selector: #selector(frameTick(_:)))
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
