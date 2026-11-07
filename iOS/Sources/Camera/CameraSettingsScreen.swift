import SwiftUI

/// Camera controls that do not fit on the prompter's control row: video format, codec, color, HDR,
/// stabilization, exposure, locks, torch. Only options the current camera supports are shown.
struct CameraSettingsScreen: View {
    @ObservedObject var camera: CameraEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                videoSection
                exposureSection
                lightSection
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var videoSection: some View {
        Section {
            Picker("Aspect ratio", selection: aspectBinding) {
                ForEach(camera.aspects) { shape in
                    Text(shape.name).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            Picker("Resolution and frame rate", selection: modeBinding) {
                ForEach(camera.videoModes) { mode in
                    Text(mode.label).tag(Optional(mode))
                }
            }
            Picker("Codec", selection: codecBinding) {
                ForEach(camera.codecs) { codec in
                    Text(codec.name).tag(codec)
                }
            }
            Picker("Color", selection: colorBinding) {
                ForEach(camera.colorModes) { mode in
                    Text(mode.name).tag(mode)
                }
            }
            if camera.hdrSupported {
                Toggle("HDR video", isOn: hdrBinding)
            }
            Picker("Stabilization", selection: stabilizationBinding) {
                ForEach(camera.stabilizationModes) { mode in
                    Text(mode.name).tag(mode)
                }
            }
        } header: {
            Label("Video", systemImage: "video")
        } footer: {
            Text("Options follow what the selected camera and format support. ProRes and Apple Log need a compatible iPhone and format.")
        }
    }

    private var exposureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Exposure") {
                    Text(String(format: "%+.1f EV", camera.exposureBias))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: exposureBinding, in: camera.exposureRange)
            }
            Toggle("Lock focus", isOn: focusLockBinding)
            Toggle("Lock exposure", isOn: exposureLockBinding)
            Toggle("Lock white balance", isOn: whiteBalanceLockBinding)
        } header: {
            Label("Exposure and focus", systemImage: "sun.max")
        } footer: {
            Text("Tap the preview to focus and expose at a point. Pinch to zoom.")
        }
    }

    @ViewBuilder
    private var lightSection: some View {
        if camera.torchAvailable {
            Section {
                Toggle("Torch", isOn: torchBinding)
            } header: {
                Label("Light", systemImage: "flashlight.on.fill")
            }
        }
    }

    // MARK: - Bindings

    private var aspectBinding: Binding<CameraEngine.AspectRatio> {
        Binding(get: { camera.aspect }, set: { camera.selectAspect($0) })
    }

    private var modeBinding: Binding<CameraEngine.VideoMode?> {
        Binding(
            get: { camera.selectedMode },
            set: { mode in
                if let mode { camera.selectMode(mode) }
            }
        )
    }

    private var codecBinding: Binding<CameraEngine.Codec> {
        Binding(get: { camera.codec }, set: { camera.selectCodec($0) })
    }

    private var colorBinding: Binding<CameraEngine.ColorMode> {
        Binding(get: { camera.colorMode }, set: { camera.selectColorMode($0) })
    }

    private var hdrBinding: Binding<Bool> {
        Binding(get: { camera.hdrEnabled }, set: { camera.setHDR($0) })
    }

    private var stabilizationBinding: Binding<CameraEngine.Stabilization> {
        Binding(get: { camera.stabilization }, set: { camera.selectStabilization($0) })
    }

    private var exposureBinding: Binding<Float> {
        Binding(get: { camera.exposureBias }, set: { camera.setExposureBias($0) })
    }

    private var focusLockBinding: Binding<Bool> {
        Binding(get: { camera.focusLocked }, set: { camera.setFocusLocked($0) })
    }

    private var exposureLockBinding: Binding<Bool> {
        Binding(get: { camera.exposureLocked }, set: { camera.setExposureLocked($0) })
    }

    private var whiteBalanceLockBinding: Binding<Bool> {
        Binding(get: { camera.whiteBalanceLocked }, set: { camera.setWhiteBalanceLocked($0) })
    }

    private var torchBinding: Binding<Bool> {
        Binding(get: { camera.torchOn }, set: { camera.setTorch($0) })
    }


}
