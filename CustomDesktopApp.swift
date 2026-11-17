import SwiftUI
import Combine

class DesktopState: ObservableObject {
    @Published var cursorPosition: CGPoint = CGPoint(x: 400, y: 300)
    @Published var scrollDelta: CGPoint = .zero
    @Published var zoomScale: CGFloat = 1.0
    @Published var clickTrigger: Bool = false
    @Published var currentURL: String = "https://www.apple.com"
    
    // Screen bounds for external display (defaults to 1080p)
    var desktopSize: CGSize = CGSize(width: 1920, height: 1080)
    
    func moveCursor(dx: CGFloat, dy: CGFloat) {
        let newX = min(max(cursorPosition.x + dx * 1.5, 0), desktopSize.width)
        let newY = min(max(cursorPosition.y + dy * 1.5, 0), desktopSize.height)
        cursorPosition = CGPoint(x: newX, y: newY)
    }
    
    func triggerScroll(dx: CGFloat, dy: CGFloat) {
        scrollDelta = CGPoint(x: dx, y: dy)
    }
    
    func triggerClick() {
        clickTrigger.toggle()
    }
}

@main
struct CustomDesktopApp: App {
    @StateObject private var desktopState = DesktopState()
    @State private var externalWindow: UIWindow?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(desktopState)
                .onReceive(NotificationCenter.default.publisher(for: UIScene.willConnectNotification)) { notification in
                    guard let windowScene = notification.object as? UIWindowScene,
                          windowScene.session.role == .windowExternalDisplayNonInteractive else { return }
                    
                    let window = UIWindow(windowScene: windowScene)
                    desktopState.desktopSize = windowScene.screen.bounds.size
                    let rootView = ExternalDesktopView().environmentObject(desktopState)
                    window.rootViewController = UIHostingController(rootView: rootView)
                    window.isHidden = false
                    self.externalWindow = window
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { notification in
                    guard let windowScene = notification.object as? UIWindowScene,
                          windowScene.session.role == .windowExternalDisplayNonInteractive else { return }
                    self.externalWindow = nil
                }
        }
    }
}
