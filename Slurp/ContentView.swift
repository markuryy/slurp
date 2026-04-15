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

    private var statusMessage: String {
        if let name = capture.selectedDeviceName {
            return "Waiting for \(name)..."
        } else if capture.availableDevices.isEmpty {
            return "No capture device detected"
        } else {
            return "Select a capture device"
        }
    }

    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(statusMessage)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .allowsHitTesting(false)
    }
}
