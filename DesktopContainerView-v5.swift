import SwiftUI

/// Wraps your existing ContentView without overwriting it, adding:
/// 1. Front-camera hand tracking (index fingertip -> cursorPosition)
/// 2. Visual pinch/drag indicator ring around cursorPosition
/// 3. Floating Hand Control status & toggle pill
/// 4. Built-in display scaling across iPhone and external monitors
struct DesktopContainerView: View {
    @EnvironmentObject var desktopState: DesktopState
    @StateObject private var handTracker = HandTrackingManager()
    @State private var lastKnownDesktopSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Your existing desktop UI (wallpaper, windows, dock, trackpad, cursor)
                ContentView()

                // Live pinch / drag feedback ring around the cursor when hand control is active
                if handTracker.isEnabled && handTracker.isHandDetected {
                    Circle()
                        .strokeBorder(
                            handTracker.isDraggingByPinch ? Color.orange : (handTracker.isPinching ? Color.green : Color.white.opacity(0.75)),
                            lineWidth: handTracker.isPinching ? 3.5 : 2.0
                        )
                        .background(
                            Circle()
                                .fill(handTracker.isPinching ? Color.green.opacity(0.22) : Color.clear)
                        )
                        .frame(
                            width: handTracker.isPinching ? 24 : 34,
                            height: handTracker.isPinching ? 24 : 34
                        )
                        .position(desktopState.cursorPosition)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.1), value: handTracker.isPinching)
                }

                // Floating Hand Control toggle & status pill (top-right corner)
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            handTracker.isEnabled.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: statusIcon)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(statusText)
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(statusColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }
            .onAppear {
                handTracker.desktopState = desktopState
                handTracker.screenSize = geo.size
                lastKnownDesktopSize = geo.size
            }
            .onChange(of: geo.size) { newSize in
                handTracker.screenSize = newSize
                desktopState.adaptLayout(from: lastKnownDesktopSize, to: newSize)
                lastKnownDesktopSize = newSize
            }
        }
        .ignoresSafeArea(.all)
    }

    private var statusIcon: String {
        if !handTracker.isEnabled { return "hand.raised" }
        if handTracker.isDraggingByPinch { return "arrow.up.and.down.and.arrow.left.and.right" }
        if handTracker.isPinching { return "hand.pinch.fill" }
        return handTracker.isHandDetected ? "hand.raised.fill" : "camera.viewfinder"
    }

    private var statusText: String {
        if !handTracker.isEnabled { return "Hand Control" }
        if handTracker.isDraggingByPinch { return "Pinch Scrolling" }
        if handTracker.isPinching { return "Pinch Click" }
        return handTracker.isHandDetected ? "Tracking Hand" : "Searching Hand..."
    }

    private var statusColor: Color {
        if !handTracker.isEnabled { return Color.black.opacity(0.65) }
        if handTracker.isDraggingByPinch { return Color.orange.opacity(0.9) }
        if handTracker.isPinching { return Color.blue.opacity(0.9) }
        return handTracker.isHandDetected ? Color.green.opacity(0.88) : Color.secondary.opacity(0.85)
    }
}

// MARK: - Self-Contained Display Scaling Extension
// Included directly here so DesktopContainerView compiles even if DesktopDisplayScaling-Final.swift
// is not added to the target. (Remove DesktopDisplayScaling-Final.swift if Xcode reports a duplicate symbol.)
extension DesktopState {
    func adaptLayout(from oldSize: CGSize, to newSize: CGSize) {
        guard oldSize.width > 0, oldSize.height > 0,
              newSize.width > 0, newSize.height > 0 else { return }

        let scaleX = newSize.width / oldSize.width
        let scaleY = newSize.height / oldSize.height

        for index in windows.indices {
            if windows[index].isMaximized {
                windows[index].posX = newSize.width / 2
                windows[index].posY = newSize.height / 2
                windows[index].width = newSize.width
                windows[index].height = newSize.height
            } else {
                windows[index].posX *= scaleX
                windows[index].posY *= scaleY
                windows[index].width = min(windows[index].width * scaleX, newSize.width * 0.92)
                windows[index].height = min(windows[index].height * scaleY, newSize.height * 0.88)
            }
        }

        cursorPosition = CGPoint(
            x: min(max(cursorPosition.x * scaleX, 0), newSize.width),
            y: min(max(cursorPosition.y * scaleY, 0), newSize.height)
        )
        saveWorkspace()
    }
}
