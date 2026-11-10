import AVFoundation
import SwiftUI
import UIKit

/// Live preview, scaled into the layout's preview frame, of the camera. Tap to focus and expose, pinch to zoom.
struct CameraPreview: UIViewRepresentable {
    let engine: CameraEngine
    /// Controls area in window coordinates; taps there go to the controls, not to focus.
    let passThrough: CGRect
    /// Called when the preview is pressed and held, to start moving and resizing it.
    var onLongPress: () -> Void = {}

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = engine.session
        view.previewLayer.videoGravity = .resizeAspectFill

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHold(_:)))
        hold.minimumPressDuration = 0.5
        view.addGestureRecognizer(hold)
        engine.onFaces = { [weak view] faces in view?.showFaces(faces) }
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.engine = engine
        context.coordinator.onLongPress = onLongPress
        uiView.passThroughRect = passThrough
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    @MainActor
    final class Coordinator: NSObject {
        var engine: CameraEngine
        weak var view: PreviewUIView?
        private var zoomAtPinchStart: CGFloat = 1
        var onLongPress: () -> Void = {}

        @objc func handleHold(_ hold: UILongPressGestureRecognizer) {
            guard hold.state == .began else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress()
        }

        init(engine: CameraEngine) {
            self.engine = engine
        }

        @objc func handleTap(_ tap: UITapGestureRecognizer) {
            guard let view else { return }
            let point = view.previewLayer.captureDevicePointConverted(fromLayerPoint: tap.location(in: view))
            engine.focus(at: point)
        }

        @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
            switch pinch.state {
            case .began:
                zoomAtPinchStart = engine.zoomFactor
            case .changed:
                engine.setZoom(zoomAtPinchStart * pinch.scale)
            default:
                break
            }
        }
    }
}

/// The layer-backed view that shows the camera. Keeps the preview upright as the device rotates.
final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Controls area in window coordinates. Touches there are not handled here.
    var passThroughRect: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if passThroughRect.contains(convert(point, to: nil)) {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    private var faceLayers: [CAShapeLayer] = []

    /// Outlines the detected faces on the preview. The outline fades when the face is gone.
    func showFaces(_ faces: [AVMetadataObject]) {
        let rects = faces.compactMap { previewLayer.transformedMetadataObject(for: $0)?.bounds }
        while faceLayers.count < rects.count {
            let layer = CAShapeLayer()
            layer.fillColor = UIColor.clear.cgColor
            layer.strokeColor = UIColor.systemYellow.cgColor
            layer.lineWidth = 2
            self.layer.addSublayer(layer)
            faceLayers.append(layer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, layer) in faceLayers.enumerated() {
            if index < rects.count {
                layer.path = UIBezierPath(roundedRect: rects[index].insetBy(dx: -4, dy: -4), cornerRadius: 10).cgPath
                layer.isHidden = false
            } else {
                layer.isHidden = true
            }
        }
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let connection = previewLayer.connection,
              let angle = CameraEngine.rotationAngle(for: UIDevice.current.orientation),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

/// The live picture filling the whole view, with no gestures: a backdrop behind the real preview.
struct CameraBackdrop: UIViewRepresentable {
    let engine: CameraEngine

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = engine.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
