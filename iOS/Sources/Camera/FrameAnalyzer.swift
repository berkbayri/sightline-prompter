import AVFoundation
import SightlineCore
import UIKit

/// Reads the small analysis frames the capture session delivers next to the recording. It does two cheap
/// jobs, each only when asked: the viewing distance from the pupil distance (about 5 Hz) and the brightness
/// of the picture behind each line of text (about 10 Hz). Frames are read in memory and dropped; nothing is
/// stored or sent. The movie output and the formats are untouched.
final class FrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct LumaTarget {
        let key: Int
        /// Where to look, 0...1 in the camera's own (unrotated) picture, as `metadataOutputRectConverted` gives it.
        let rect: CGRect
    }

    private let lock = NSLock()
    private var measuring = false
    private var targets: [LumaTarget] = []
    private var orientation = CGImagePropertyOrientation.leftMirrored
    private var fallbackFOV: Double?
    private var zoom: Double = 1
    private var lastFace = -Double.infinity
    private var lastLuma = -Double.infinity

    /// Viewing distance in millimetres, from a usable face. Called on the analysis queue.
    var onDistance: (@Sendable (Double) -> Void)?
    /// Encoded luma (0...1) behind each target, 90th percentile. Called on the analysis queue.
    var onLuma: (@Sendable ([Int: Double]) -> Void)?

    func configure(measuring: Bool? = nil, targets: [LumaTarget]? = nil, orientation: CGImagePropertyOrientation? = nil,
                   fallbackFOV: Double?? = nil, zoom: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let measuring { self.measuring = measuring }
        if let targets { self.targets = targets }
        if let orientation { self.orientation = orientation }
        if let fallbackFOV { self.fallbackFOV = fallbackFOV }
        if let zoom { self.zoom = zoom }
    }

    /// How a sensor-oriented frame must be turned to be upright, for Vision. The front camera's picture is mirrored.
    static func visionOrientation(for device: UIDeviceOrientation, front: Bool) -> CGImagePropertyOrientation {
        switch device {
        case .portraitUpsideDown: front ? .rightMirrored : .left
        case .landscapeLeft: front ? .downMirrored : .down
        case .landscapeRight: front ? .upMirrored : .up
        default: front ? .leftMirrored : .right
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let measuring = measuring, targets = targets, orientation = orientation, fov = fallbackFOV, zoom = zoom
        lock.unlock()
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let wantsFace = measuring && time - lastFace >= 0.19
        let wantsLuma = !targets.isEmpty && time - lastLuma >= 0.09
        guard wantsFace || wantsLuma, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if wantsLuma {
            lastLuma = time
            onLuma?(Self.luma(in: buffer, targets: targets))
        }
        if wantsFace {
            lastFace = time
            guard let face = FaceMeasure.largestFace(in: buffer, orientation: orientation),
                  let focal = Self.focalPx(sampleBuffer, buffer: buffer, fov: fov, zoom: zoom),
                  let distance = PrompterTypography.distanceMm(ipdPx: face.ipdPx, yawRad: face.yawRad, focalPx: focal)
            else { return }
            onDistance?(distance)
        }
    }

    /// Focal length in pixels of the delivered frame: from the camera intrinsics when the frame carries them
    /// (the principal point sits at the middle, so twice its x is the width they refer to), else from the
    /// format's field of view and the zoom.
    private static func focalPx(_ sample: CMSampleBuffer, buffer: CVPixelBuffer, fov: Double?, zoom: Double) -> Double? {
        let width = Double(CVPixelBufferGetWidth(buffer))
        if let data = CMGetAttachment(sample, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data,
           data.count >= MemoryLayout<matrix_float3x3>.size {
            let matrix = data.withUnsafeBytes { $0.loadUnaligned(as: matrix_float3x3.self) }
            let fx = Double(matrix.columns.0.x), cx = Double(matrix.columns.2.x)
            if fx > 0, cx > 0 { return fx * width / (2 * cx) }
        }
        return fov.map { PrompterTypography.focalPx(horizontalFOVDeg: $0, imageWidthPx: width) * zoom }
    }

    /// 90th percentile of the Y plane over an 8 x 8 grid inside each target. Y of a video frame is already
    /// sRGB-encoded, which is what `PrompterTypography.scrimAlpha` expects.
    private static func luma(in buffer: CVPixelBuffer, targets: [LumaTarget]) -> [Int: Double] {
        guard CVPixelBufferGetPlaneCount(buffer) > 0, CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return [:] }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self) else { return [:] }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let grid = 8
        var result: [Int: Double] = [:]
        for target in targets {
            var values: [UInt8] = []
            values.reserveCapacity(grid * grid)
            for row in 0..<grid {
                for column in 0..<grid {
                    let u = target.rect.minX + target.rect.width * (CGFloat(column) + 0.5) / CGFloat(grid)
                    let v = target.rect.minY + target.rect.height * (CGFloat(row) + 0.5) / CGFloat(grid)
                    let x = min(max(Int(u * CGFloat(width)), 0), width - 1)
                    let y = min(max(Int(v * CGFloat(height)), 0), height - 1)
                    values.append(base[y * stride + x])
                }
            }
            values.sort()
            result[target.key] = Double(values[values.count * 9 / 10]) / 255
        }
        return result
    }
}
