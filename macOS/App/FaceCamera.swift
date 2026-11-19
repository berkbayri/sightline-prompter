import AVFoundation
import SightlineCore

enum FaceCameraError: Error {
    case denied, none
}

/// The Mac's built-in camera, used only to read how wide your face is in the picture (Vision pupil distance,
/// about 5 times a second). Frames are read in memory and dropped; nothing is saved or sent. The built-in
/// camera is picked explicitly, so a Continuity Camera iPhone is never switched on.
final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "sightline.facecamera")
    private var last = -Double.infinity
    /// Pupil distance in pixels of the frame. Called on the camera queue.
    var onIPD: (@Sendable (Double) -> Void)?

    /// Starts the camera and returns its name. Throws when access is off or there is no built-in camera.
    func start() async throws -> String {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw FaceCameraError.denied }
        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.first,
              let input = try? AVCaptureDeviceInput(device: device) else { throw FaceCameraError.none }
        let session = self.session
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        queue.async {
            session.beginConfiguration()
            session.sessionPreset = .vga640x480 // small frames: cheap, and the face is large in them
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
        }
        return device.localizedName
    }

    func stop() {
        let session = self.session
        queue.async {
            session.stopRunning()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - last >= 0.19, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        last = time
        guard let face = FaceMeasure.largestFace(in: buffer),
              abs(face.yawRad) <= PrompterTypography.yawRejectDeg * .pi / 180,
              face.ipdPx >= PrompterTypography.minIPDPx else { return }
        onIPD?(face.ipdPx / cos(face.yawRad))
    }
}
