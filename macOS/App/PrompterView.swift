import AppKit
import Aligner
import Combine
import QuartzCore
import SightlineCore

/// The script editor that replaces the prompter text while editing; Esc ends it, like the Done button.
private final class ScriptEditorTextView: NSTextView {
    var onDone: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onDone?()
    }
}

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

    // Colour order (spec 8.1): the text the eyes work on is brightest, what is read is clearly done.
    private static let dimColor = NSColor(white: 1, alpha: CGFloat(PrompterTypography.colorReadAlpha))
    private static let normalColor = NSColor(white: 1, alpha: 1)
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
    private var cues: [PrompterText.CueRun] = []
    private var cueRects: [CGRect] = []
    private var paragraphStarts: [Int] = []
    private var cursorIndex = 0
    private var settleTask: Task<Void, Never>?
    private var cursorMoved: CFTimeInterval = CACurrentMediaTime()

    var currentWordIndex: Int { cursorIndex }
    var isPlaying: Bool { scroll.isPlaying }

    /// The script is shown in an editable text view in place of the prompter text.
    private var editor: NSScrollView?
    private var editorDone: NSButton?
    private var appBeforeEditing: NSRunningApplication?
    var isEditing: Bool { editor != nil }
    /// Called when editing starts (true) and, after the new text is in place, when it ends (false).
    var onEditingChanged: ((Bool) -> Void)?

    private var readingLineY: CGFloat { bounds.height * Self.readingLineRatio }

    init(settings: Settings) {
        self.settings = settings
        self.fontSize = CGFloat(TextSizer.shared.size)
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
        TextSizer.shared.speechPause = { [weak self] in self.map { CACurrentMediaTime() - $0.cursorMoved } ?? 1 }
        TextSizer.shared.$size
            .dropFirst()
            .sink { [weak self] size in self?.setFontSize(CGFloat(size), animated: TextSizer.shared.lastChangeWasAuto) }
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
            layoutEditor()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
    }

    override func draw(_ dirtyRect: NSRect) {
        // The editor stands in for the text, so nothing of the prompter shows behind it.
        guard editor == nil else { return }
        guard !words.isEmpty else {
            drawPlaceholder()
            return
        }

        let origin = CGPoint(x: Self.insetX, y: Self.insetTop - scroll.offset)
        let contentWidth = textContainer.size.width
        let visible = CGRect(x: 0, y: scroll.offset - Self.insetTop - 40,
                             width: contentWidth, height: bounds.height + 80)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)

        // The reading line only ticks in the margins, so it never crosses the text.
        NSColor(white: 1, alpha: 0.18).setFill()
        for x in [Self.insetX - 12, Self.insetX + contentWidth + 2] {
            NSRect(x: x, y: readingLineY, width: 10, height: 1).fill()
        }

        // Highlight sits on the glyphs (cap top to under the baseline), not on the taller line box.
        let wordRect = words[cursorIndex].rect
        let glyph = layoutManager.glyphIndexForCharacter(at: words[cursorIndex].range.location)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let font = textStorage.attribute(.font, at: words[cursorIndex].range.location, effectiveRange: nil) as? NSFont
            ?? .systemFont(ofSize: fontSize)
        let band = PrompterTypography.highlightBand(
            baseline: Double(fragment.minY + layoutManager.location(forGlyphAt: glyph).y),
            capHeight: Double(font.capHeight), fontSize: Double(font.pointSize))
        let pad = 0.12 * font.pointSize
        let highlight = CGRect(x: wordRect.minX - pad, y: CGFloat(band.top), width: wordRect.width + 2 * pad,
                               height: CGFloat(band.bottom - band.top))
            .offsetBy(dx: origin.x, dy: origin.y)
        Self.highlightFill.setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 0.2 * font.pointSize, yRadius: 0.2 * font.pointSize).fill()

        layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
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
        if event.clickCount >= 2 {
            beginEditing(atWord: wordIndex(at: convert(event.locationInWindow, from: nil)))
            return
        }
        togglePlay()
    }

    /// The word under a point of this view, with a little slack around it; nil on a gap.
    private func wordIndex(at point: CGPoint) -> Int? {
        let local = CGPoint(x: point.x - Self.insetX, y: point.y - Self.insetTop + scroll.offset)
        return words.indices.first { words[$0].rect.insetBy(dx: -0.3 * fontSize, dy: -0.15 * fontSize).contains(local) }
    }

    // MARK: - Editing

    /// Swaps the prompter text for an editable text view of the script, caret on the given word (the current one by
    /// default). Scrolling pauses; the panel becomes the key window until editing ends.
    func beginEditing(atWord word: Int? = nil) {
        guard editor == nil, let window else { return }
        if scroll.isPlaying { togglePlay() }
        let front = NSWorkspace.shared.frontmostApplication
        appBeforeEditing = front == NSRunningApplication.current ? nil : front

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        let textView = ScriptEditorTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.onDone = { [weak self] in self?.endEditing() }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .white
        textView.insertionPointColor = Self.currentColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = script
        scrollView.documentView = textView

        let done = NSButton(title: "Done", target: self, action: #selector(endEditingPressed))
        done.bezelStyle = .rounded
        done.toolTip = "Save and continue (Esc)"
        addSubview(scrollView)
        addSubview(done)
        editor = scrollView
        editorDone = done
        layoutEditor()
        needsDisplay = true

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window.makeFirstResponder(textView)
        let offset = ScriptEditing.startOffset(ofWord: word ?? cursorIndex, in: script, language: language)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        onEditingChanged?(true)
    }

    @objc private func endEditingPressed() {
        endEditing()
    }

    /// Saves the text through Settings.script (which the library follows), puts the reading position back on
    /// the same word and hands the focus back to the app that had it.
    private func endEditing() {
        guard let scrollView = editor, let textView = scrollView.documentView as? NSTextView else { return }
        let text = textView.string
        let old = script
        let word = cursorIndex
        editor = nil
        scrollView.removeFromSuperview()
        editorDone?.removeFromSuperview()
        editorDone = nil
        needsDisplay = true
        window?.makeFirstResponder(self)
        if text != old {
            settings.script = text
            place(word: ScriptEditing.remap(word: word, old: old, new: text, language: language))
        }
        appBeforeEditing?.activate()
        appBeforeEditing = nil
        onEditingChanged?(false)
    }

    private func layoutEditor() {
        guard let editor, let editorDone else { return }
        editorDone.sizeToFit()
        editorDone.setFrameOrigin(NSPoint(x: bounds.maxX - editorDone.frame.width - 12, y: 6))
        editor.frame = NSRect(x: 12, y: 38, width: max(bounds.width - 24, 40), height: max(bounds.height - 46, 40))
    }

    /// Puts the reading position on a word at once (no scroll animation), after the text was replaced.
    private func place(word: Int) {
        guard !words.isEmpty else { return }
        cursorIndex = min(max(word, 0), words.count - 1)
        cursorMoved = CACurrentMediaTime()
        recolor(0, words.count - 1)
        scroll.offset = min(max(Self.insetTop + words[cursorIndex].rect.midY - readingLineY, 0), scroll.maxOffset)
        updateDisplayLink()
        needsDisplay = true
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

    /// A new text size, from the settings or from the camera. The word on the reading line stays on it.
    private func setFontSize(_ size: CGFloat, animated: Bool) {
        guard abs(size - fontSize) > 0.01 else { return }
        let anchor = words.isEmpty ? nil : wordIndexAtReadingLine()
        if animated, let layer {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3
            layer.add(fade, forKey: "textSize")
        }
        fontSize = size
        buildText()
        if let anchor {
            scroll.offset = min(max(Self.insetTop + words[anchor].rect.midY - readingLineY, 0), scroll.maxOffset)
            if scroll.followTarget != nil { scroll.followTarget = Self.insetTop + words[cursorIndex].rect.midY - readingLineY }
        }
    }

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

        cueRects = cues.map { cue in
            let glyphs = layoutManager.glyphRange(forCharacterRange: cue.range, actualCharacterRange: nil)
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        }

        // Scrolling stops once the last word, or a cue after it, reaches the reading line.
        if let last = words.last {
            let end = max(last.rect.midY, cueRects.last?.midY ?? 0)
            scroll.maxOffset = max(0, Self.insetTop + end - readingLineY)
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
        cursorMoved = CACurrentMediaTime()
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
