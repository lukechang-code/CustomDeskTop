import SwiftUI

struct ContentView: View {
    @EnvironmentObject var desktopState: DesktopState
    @State private var urlInput: String = "https://www.apple.com"
    @State private var activeGestureStatus: String = "1-Finger: Move | Pinch + Drag: Scroll"

    var body: some View {
        VStack(spacing: 12) {
            // Top URL & Navigation Bar
            HStack {
                TextField("Enter URL...", text: $urlInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                
                Button("Go") {
                    if !urlInput.hasPrefix("http") {
                        urlInput = "https://" + urlInput
                    }
                    desktopState.currentURL = urlInput
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            // Live Gesture Feedback Pill
            Text(activeGestureStatus)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .cornerRadius(20)

            // Custom Gesture Trackpad
            TrackpadView(
                onMove: { dx, dy in
                    activeGestureStatus = "Moving Cursor"
                    desktopState.moveCursor(dx: dx, dy: dy)
                },
                onPinchDragScroll: { dx, dy in
                    activeGestureStatus = "Pinch + Drag Scrolling"
                    desktopState.triggerScroll(dx: dx, dy: dy)
                },
                onTapClick: {
                    activeGestureStatus = "Left Click"
                    desktopState.triggerClick()
                },
                onGestureEnd: {
                    activeGestureStatus = "1-Finger: Move | Pinch + Drag: Scroll"
                }
            )
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
    }
}
