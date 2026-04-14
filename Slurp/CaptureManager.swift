@preconcurrency import AVFoundation
import AppKit

final class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CMSampleBuffer?

    var latestBuffer: CMSampleBuffer? {
        lock.withLock { buffer }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.withLock { buffer = sampleBuffer }
    }
}

@MainActor
final class CaptureManager: ObservableObject {
    let session = AVCaptureSession()
    let audioPreviewOutput = AVCaptureAudioPreviewOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    let frameGrabber = FrameGrabber()
    private let sessionQueue = DispatchQueue(label: "com.slurp.session")

    @Published var isDeviceConnected = false
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var availableAudioDevices: [AVCaptureDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var selectedDeviceName: String?
    @Published private(set) var selectedAudioDeviceID: String?
    @Published private(set) var selectedAudioDeviceName: String?
    @Published var volume: Float = 1.0 {
        didSet { audioPreviewOutput.volume = volume }
    }
    @Published var showFlash = false

    private static let deviceIDKey = "SlurpDeviceID"
    private static let deviceNameKey = "SlurpDeviceName"
    private static let audioDeviceIDKey = "SlurpAudioDeviceID"
    private static let audioDeviceNameKey = "SlurpAudioDeviceName"

    init() {
        audioPreviewOutput.volume = volume
        audioPreviewOutput.outputDeviceUniqueID = nil

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(frameGrabber, queue: DispatchQueue(label: "com.slurp.frame"))

        selectedDeviceID = UserDefaults.standard.string(forKey: Self.deviceIDKey)
        selectedDeviceName = UserDefaults.standard.string(forKey: Self.deviceNameKey)
        selectedAudioDeviceID = UserDefaults.standard.string(forKey: Self.audioDeviceIDKey)
        selectedAudioDeviceName = UserDefaults.standard.string(forKey: Self.audioDeviceNameKey)

        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
                if self?.isDeviceConnected == false {
                    self?.connectToDevice()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshDevices()
                if let id = self.selectedDeviceID,
                   !self.availableDevices.contains(where: { $0.uniqueID == id }) {
                    self.teardownSession()
                }
            }
        }

        Task {
            await AVCaptureDevice.requestAccess(for: .video)
            await AVCaptureDevice.requestAccess(for: .audio)
            refreshDevices()
            connectToDevice()
        }
    }

    func refreshDevices() {
        availableDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices

        availableAudioDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func resolveAudioDevice(for videoDevice: AVCaptureDevice) -> AVCaptureDevice? {
        // If user explicitly picked an audio device, use it
        if let id = selectedAudioDeviceID,
           let device = availableAudioDevices.first(where: { $0.uniqueID == id }) {
            return device
        }
        // Auto-match: try modelID, then manufacturer, then name substring
        return availableAudioDevices.first { $0.modelID == videoDevice.modelID }
            ?? availableAudioDevices.first { $0.manufacturer == videoDevice.manufacturer && $0.manufacturer != "Apple Inc." }
            ?? availableAudioDevices.first { $0.localizedName.contains(videoDevice.localizedName) || videoDevice.localizedName.contains($0.localizedName) }
    }

    func connectToDevice() {
        let target: AVCaptureDevice?

        if let id = selectedDeviceID {
            target = availableDevices.first { $0.uniqueID == id }
        } else if availableDevices.count == 1 {
            target = availableDevices.first
        } else {
            target = nil
        }

        guard let videoDevice = target else {
            isDeviceConnected = false
            return
        }

        rememberDevice(videoDevice)
        let audioDevice = resolveAudioDevice(for: videoDevice)
        if let audioDevice {
            rememberAudioDevice(audioDevice)
        }
        setupSession(video: videoDevice, audio: audioDevice)
    }

    func selectDevice(_ device: AVCaptureDevice) {
        teardownSession()
        rememberDevice(device)
        // Clear audio selection so auto-match runs for the new video device
        selectedAudioDeviceID = nil
        selectedAudioDeviceName = nil
        UserDefaults.standard.removeObject(forKey: Self.audioDeviceIDKey)
        UserDefaults.standard.removeObject(forKey: Self.audioDeviceNameKey)
        connectToDevice()
    }

    func selectAudioDevice(_ device: AVCaptureDevice) {
        rememberAudioDevice(device)
        // Reconnect with the new audio device
        if isDeviceConnected {
            teardownSession()
            connectToDevice()
        }
    }

    private func rememberDevice(_ device: AVCaptureDevice) {
        selectedDeviceID = device.uniqueID
        selectedDeviceName = device.localizedName
        UserDefaults.standard.set(device.uniqueID, forKey: Self.deviceIDKey)
        UserDefaults.standard.set(device.localizedName, forKey: Self.deviceNameKey)
    }

    private func rememberAudioDevice(_ device: AVCaptureDevice) {
        selectedAudioDeviceID = device.uniqueID
        selectedAudioDeviceName = device.localizedName
        UserDefaults.standard.set(device.uniqueID, forKey: Self.audioDeviceIDKey)
        UserDefaults.standard.set(device.localizedName, forKey: Self.audioDeviceNameKey)
    }

    private func setupSession(video: AVCaptureDevice, audio: AVCaptureDevice?) {
        let session = self.session
        let audioOutput = self.audioPreviewOutput
        let videoOutput = self.videoDataOutput

        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            session.sessionPreset = .high

            if let input = try? AVCaptureDeviceInput(device: video),
               session.canAddInput(input) {
                session.addInput(input)
            }
            if let audio,
               let input = try? AVCaptureDeviceInput(device: audio),
               session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            session.startRunning()

            Task { @MainActor [weak self] in
                self?.isDeviceConnected = true
            }
        }
    }

    private func teardownSession() {
        isDeviceConnected = false
        let session = self.session
        sessionQueue.async {
            session.stopRunning()
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
        }
    }

    func takeScreenshot() {
        guard let buffer = frameGrabber.latestBuffer,
              let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let name = "Slurp \(formatter.string(from: Date())).png"

        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        try? png.write(to: desktop.appendingPathComponent(name))

        showFlash = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            showFlash = false
        }
    }
}
