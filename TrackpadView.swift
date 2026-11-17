import SwiftUI
import UIKit

struct TrackpadView: UIViewRepresentable {
    var onMove: (CGFloat, CGFloat) -> Void
    var onPinchDragScroll: (CGFloat, CGFloat) -> Void
    var onTapClick: () -> Void
    var onGestureEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemBackground
        view.layer.cornerRadius = 24
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.cgColor

        // 1. Single-finger pan for cursor movement
        let cursorPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleCursorPan(_:)))
        cursorPan.minimumNumberOfTouches = 1
        cursorPan.maximumNumberOfTouches = 1

        // 2. Tap for left click
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))

        // 3. Pinch recognizer to engage scroll lock
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))

        // 4. Two-finger drag for scrolling while pinched
        let scrollPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScrollPan(_:)))
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2

        pinchGesture.delegate = context.coordinator
        scrollPan.delegate = context.coordinator

        view.addGestureRecognizer(cursorPan)
        view.addGestureRecognizer(tapGesture)
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(scrollPan)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TrackpadView
        private var isPinchEngaged = false

        init(_ parent: TrackpadView) {
            self.parent = parent
        }

        // Allow pinch and 2-finger pan to work simultaneously
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        @objc func handleCursorPan(_ gesture: UIPanGestureRecognizer) {
            guard !isPinchEngaged else { return }
            let translation = gesture.translation(in: gesture.view)
            parent.onMove(translation.x, translation.y)
            gesture.setTranslation(.zero, in: gesture.view)
            
            if gesture.state == .ended || gesture.state == .cancelled {
                parent.onGestureEnd()
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onTapClick()
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed {
                // Engage scroll mode as soon as fingers pinch slightly
                if abs(gesture.scale - 1.0) > 0.04 {
                    isPinchEngaged = true
                }
            } else if gesture.state == .ended || gesture.state == .cancelled {
                isPinchEngaged = false
                parent.onGestureEnd()
            }
        }

        @objc func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
            guard isPinchEngaged else { return }
            
            if gesture.state == .changed {
                let translation = gesture.translation(in: gesture.view)
                // Invert Y for natural iOS-style scrolling
                parent.onPinchDragScroll(-translation.x * 2.0, -translation.y * 2.0)
                gesture.setTranslation(.zero, in: gesture.view)
            } else if gesture.state == .ended || gesture.state == .cancelled {
                isPinchEngaged = false
                parent.onGestureEnd()
            }
        }
    }
}
