import SwiftUI

struct ContentView: View {
    @EnvironmentObject var capture: CaptureManager
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PreviewView(session: capture.session, isHovering: $isHovering)
                .ignoresSafeArea()

            if !capture.isDeviceConnected {
                disconnectedView
            }

            if capture.showFlash {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                OverlayView()
                    .padding(.bottom, 12)
            }
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .frame(minWidth: 320, minHeight: 180)
    }

    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if let name = capture.selectedDeviceName {
                Text("Waiting for \(name)...")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else if capture.availableDevices.isEmpty {
                Text("No capture device detected")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a capture device")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if !capture.availableDevices.isEmpty {
                Menu("Select Device") {
                    ForEach(capture.availableDevices, id: \.uniqueID) { device in
                        Button(device.localizedName) {
                            capture.selectDevice(device)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
