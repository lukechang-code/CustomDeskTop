import SwiftUI

@main
struct PXSDesktopCloneApp: App {
    @StateObject private var desktopState = DesktopState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(desktopState)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                desktopState.saveWorkspace()
            }
        }
    }
}
