import CoreVideo
import Foundation
import ImageIO
import Vision

/// What one camera frame says about the face in front of it.
public struct FaceSample: Equatable, Sendable {
    /// Distance between the pupils in pixels of the frame.
    public let ipdPx: Double
    /// Head turn in radians (0 = facing the camera).
    public let yawRad: Double
}

/// Vision face landmarks to a pupil distance. Used by the iPhone (metric distance) and the Mac (relative).
/// Nothing is stored or sent; the frame is read in memory and dropped.
public enum FaceMeasure {
    /// The largest face in the frame, or nil when there is none. `orientation` says how the frame must be
    /// turned to be upright (the camera's frames are sensor-oriented), so Vision can find the face.
    public static func largestFace(in buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> FaceSample? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
        guard (try? handler.perform([request])) != nil,
              let face = request.results?.max(by: { area($0) < area($1) }),
              let landmarks = face.landmarks else { return nil }

        // Landmark points are normalized to the face box, and the box to the upright image.
        let quarterTurn: [CGImagePropertyOrientation] = [.left, .right, .leftMirrored, .rightMirrored]
        let swapped = quarterTurn.contains(orientation)
        let width = Double(swapped ? CVPixelBufferGetHeight(buffer) : CVPixelBufferGetWidth(buffer))
        let height = Double(swapped ? CVPixelBufferGetWidth(buffer) : CVPixelBufferGetHeight(buffer))
        let box = face.boundingBox

        func center(_ pupil: VNFaceLandmarkRegion2D?, _ eye: VNFaceLandmarkRegion2D?) -> CGPoint? {
            // The pupil when Vision found it, else the middle of the eye outline.
            let points = pupil?.normalizedPoints.isEmpty == false ? pupil?.normalizedPoints : eye?.normalizedPoints
            guard let points, !points.isEmpty else { return nil }
            let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
            let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
            return CGPoint(x: (box.minX + x * box.width) * width, y: (box.minY + y * box.height) * height)
        }
        guard let left = center(landmarks.leftPupil, landmarks.leftEye),
              let right = center(landmarks.rightPupil, landmarks.rightEye) else { return nil }
        return FaceSample(ipdPx: Double(hypot(left.x - right.x, left.y - right.y)), yawRad: face.yaw?.doubleValue ?? 0)
    }

    private static func area(_ face: VNFaceObservation) -> CGFloat {
        face.boundingBox.width * face.boundingBox.height
    }
}
