import SightlineCore
import SwiftUI

/// Arrange mode: the camera preview and the prompter text can be dragged around and resized. Drag an item to
/// move it, drag the handle on its corner to resize it. The preview keeps its aspect ratio, the text is free,
/// and the two never overlap: resizing one shrinks the other when needed (see ArrangementGeometry).
struct ArrangeOverlay: View {
    @Binding var frames: ArrangedFrames
    @Binding var selected: ArrangedItem
    let geometry: ArrangementGeometry
    let onCommit: (ArrangedFrames) -> Void

    private enum Mode {
        case move(ArrangedItem)
        case resize(ArrangedItem)
    }

    @State private var start: ArrangedFrames?
    @State private var mode: Mode?

    private let handleSize: CGFloat = 30

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(drag)
            outline(for: .preview)
            outline(for: .text)
        }
        .allowsHitTesting(true)
    }

    // MARK: - Drawing

    private func rect(of item: ArrangedItem) -> CGRect {
        item == .preview ? frames.preview : frames.text
    }

    private func outline(for item: ArrangedItem) -> some View {
        let frame = rect(of: item)
        let isSelected = selected == item
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.yellow : Color.white.opacity(0.5),
                    style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: isSelected ? [] : [6, 4])
                )
            if isSelected {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(Color.yellow, in: Circle())
                    .padding(4)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if start == nil {
                    start = frames
                    mode = pick(at: value.startLocation)
                }
                guard let start, let mode else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                switch mode {
                case .move(let item):
                    let origin = rect(of: item, in: start).origin
                    frames = geometry.move(item, in: start, to: CGPoint(x: origin.x + dx, y: origin.y + dy))
                case .resize(.preview):
                    let box = start.preview
                    // The corner follows the finger; the width comes from both axes so either one can drive it.
                    let width = ((box.width + dx) + (box.height + dy) * geometry.aspect) / 2
                    frames = geometry.resizePreview(in: start, width: width)
                case .resize(.text):
                    frames = geometry.resizeText(in: start, size: CGSize(width: start.text.width + dx, height: start.text.height + dy))
                }
            }
            .onEnded { _ in
                if start != nil { onCommit(frames) }
                start = nil
                mode = nil
            }
    }

    private func rect(of item: ArrangedItem, in frames: ArrangedFrames) -> CGRect {
        item == .preview ? frames.preview : frames.text
    }

    /// The handle of the selected item resizes it; any other touch on an item selects and moves that item.
    private func pick(at point: CGPoint) -> Mode? {
        let current = rect(of: selected)
        let handle = CGRect(x: current.maxX - handleSize, y: current.maxY - handleSize, width: handleSize + 10, height: handleSize + 10)
        if handle.contains(point) { return .resize(selected) }
        if frames.text.contains(point) {
            selected = .text
            return .move(.text)
        }
        if frames.preview.contains(point) {
            selected = .preview
            return .move(.preview)
        }
        return nil
    }
}

/// Buttons shown in the controls area while arranging.
struct ArrangeBar: View {
    let layout: CameraLayout
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        let frame = layout.controlsFrame
        let stack = layout.isLandscape ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        stack {
            Text("Drag to move.\nDrag the corner to resize.\nThe text floats over the video.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset layout")
            .accessibilityIdentifier("arrange.reset")
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .accessibilityIdentifier("arrange.done")
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }
}
