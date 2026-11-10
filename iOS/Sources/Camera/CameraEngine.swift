import AVFoundation
import CoreMedia
import CoreVideo
import Photos
import SightlineCore
import UIKit

/// The live camera behind the prompter. Wraps AVCaptureSession and exposes the controls the iPhone camera
/// offers through public AVFoundation API: lenses and zoom, focus, exposure and white balance locks, video
/// format (resolution, frame rate, HDR, color space), stabilization, torch, codecs (including ProRes),
/// and saving to Photos.
@MainActor
final class CameraEngine: NSObject, ObservableObject {
    // MARK: - Types

    enum Status: Equatable {
        case idle, unauthorized, running, failed(String)
    }

    /// One selectable recording mode: a device format at a frame rate.
    struct VideoMode: Hashable, Identifiable {
        let width: Int32
        let height: Int32
        let frameRate: Int
        let formatIndex: Int
        let frameDuration: CMTime

        var id: String { "\(width)x\(height)@\(frameRate)" }

        var aspect: AspectRatio? { AspectRatio(width: width, height: height) }

        var resolutionName: String {
            // Only true 16:9 sizes get the marketing names; a 4:3 sensor format is shown by its pixels.
            guard aspect == .widescreen else { return "\(width)×\(height)" }
            if height >= 2160 { return "4K" }
            if height >= 1080 { return "1080p" }
            if height >= 720 { return "720p" }
            return "\(width)×\(height)"
        }

        var label: String { "\(resolutionName) · \(frameRate) fps" }
    }

    /// Shape of the recorded video. Both are native sensor formats, so nothing is cropped.
    enum AspectRatio: String, CaseIterable, Identifiable {
        case widescreen, standard

        var id: String { rawValue }
        var name: String { self == .widescreen ? "16:9" : "4:3" }
        /// Width divided by height, in landscape.
        var ratio: CGFloat { self == .widescreen ? 16.0 / 9.0 : 4.0 / 3.0 }

        init?(width: Int32, height: Int32) {
            guard height > 0 else { return nil }
            let value = CGFloat(width) / CGFloat(height)
            if abs(value - 16.0 / 9.0) < 0.03 {
                self = .widescreen
            } else if abs(value - 4.0 / 3.0) < 0.03 {
                self = .standard
            } else {
                return nil
            }
        }
    }

    enum Codec: String, CaseIterable, Identifiable {
        case h264, hevc, proRes422, proRes422HQ

        var id: String { rawValue }

        var videoType: AVVideoCodecType {
            switch self {
            case .h264: .h264
            case .hevc: .hevc
            case .proRes422: .proRes422
            case .proRes422HQ: .proRes422HQ
            }
        }

        var name: String {
            switch self {
            case .h264: "H.264"
            case .hevc: "HEVC"
            case .proRes422: "ProRes 422"
            case .proRes422HQ: "ProRes 422 HQ"
            }
        }
    }

    enum ColorMode: String, CaseIterable, Identifiable {
        case standard, wideColor, hdr, appleLog

        var id: String { rawValue }

        var name: String {
            switch self {
            case .standard: "Standard"
            case .wideColor: "Wide color"
            case .hdr: "HDR (HLG)"
            case .appleLog: "Apple Log"
            }
        }

        var captureSpace: AVCaptureColorSpace {
            switch self {
            case .standard: .sRGB
            case .wideColor: .P3_D65
            case .hdr: .HLG_BT2020
            case .appleLog: .appleLog
            }
        }
    }

    enum Stabilization: String, CaseIterable, Identifiable {
        case off, standard, cinematic, cinematicExtended, auto

        var id: String { rawValue }

        var name: String {
            switch self {
            case .off: "Off"
            case .standard: "Standard"
            case .cinematic: "Cinematic"
            case .cinematicExtended: "Cinematic Extended"
            case .auto: "Auto"
            }
        }

        var mode: AVCaptureVideoStabilizationMode {
            switch self {
            case .off: .off
            case .standard: .standard
            case .cinematic: .cinematic
            case .cinematicExtended: .cinematicExtended
            case .auto: .auto
            }
        }
    }

    /// Frame rates offered for each format. Rates outside a format's supported ranges are skipped.
    private static let commonFrameRates = [24, 25, 30, 50, 60, 120, 240]
    /// Pixel formats of camera video (8-bit and 10-bit, video and full range). Photo and depth formats are excluded.
    private static let videoPixelFormats: Set<OSType> = [
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
    ]

