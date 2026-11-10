import CoreGraphics

/// Where the user put the camera preview and the prompter text, as fractions of the free screen area, so a
/// saved placement survives other screen sizes and a changed aspect ratio. The preview stores only its
/// origin and width: its height always follows the aspect ratio.
public struct Arrangement: Equatable, Codable, Sendable {
    public var preview: CGRect
    public var text: CGRect

    public init(preview: CGRect, text: CGRect) {
        self.preview = preview
        self.text = text
    }

    public init(frames: ArrangedFrames, in area: CGRect) {
        func normalize(_ rect: CGRect) -> CGRect {
            guard area.width > 0, area.height > 0 else { return .zero }
            return CGRect(
                x: (rect.minX - area.minX) / area.width,
                y: (rect.minY - area.minY) / area.height,
                width: rect.width / area.width,
                height: rect.height / area.height
            )
        }
        self.init(preview: normalize(frames.preview), text: normalize(frames.text))
    }
}

/// The two items in screen coordinates.
public struct ArrangedFrames: Equatable, Sendable {
    public var preview: CGRect
    public var text: CGRect

    public init(preview: CGRect, text: CGRect) {
        self.preview = preview
        self.text = text
    }
}

/// Which item an edit is about.
public enum ArrangedItem: Sendable {
    case preview, text
}

/// Moving and resizing the preview and the text inside the free area. Pure geometry.
///
/// - The preview keeps its aspect ratio whatever is done to it.
/// - The text is free-form.
/// - By default the two never overlap. Resizing one shrinks the other when it has to; a move slides along
///   the other item or stops, because moving never resizes. With `textMayCoverPreview` the text floats
///   over the preview and nothing is avoided or shrunk; each item only stays inside the area.
public struct ArrangementGeometry: Sendable {
    public var area: CGRect
    /// Width / height of the preview.
    public var aspect: CGFloat
    public var minPreviewWidth: CGFloat = 96
    public var minText = CGSize(width: 120, height: 60)
    /// Empty room kept between the items.
    public var gap: CGFloat = 8
    /// The prompter text may sit on top of the preview.
    public var textMayCoverPreview = false

    public init(area: CGRect, aspect: CGFloat, minText: CGSize = CGSize(width: 120, height: 60)) {
        self.area = area
        self.aspect = aspect
        self.minText = minText
    }

    // MARK: - Resolving

    /// Turns a saved arrangement into frames that fit the area and do not overlap, whatever the screen is now.
    public func resolve(_ arrangement: Arrangement) -> ArrangedFrames {
        var preview = clampPreview(
            origin: CGPoint(x: area.minX + arrangement.preview.minX * area.width,
                            y: area.minY + arrangement.preview.minY * area.height),
            width: arrangement.preview.width * area.width
        )
        var text = clamp(CGRect(
            x: area.minX + arrangement.text.minX * area.width,
            y: area.minY + arrangement.text.minY * area.height,
            width: arrangement.text.width * area.width,
            height: arrangement.text.height * area.height
        ))
        if !textMayCoverPreview, overlaps(preview, text) {
            if let shrunk = shrink(text, avoiding: preview) {
                text = shrunk
            } else if let shrunk = shrinkPreview(preview, avoiding: text) {
                preview = shrunk
            } else {
                text = shrink(text, avoiding: preview) ?? text
            }
        }
        return ArrangedFrames(preview: preview, text: text)
    }

    // MARK: - Moving

    /// Moves an item so its top-left corner is at `origin`, as far as it can go without leaving the area or
    /// touching the other item.
    public func move(_ item: ArrangedItem, in frames: ArrangedFrames, to origin: CGPoint) -> ArrangedFrames {
        var result = frames
        if textMayCoverPreview {
            switch item {
            case .preview: result.preview = clampOrigin(CGRect(origin: origin, size: frames.preview.size))
            case .text: result.text = clampOrigin(CGRect(origin: origin, size: frames.text.size))
            }
            return result
        }
        switch item {
        case .preview:
            let size = frames.preview.size
            if let rect = place(CGRect(origin: origin, size: size), avoiding: frames.text) {
                result.preview = rect
            }
        case .text:
            let size = frames.text.size
            if let rect = place(CGRect(origin: origin, size: size), avoiding: frames.preview) {
                result.text = rect
            }
        }
        return result
    }

    /// Clamps a rect of fixed size into the area and slides it out of `other`, the shortest way that still
    /// fits. Nil when there is no free spot.
    private func place(_ proposed: CGRect, avoiding other: CGRect) -> CGRect? {
        let inside = clampOrigin(proposed)
        guard overlaps(inside, other) else { return inside }
        let size = inside.size
        let candidates = [
            CGPoint(x: other.minX - gap - size.width, y: inside.minY),
            CGPoint(x: other.maxX + gap, y: inside.minY),
            CGPoint(x: inside.minX, y: other.minY - gap - size.height),
            CGPoint(x: inside.minX, y: other.maxY + gap),
        ]
        return candidates
            .map { clampOrigin(CGRect(origin: $0, size: size)) }
            .filter { !overlaps($0, other) }
            .min { distance($0.origin, inside.origin) < distance($1.origin, inside.origin) }
    }

