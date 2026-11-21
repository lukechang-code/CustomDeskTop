import AVFoundation
import Vision
import SwiftUI

final class HandTrackingManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isEnabled: Bool = false {
        didSet {
            isEnabled ? startSession() : stopSession()
        }
    }
    @Published var isHandDetected: Bool = false
    @Published var isPinching: Bool = false
    @Published var isDragging: Bool = false
    @Published var isDraggingByPinch: Bool = false

    weak var desktopState: DesktopState?
    var screenSize: CGSize = .zero

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.pxs.handtracking.queue", qos: .userInteractive)
    private let handPoseRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()

    private var smoothedPoint: CGPoint?
    private let smoothingFactor: CGFloat = 0.28

    private var wasPinching: Bool = false
    private var pinchStartPoint: CGPoint?
    private var lastDragPoint: CGPoint?
    private var activeDragWindowID: UUID?
    private var isDraggingWindowTitleBar: Bool = false
    private let dragThreshold: CGFloat = 8.0

    override init() {
        super.init()
        setupCamera()
    }

    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480

        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        captureSession.commitConfiguration()
    }

    func startSession() {
        processingQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    func stopSession() {
        processingQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isHandDetected = false
                self.isPinching = false
                self.isDragging = false
                self.isDraggingByPinch = false
                self.smoothedPoint = nil
                self.resetPinchState()
            }
        }
    }

    private func resetPinchState() {
        wasPinching = false
        pinchStartPoint = nil
        lastDragPoint = nil
        activeDragWindowID = nil
        isDraggingWindowTitleBar = false
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isEnabled, screenSize.width > 0, screenSize.height > 0 else { return }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .upMirrored, options: [:])
        do {
            try handler.perform([handPoseRequest])
            guard let observation = handPoseRequest.results?.first else {
                DispatchQueue.main.async {
                    self.isHandDetected = false
                    self.isPinching = false
                    self.isDragging = false
                    self.isDraggingByPinch = false
                    self.resetPinchState()
                }
                return
            }

            let indexTip = try observation.recognizedPoint(.indexTip)
            let thumbTip = try observation.recognizedPoint(.thumbTip)
            guard indexTip.confidence > 0.45 else {
                DispatchQueue.main.async { self.isHandDetected = false }
                return
            }

            let clampedX = min(max((indexTip.location.x - 0.14) / 0.72, 0), 1)
            let clampedY = min(max(((1.0 - indexTip.location.y) - 0.14) / 0.72, 0), 1)
            let targetPoint = CGPoint(x: clampedX * screenSize.width, y: clampedY * screenSize.height)

            let currentPoint: CGPoint
            if let prev = smoothedPoint {
                currentPoint = CGPoint(
                    x: prev.x + (targetPoint.x - prev.x) * smoothingFactor,
                    y: prev.y + (targetPoint.y - prev.y) * smoothingFactor
                )
            } else {
                currentPoint = targetPoint
            }
            smoothedPoint = currentPoint

            var pinchingNow = wasPinching
            if thumbTip.confidence > 0.45 {
                let dist = hypot(indexTip.location.x - thumbTip.location.x, indexTip.location.y - thumbTip.location.y)
                pinchingNow = wasPinching ? (dist < 0.075) : (dist < 0.052)
            }

            DispatchQueue.main.async { [weak self] in
                self?.processHandFrame(point: currentPoint, pinchingNow: pinchingNow)
            }
        } catch {}
    }

    private func processHandFrame(point: CGPoint, pinchingNow: Bool) {
        guard let desktop = desktopState else { return }
        isHandDetected = true
        isPinching = pinchingNow
        desktop.cursorPosition = point

        if pinchingNow && !wasPinching {
            pinchStartPoint = point
            lastDragPoint = point
            isDragging = false
            isDraggingByPinch = false

            if let target = desktop.topmostWindow(at: point) {
                activeDragWindowID = target.window.id
                isDraggingWindowTitleBar = target.isTitleBar
            } else {
                activeDragWindowID = nil
                isDraggingWindowTitleBar = false
            }
        } else if pinchingNow && wasPinching {
            if let start = pinchStartPoint,
               hypot(point.x - start.x, point.y - start.y) > dragThreshold {
                isDragging = true
                isDraggingByPinch = true
            }

            if isDragging, let last = lastDragPoint {
                let delta = CGSize(width: point.x - last.x, height: point.y - last.y)
                if let winID = activeDragWindowID {
                    if isDraggingWindowTitleBar {
                        desktop.moveWindowByHand(id: winID, delta: delta, desktopSize: screenSize)
                    } else {
                        desktop.scrollWindowByHand(id: winID, delta: delta)
                    }
                }
            }
            lastDragPoint = point
        } else if !pinchingNow && wasPinching {
            if !isDragging {
                desktop.clickPulsePoint = point
                desktop.performHandClick(at: point, desktopSize: screenSize)
            }
            isDragging = false
            isDraggingByPinch = false
            resetPinchState()
        }

        wasPinching = pinchingNow
    }
}
