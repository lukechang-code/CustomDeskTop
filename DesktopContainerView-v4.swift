import SwiftUI

struct DesktopContainerView: View {
    @EnvironmentObject var desktopState: DesktopState
    @StateObject private var handTracker = HandTrackingManager()
    @State private var lastKnownDesktopSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Keeps your existing ContentView intact (wallpaper, windows, dock, trackpad)
                ContentView()
                    .environmentObject(desktopState)

                // Visual pinch-and-drag feedback ring around the cursor
                if handTracker.isEnabled && handTracker.isHandDetected {
                    Circle()
                        .strokeBorder(
                            handTracker.isDragging ? Color.orange : (handTracker.isPinching ? Color.green : Color.cyan.opacity(0.85)),
                            lineWidth: handTracker.isPinching ? 3.5 : 2.0
                        )
                        .background(
                            Circle()
                                .fill((handTracker.isPinching ? Color.green : Color.cyan).opacity(0.18))
                        )
                        .frame(width: handTracker.isPinching ? 24 : 34, height: handTracker.isPinching ? 24 : 34)
                        .position(desktopState.cursorPosition)
                        .animation(.easeOut(duration: 0.12), value: handTracker.isPinching)
                        .allowsHitTesting(false)
                }

                // Floating Hand-Control Status & Toggle Pill
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            handTracker.isEnabled.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: statusIcon)
                                Text(statusLabel)
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(statusColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .padding(.top, 36)
                        .padding(.trailing, 14)
                    }
                    Spacer()
                }
            }
            .onAppear {
                applyDesktopGeometry(geo.size)
            }
            .onChange(of: geo.size) { newSize in
                applyDesktopGeometry(newSize)
            }
        }
        .ignoresSafeArea(.all)
    }

    private func applyDesktopGeometry(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        handTracker.desktopState = desktopState
        handTracker.screenSize = newSize

        if lastKnownDesktopSize != .zero && lastKnownDesktopSize != newSize {
            desktopState.adaptLayout(from: lastKnownDesktopSize, to: newSize)
        }
        lastKnownDesktopSize = newSize
    }

    private var statusIcon: String {
        guard handTracker.isEnabled else { return "hand.raised" }
        if handTracker.isDragging { return "hand.draw.fill" }
        if handTracker.isPinching { return "hand.pinch.fill" }
        return handTracker.isHandDetected ? "hand.raised.fill" : "camera.viewfinder"
    }

    private var statusLabel: String {
        guard handTracker.isEnabled else { return "Hand Control" }
        if handTracker.isDragging { return "Pinch Scrolling" }
        if handTracker.isPinching { return "Pinch" }
        return handTracker.isHandDetected ? "Tracking Hand" : "Show Hand"
    }

    private var statusColor: Color {
        guard handTracker.isEnabled else { return Color.black.opacity(0.65) }
        if handTracker.isDragging { return Color.orange.opacity(0.9) }
        if handTracker.isPinching { return Color.blue.opacity(0.9) }
        return handTracker.isHandDetected ? Color.green.opacity(0.88) : Color.indigo.opacity(0.85)
    }
}