    // MARK: - Published state

    @Published private(set) var status: Status = .idle
    @Published private(set) var position: AVCaptureDevice.Position = .front
    @Published private(set) var zoomPresets: [CGFloat] = [1]
    @Published private(set) var zoomFactor: CGFloat = 1
    /// Every launch starts with 16:9, 4K at 30 fps on the front camera (the nearest mode if the device lacks it).
    @Published private(set) var aspect: AspectRatio = .widescreen
    @Published private(set) var aspects: [AspectRatio] = [.widescreen]
    @Published private(set) var videoModes: [VideoMode] = []
    @Published private(set) var selectedMode: VideoMode?
    @Published private(set) var colorModes: [ColorMode] = [.standard]
    @Published private(set) var colorMode: ColorMode = .standard
    @Published private(set) var hdrSupported = false
    @Published private(set) var hdrEnabled = false
    @Published private(set) var codecs: [Codec] = [.hevc]
    @Published private(set) var codec: Codec = .hevc
    @Published private(set) var stabilizationModes: [Stabilization] = [.off]
    @Published private(set) var stabilization: Stabilization = .off
    @Published private(set) var torchAvailable = false
    @Published private(set) var torchOn = false
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var exposureRange: ClosedRange<Float> = 0...0
    @Published private(set) var exposureLocked = false
    @Published private(set) var focusLocked = false
    @Published private(set) var whiteBalanceLocked = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordedSeconds = 0
    @Published private(set) var hasMicrophone = false
    /// Last result or error, shown briefly under the controls.
    @Published private(set) var message: String?

