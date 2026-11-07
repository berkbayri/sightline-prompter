import AVFoundation
import SwiftUI
import UIKit

/// Live preview, scaled into the layout's preview frame, of the camera. Tap to focus and expose, pinch to zoom.
struct CameraPreview: UIViewRepresentable {
    let engine: CameraEngine
    /// Controls area in window coordinates; taps there go to the controls, not to focus.
    let passThrough: CGRect

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = engine.session
        view.previewLayer.videoGravity = .resizeAspectFill

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.engine = engine
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let connection = previewLayer.connection,
              let angle = CameraEngine.rotationAngle(for: UIDevice.current.orientation),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
