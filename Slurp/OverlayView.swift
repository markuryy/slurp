import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var capture: CaptureManager

    var body: some View {
        HStack(spacing: 12) {
            if !capture.availableDevices.isEmpty || !capture.availableAudioDevices.isEmpty {
                devicePicker
                Divider().frame(height: 16)
            }

            Image(systemName: volumeIcon)
                .font(.system(size: 13))
                .frame(width: 16)
                .foregroundStyle(.secondary)

            Slider(value: $capture.volume, in: 0...1)
                .controlSize(.small)
                .frame(width: 100)

            Divider().frame(height: 16)

            Button {
                capture.takeScreenshot()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var devicePicker: some View {
        Menu {
            Section("Video") {
                ForEach(capture.availableDevices, id: \.uniqueID) { device in
                    Toggle(device.localizedName, isOn: Binding(
                        get: { device.uniqueID == capture.selectedDeviceID },
                        set: { if $0 { capture.selectDevice(device) } }
                    ))
                }
            }
            Section("Audio") {
                ForEach(capture.availableAudioDevices, id: \.uniqueID) { device in
                    Toggle(device.localizedName, isOn: Binding(
                        get: { device.uniqueID == capture.selectedAudioDeviceID },
                        set: { if $0 { capture.selectAudioDevice(device) } }
                    ))
                }
            }
        } label: {
            Image(systemName: "video")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var volumeIcon: String {
        if capture.volume == 0 { return "speaker.slash" }
        if capture.volume < 0.33 { return "speaker.wave.1" }
        if capture.volume < 0.66 { return "speaker.wave.2" }
        return "speaker.wave.3"
    }
}
