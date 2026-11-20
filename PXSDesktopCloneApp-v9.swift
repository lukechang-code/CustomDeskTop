import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = FullScreenSceneDelegate.self
        return config
    }
}

final class FullScreenSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }
}

@main
struct PXSDesktopCloneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var desktopState = DesktopState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(desktopState)
                .preferredColorScheme(.dark)
                .ignoresSafeArea(.all)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                desktopState.saveWorkspace()
            }
        }
    }
}