    // MARK: - Session

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sightline.camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "sightline.camera.audio")
    private var audioDelegate: AudioSampleDelegate?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private(set) var device: AVCaptureDevice?
    private var configured = false
    private var movieDelegate: MovieDelegate?
    private let metadataOutput = AVCaptureMetadataOutput()
    private var faceDelegate: FaceDelegate?
    private var subjectAreaObserver: NSObjectProtocol?

    /// Faces the camera currently sees, as metadata objects. Called on the main actor; empty when none.
    var onFaces: (([AVMetadataObject]) -> Void)?

    /// Microphone audio as it is recorded, for live speech tracking. Called on the main actor.
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var recordingTimer: Timer?
    private var recordingStart: Date?

    // MARK: - Lifecycle

    /// Asks for camera and microphone access, builds the session once, and starts it.
    func start() {
        guard status != .running else { return }
        Task {
            let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
            guard videoGranted else {
                status = .unauthorized
                message = "Camera access is off. Turn it on in Settings › Sightline Prompter."
                return
            }
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            configure()
            guard configured else { return }
            let session = self.session
            sessionQueue.async { session.startRunning() }
            status = .running
            message = nil
        }
    }

    /// Stops the session. A recording in progress is finished and saved first.
    func stop() {
        if isRecording {
            stopRecording()
        }
        let session = self.session
        sessionQueue.async { session.stopRunning() }
        status = .idle
    }

    private func configure() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = Self.device(for: position), let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            status = .failed("No camera is available on this device.")
            message = "No camera is available on this device."
            return
        }
        session.addInput(input)
        videoInput = input
        device = camera

        if let microphone = AVCaptureDevice.default(for: .audio),
           let audio = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audio) {
            session.addInput(audio)
            audioInput = audio
            hasMicrophone = true

            let delegate = AudioSampleDelegate { [weak self] buffer in
                Task { @MainActor in self?.onAudioBuffer?(buffer) }
            }
            audioDelegate = delegate
            audioOutput.setSampleBufferDelegate(delegate, queue: audioQueue)
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        // Face detection: the preview outlines the faces, and focus and exposure follow them.
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            if metadataOutput.availableMetadataObjectTypes.contains(.face) {
                metadataOutput.metadataObjectTypes = [.face]
                let delegate = FaceDelegate { [weak self] faces in
                    Task { @MainActor in self?.onFaces?(faces) }
                }
                faceDelegate = delegate
                metadataOutput.setMetadataObjectsDelegate(delegate, queue: .main)
            }
        }
        session.commitConfiguration()
        configured = true
        observeSessionInterruptions()
        refreshDeviceState()
    }

    /// Picks the most capable camera for the position: the virtual triple/dual camera on back, which switches
    /// lenses on its own as the zoom changes.
    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return nil
    }

    /// Switches between the back and front cameras. Not allowed while recording.
    func switchCamera() {
        guard !isRecording, configured else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let camera = Self.device(for: next), let input = try? AVCaptureDeviceInput(device: camera) else {
            message = "This camera is not available."
            return
        }
        session.beginConfiguration()
        if let videoInput {
            session.removeInput(videoInput)
        }
        session.sessionPreset = .high
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            device = camera
            position = next
        } else if let videoInput, session.canAddInput(videoInput) {
            session.addInput(videoInput)
            message = "Could not switch camera."
        }
        session.commitConfiguration()
        refreshDeviceState()
    }

    // MARK: - Device state

    /// A notification sound, a call or a media-services reset can stop the capture session. It is started
    /// again as soon as the system lets it, so the camera, the recording and the audio feed carry on.
    private func observeSessionInterruptions() {
        let center = NotificationCenter.default
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.interruptionEndedNotification] {
            center.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeSessionIfStopped() }
            }
        }
    }

    private func resumeSessionIfStopped() {
        guard status == .running else { return }
        let session = self.session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    /// Whether Sightline Pro is unlocked. The free version records 1080p at up to 30 fps, in 16:9, for two minutes.
    var isProUnlocked: () -> Bool = { true }
    /// Called when a free recording was stopped at the time limit.
    var onRecordingLimit: (() -> Void)?

    /// The purchase state changed: offer the modes and codecs it allows.
    func entitlementChanged() {
        guard configured, !isRecording else { return }
        refreshDeviceState()
    }

    /// Re-reads everything the controls show from the current device, and re-applies the chosen settings.
    /// Face-driven autofocus and auto exposure on, in continuous modes, so the camera keeps the face sharp and
    /// well exposed. A tap to focus switches to a single focus; when the scene changes the continuous mode, and
    /// with it the face tracking, comes back.
    private func enableFaceTracking() {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = true
            device.automaticallyAdjustsFaceDrivenAutoExposureEnabled = true
            if !focusLocked, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if !exposureLocked, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {}
        if let subjectAreaObserver { NotificationCenter.default.removeObserver(subjectAreaObserver) }
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.focusLocked, !self.exposureLocked else { return }
                self.enableFaceTracking()
            }
        }
    }

    private func refreshDeviceState() {
        guard let device else { return }
        enableFaceTracking()
        let format = device.activeFormat

        zoomPresets = Self.zoomPresets(for: device)
        zoomFactor = device.videoZoomFactor

        let pro = isProUnlocked()
        let allModes = Self.modes(for: device).filter {
            pro || ($0.height <= FreeTier.maxVideoHeight && $0.frameRate <= FreeTier.maxFrameRate)
        }
        aspects = AspectRatio.allCases.filter { shape in
            (pro || shape == .widescreen) && allModes.contains { $0.aspect == shape }
        }
        if !aspects.contains(aspect), let first = aspects.first {
            aspect = first
        }
        videoModes = allModes.filter { $0.aspect == aspect }
        if videoModes.isEmpty { videoModes = allModes }
        let previous = selectedMode
        let wanted = videoModes.first { $0.id == previous?.id }
            ?? videoModes.first { $0.height == previous?.height && $0.frameRate == previous?.frameRate }
            ?? videoModes.first { $0.height == 2160 && $0.frameRate == 30 }
            ?? videoModes.first { $0.width == 1920 && $0.frameRate == 30 }
            ?? videoModes.first { $0.frameRate == 30 }
            ?? videoModes.first
        if let wanted {
            applyMode(wanted)
        }

        colorModes = ColorMode.allCases.filter { format.supportedColorSpaces.contains($0.captureSpace) }
        if !colorModes.contains(colorMode) {
            colorMode = colorModes.first ?? .standard
        }
        applyColorMode(colorMode)

        hdrSupported = pro && format.isVideoHDRSupported
        if !pro { hdrEnabled = false }
        applyHDR(hdrEnabled)

        codecs = Codec.allCases.filter {
            movieOutput.availableVideoCodecTypes.contains($0.videoType) && (pro || $0 == .hevc || $0 == .h264)
        }
        if !codecs.contains(codec) {
            codec = codecs.first ?? .h264
        }

        stabilizationModes = Stabilization.allCases.filter {
            $0 == .off || format.isVideoStabilizationModeSupported($0.mode)
        }
        if !stabilizationModes.contains(stabilization) {
            stabilization = .off
        }
        applyStabilization(stabilization)

        torchAvailable = device.hasTorch
        exposureRange = device.minExposureTargetBias...device.maxExposureTargetBias
        exposureBias = device.exposureTargetBias
        updateOrientation(UIDevice.current.orientation)
    }

    /// Zoom stops for the buttons: the ultra-wide 0.5x when the virtual camera has it, then 1x, the
    /// lens switch-over points and common digital stops, all within the device's range.
    private static func zoomPresets(for device: AVCaptureDevice) -> [CGFloat] {
        var stops: Set<CGFloat> = [1]
        if device.minAvailableVideoZoomFactor < 1 {
            stops.insert(device.minAvailableVideoZoomFactor.rounded(toPlaces: 1))
        }
        for factor in device.virtualDeviceSwitchOverVideoZoomFactors {
            stops.insert(CGFloat(truncating: factor))
        }
        for factor: CGFloat in [2, 3, 5] {
            stops.insert(factor)
        }
        let range = device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor
        return stops.filter { range.contains($0) }.sorted()
    }

    /// Every recording mode the device offers: each format's resolution at each common frame rate.
    private static func modes(for device: AVCaptureDevice) -> [VideoMode] {
        var result: [VideoMode] = []
        var seen = Set<String>()
        for (index, format) in device.formats.enumerated() {
            let description = format.formatDescription
            guard videoPixelFormats.contains(CMFormatDescriptionGetMediaSubType(description)) else { continue }
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            for range in format.videoSupportedFrameRateRanges {
                for rate in commonFrameRates {
                    let fps = Double(rate)
                    guard fps <= range.maxFrameRate + 0.5, fps >= range.minFrameRate - 0.5 else { continue }
                    let mode = VideoMode(
                        width: dimensions.width,
                        height: dimensions.height,
                        frameRate: rate,
                        formatIndex: index,
                        frameDuration: CMTime(value: 1, timescale: CMTimeScale(rate))
                    )
                    if seen.insert(mode.id).inserted {
                        result.append(mode)
                    }
                }
            }
        }
        return result.sorted {
            ($0.height, $0.width, $0.frameRate) < ($1.height, $1.width, $1.frameRate)
        }
    }

    // MARK: - Format, color, HDR, stabilization

    /// Switches the video shape and keeps the closest resolution and frame rate.
    func selectAspect(_ shape: AspectRatio) {
        guard !isRecording, shape != aspect else { return }
        aspect = shape
        refreshDeviceState()
    }

    /// Applies a recording mode: the device format and its frame duration.
    func selectMode(_ mode: VideoMode) {
        applyMode(mode)
        refreshDeviceState()
    }

    private func applyMode(_ mode: VideoMode) {
        guard let device, mode.formatIndex < device.formats.count else { return }
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        do {
            try device.lockForConfiguration()
            device.activeFormat = device.formats[mode.formatIndex]
            device.activeVideoMinFrameDuration = mode.frameDuration
            device.activeVideoMaxFrameDuration = mode.frameDuration
            device.unlockForConfiguration()
            selectedMode = mode
        } catch {
            message = "Could not change the video format."
        }
        session.commitConfiguration()
    }

    func selectColorMode(_ mode: ColorMode) {
        colorMode = mode
        applyColorMode(mode)
    }

    private func applyColorMode(_ mode: ColorMode) {
        guard let device, device.activeFormat.supportedColorSpaces.contains(mode.captureSpace) else { return }
        do {
            try device.lockForConfiguration()
            device.activeColorSpace = mode.captureSpace
            device.unlockForConfiguration()
        } catch {
            message = "Could not change the color mode."
        }
    }

    func setHDR(_ enabled: Bool) {
        hdrEnabled = enabled
        applyHDR(enabled)
    }

    private func applyHDR(_ enabled: Bool) {
        guard let device, device.activeFormat.isVideoHDRSupported else { return }
        do {
            try device.lockForConfiguration()
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = enabled
            device.unlockForConfiguration()
        } catch {
            message = "Could not change HDR."
        }
    }

    func selectCodec(_ codec: Codec) {
        self.codec = codec
    }

    func selectStabilization(_ mode: Stabilization) {
        stabilization = mode
        applyStabilization(mode)
    }

    private func applyStabilization(_ mode: Stabilization) {
        guard let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported else {
            return
        }
        connection.preferredVideoStabilizationMode = mode.mode
    }

    // MARK: - Zoom, focus, exposure, torch

    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        guard let device else { return }
        let target = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: target, withRate: 8)
            } else {
                device.videoZoomFactor = target
            }
            device.unlockForConfiguration()
            zoomFactor = target
        } catch {
            message = "Could not zoom."
        }
    }

    /// Tap to focus and expose at a point in device coordinates (0...1, from the preview layer).
    func focus(at point: CGPoint) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            focusLocked = false
            exposureLocked = false
        } catch {
            message = "Could not focus."
        }
    }

    func setFocusLocked(_ locked: Bool) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if locked, device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
            focusLocked = locked
        } catch {
            message = "Could not lock focus."
        }
    }

    func setExposureLocked(_ locked: Bool) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if locked, device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            } else if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            exposureLocked = locked
        } catch {
            message = "Could not lock exposure."
        }
    }

    func setWhiteBalanceLocked(_ locked: Bool) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if locked, device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
            whiteBalanceLocked = locked
        } catch {
            message = "Could not lock white balance."
        }
    }

    func setExposureBias(_ bias: Float) {
        guard let device else { return }
        let clamped = min(max(bias, exposureRange.lowerBound), exposureRange.upperBound)
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
            exposureBias = clamped
        } catch {
            message = "Could not change exposure."
        }
    }

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            message = "Could not change the torch."
        }
    }

    // MARK: - Orientation

    /// Rotation angle for a device orientation, following AVCaptureConnection's convention. nil for flat or unknown.
    /// The two landscape angles are swapped relative to the device orientation names: with 0 and 180 the image
    /// came out upside down in landscape.
    static func rotationAngle(for orientation: UIDeviceOrientation) -> CGFloat? {
        switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 180
        case .landscapeRight: 0
        default: nil
        }
    }

    /// Keeps the recording upright.
    func updateOrientation(_ orientation: UIDeviceOrientation) {
        guard let angle = Self.rotationAngle(for: orientation) else { return }
        if let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard status == .running, !movieOutput.isRecording, let connection = movieOutput.connection(with: .video) else {
            return
        }
        if movieOutput.availableVideoCodecTypes.contains(codec.videoType) {
            movieOutput.setOutputSettings([AVVideoCodecKey: codec.videoType], for: connection)
        }
        applyStabilization(stabilization)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sightline-\(UUID().uuidString).mov")
        let delegate = MovieDelegate { [weak self] url, error in
            Task { @MainActor in self?.recordingFinished(url, error: error) }
        }
        movieDelegate = delegate
        movieOutput.startRecording(to: url, recordingDelegate: delegate)

        isRecording = true
        recordedSeconds = 0
        recordingStart = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStart else { return }
                self.recordedSeconds = Int(Date().timeIntervalSince(start))
                if self.recordedSeconds >= FreeTier.maxRecordSeconds, !self.isProUnlocked() {
                    self.stopRecording()
                    self.message = "Free recordings stop after \(FreeTier.maxRecordSeconds / 60) minutes. Sightline Pro removes the limit."
                    self.onRecordingLimit?()
                }
            }
        }
    }

    private func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func recordingFinished(_ url: URL, error: Error?) {
        isRecording = false
        recordingStart = nil
        if let error {
            let nsError = error as NSError
            let finished = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
            guard finished else {
                message = "Recording failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: url)
                return
            }
        }
        saveVideo(url)
    }

    private func saveVideo(_ url: URL) {
        Task {
            let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard access == .authorized || access == .limited else {
                message = "Allow Photos access to save recordings."
                try? FileManager.default.removeItem(at: url)
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                message = "Saved to Photos."
            } catch {
                message = "Could not save the video."
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Delegates

/// Forwards the end of a movie recording. AVFoundation holds the delegate weakly, so the engine keeps it.
private final class MovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let finished: @Sendable (URL, Error?) -> Void

    init(finished: @escaping @Sendable (URL, Error?) -> Void) {
        self.finished = finished
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        finished(outputFileURL, error)
    }
}

/// Converts each microphone sample buffer to PCM for the speech recognizer. Runs on the audio queue.
private final class AudioSampleDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let deliver: @Sendable (AVAudioPCMBuffer) -> Void

    init(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.deliver = deliver
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        deliver(buffer)
    }

    private static func pcmBuffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let scale = pow(10, CGFloat(places))
        return (self * scale).rounded() / scale
    }
}

/// Receives the faces the capture session detects.
private final class FaceDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let handler: ([AVMetadataObject]) -> Void

    init(handler: @escaping ([AVMetadataObject]) -> Void) {
        self.handler = handler
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        handler(metadataObjects.filter { $0.type == .face })
    }
}
