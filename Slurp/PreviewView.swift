import SwiftUI
import AVFoundation

struct PreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView(session: session)
        let coordinator = context.coordinator
        view.onHoverChanged = { hovering in
            coordinator.hoverChanged(hovering)
        }
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: PreviewView

        init(parent: PreviewView) {
            self.parent = parent
        }

        func hoverChanged(_ hovering: Bool) {
            DispatchQueue.main.async {
                self.parent.isHovering = hovering
            }
        }
    }
}

final class PreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    var onHoverChanged: ((Bool) -> Void)?
    private var idleTimer: Timer?
    private var currentTrackingArea: NSTrackingArea?
    private var windowConfigured = false
    private var fullScreenObserver: NSObjectProtocol?

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !windowConfigured else { return }
        windowConfigured = true

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: 320, height: 180)

        setTrafficLights(visible: false, animated: false)

        fullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.setTrafficLights(visible: false, animated: false)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = currentTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        currentTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        setTrafficLights(visible: true)
        resetIdleTimer()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        setTrafficLights(visible: false)
        idleTimer?.invalidate()
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverChanged?(true)
        setTrafficLights(visible: true)
        resetIdleTimer()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.onHoverChanged?(false)
            self?.setTrafficLights(visible: false)
        }
    }

    private func setTrafficLights(visible: Bool, animated: Bool = true) {
        guard let window else { return }
        guard let container = window.standardWindowButton(.closeButton)?.superview else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                container.animator().alphaValue = visible ? 1 : 0
            }
        } else {
            container.alphaValue = visible ? 1 : 0
        }
    }

    deinit {
        if let observer = fullScreenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