    // MARK: - Resizing

    /// Resizes the preview to `width`, keeping its top-left corner and its aspect ratio. The text shrinks if the
    /// preview would run into it; if it cannot shrink enough, the preview stops growing.
    public func resizePreview(in frames: ArrangedFrames, width requested: CGFloat) -> ArrangedFrames {
        if textMayCoverPreview {
            let width = min(max(requested, minPreviewWidth), maxPreviewWidth(from: frames.preview.origin))
            return ArrangedFrames(preview: clampPreview(origin: frames.preview.origin, width: width), text: frames.text)
        }
        var width = min(max(requested, minPreviewWidth), maxPreviewWidth(from: frames.preview.origin))
        while true {
            let preview = clampPreview(origin: frames.preview.origin, width: width)
            if !overlaps(preview, frames.text) {
                return ArrangedFrames(preview: preview, text: frames.text)
            }
            if let text = shrink(frames.text, avoiding: preview) {
                return ArrangedFrames(preview: preview, text: text)
            }
            guard width > minPreviewWidth, width > frames.preview.width else {
                return frames
            }
            width = max(width - 4, max(minPreviewWidth, frames.preview.width))
        }
    }

    /// Resizes the text to `size`, keeping its top-left corner. The preview shrinks (same aspect ratio) if the text
    /// would run into it; if it cannot shrink enough, the text stops growing.
    public func resizeText(in frames: ArrangedFrames, size requested: CGSize) -> ArrangedFrames {
        var target = clamp(CGRect(origin: frames.text.origin, size: requested))
        if textMayCoverPreview { return ArrangedFrames(preview: frames.preview, text: target) }
        if !overlaps(frames.preview, target) {
            return ArrangedFrames(preview: frames.preview, text: target)
        }
        if let preview = shrinkPreview(frames.preview, avoiding: target) {
            return ArrangedFrames(preview: preview, text: target)
        }
        // The preview is as small as it goes: hold the text off it.
        target = shrink(target, avoiding: frames.preview) ?? frames.text
        return ArrangedFrames(preview: frames.preview, text: target)
    }

    // MARK: - Helpers

    private func maxPreviewWidth(from origin: CGPoint) -> CGFloat {
        max(min(area.maxX - origin.x, (area.maxY - origin.y) * aspect), minPreviewWidth)
    }

    private func clampPreview(origin: CGPoint, width requested: CGFloat) -> CGRect {
        let limit = min(area.width, area.height * aspect)
        let width = min(max(requested, min(minPreviewWidth, limit)), limit)
        let size = CGSize(width: width, height: width / aspect)
        return clampOrigin(CGRect(origin: origin, size: size))
    }

    /// Size limits for the text, then the area.
    private func clamp(_ rect: CGRect) -> CGRect {
        let size = CGSize(
            width: min(max(rect.width, min(minText.width, area.width)), area.width),
            height: min(max(rect.height, min(minText.height, area.height)), area.height)
        )
        return clampOrigin(CGRect(origin: rect.origin, size: size))
    }

    private func clampOrigin(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(max(rect.minX, area.minX), max(area.maxX - rect.width, area.minX)),
            y: min(max(rect.minY, area.minY), max(area.maxY - rect.height, area.minY)),
            width: rect.width,
            height: rect.height
        )
    }

    /// True when the rects are closer than the gap.
    private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(b.insetBy(dx: -gap / 2, dy: -gap / 2).insetBy(dx: 0.01, dy: 0.01))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// The largest cut of `rect`, as one side of `other`, that is still at least the minimum text size.
    private func shrink(_ rect: CGRect, avoiding other: CGRect) -> CGRect? {
        guard overlaps(rect, other) else { return rect }
        // CGRect reports width and height as absolute values, so the sides are checked before a rect is made.
        func cut(minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) -> CGRect? {
            guard maxX - minX >= minText.width, maxY - minY >= minText.height else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        let cuts = [
            cut(minX: rect.minX, minY: rect.minY, maxX: other.minX - gap, maxY: rect.maxY),
            cut(minX: other.maxX + gap, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY),
            cut(minX: rect.minX, minY: rect.minY, maxX: rect.maxX, maxY: other.minY - gap),
            cut(minX: rect.minX, minY: other.maxY + gap, maxX: rect.maxX, maxY: rect.maxY),
        ]
        return cuts
            .compactMap { $0 }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// The preview scaled about its center, as large as it can be without touching `other`. Nil when even the
    /// smallest preview touches it.
    private func shrinkPreview(_ preview: CGRect, avoiding other: CGRect) -> CGRect? {
        func scaled(_ width: CGFloat) -> CGRect {
            let size = CGSize(width: width, height: width / aspect)
            return clampOrigin(CGRect(x: preview.midX - size.width / 2, y: preview.midY - size.height / 2,
                                      width: size.width, height: size.height))
        }
        guard overlaps(preview, other) else { return preview }
        var low = minPreviewWidth
        var high = preview.width
        guard !overlaps(scaled(low), other) else { return nil }
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if overlaps(scaled(middle), other) { high = middle } else { low = middle }
        }
        return scaled(low)
    }
}
