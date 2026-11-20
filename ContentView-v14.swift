import SwiftUI
import WebKit
import UIKit

// MARK: - Models & Persistence

enum DesktopAppType: String, Codable, CaseIterable, Identifiable {
    case browser = "Browser"
    case youtube = "YouTube"
    case netflix = "Netflix"
    case notes = "Notes"
    case files = "Files"
    case terminal = "Terminal"

    var id: String { rawValue }

    var isWebApp: Bool {
        switch self {
        case .browser, .youtube, .netflix:
            return true
        default:
            return false
        }
    }

    var defaultURL: String {
        switch self {
        case .browser: return "https://apple.com"
        case .youtube: return "https://youtube.com"
        case .netflix: return "https://netflix.com"
        default: return ""
        }
    }

    var iconName: String {
        switch self {
        case .browser: return "safari.fill"
        case .youtube: return "play.rectangle.fill"
        case .netflix: return "n.square.fill"
        case .notes: return "note.text"
        case .files: return "folder.fill"
        case .terminal: return "terminal.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .browser: return .blue
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .netflix: return Color(red: 0.89, green: 0.04, blue: 0.08)
        case .notes: return .yellow
        case .files: return .cyan
        case .terminal: return .green
        }
    }
}

enum WallpaperTheme: String, Codable, CaseIterable, Identifiable {
    case illini = "Illini"
    case illiniSunset = "Illini Alma Mater"
    case midnight = "Midnight"

    var id: String { rawValue }
}

struct PersistedWindow: Codable, Identifiable {
    let id: UUID
    var appType: DesktopAppType
    var title: String
    var urlString: String
    var noteText: String
    var posX: CGFloat
    var posY: CGFloat
    var width: CGFloat
    var height: CGFloat
    var zIndex: Double
    var isMinimized: Bool
    var isMaximized: Bool = false
    var preMaximizeFrame: CGRect? = nil
}

struct SavedWorkspaceSnapshot: Codable {
    var windows: [PersistedWindow]
    var savedAt: Date
}

struct ContextMenuState {
    var isPresented: Bool = false
    var position: CGPoint = .zero
    var targetWindowID: UUID? = nil
}

final class DesktopState: ObservableObject {
    @Published var windows: [PersistedWindow] = []
    @Published var cursorPosition: CGPoint = CGPoint(x: 420, y: 200)
    @Published var isTrackpadActive: Bool = true
    @Published var trackpadPosition: CGPoint? = nil
    @Published var hasClosedWorkspaceBackup: Bool = false
    @Published var clickPulsePoint: CGPoint? = nil
    @Published var contextMenu: ContextMenuState = ContextMenuState()
    @Published var wallpaperTheme: WallpaperTheme = .illini

    private let activeWorkspaceKey = "pxs.desktop.activeWorkspace.v14"
    private let closedWorkspaceKey = "pxs.desktop.closedWorkspaceBackup.v14"
    private let wallpaperKey = "pxs.desktop.wallpaperTheme.v14"
    private var topZIndex: Double = 10

    var webViewStore: [UUID: WKWebView] = [:]

    init() {
        if let rawTheme = UserDefaults.standard.string(forKey: wallpaperKey),
           let savedTheme = WallpaperTheme(rawValue: rawTheme) {
            self.wallpaperTheme = savedTheme
        }
        restoreWorkspaceOnLaunch()
    }

    func setWallpaper(_ theme: WallpaperTheme) {
        wallpaperTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: wallpaperKey)
    }

    func restoreWorkspaceOnLaunch() {
        if let data = UserDefaults.standard.data(forKey: activeWorkspaceKey),
           let decoded = try? JSONDecoder().decode([PersistedWindow].self, from: data),
           !decoded.isEmpty {
            self.windows = decoded
            self.topZIndex = (decoded.map(\.zIndex).max() ?? 10) + 1
        } else {
            loadDefaultWorkspace()
        }
        refreshBackupAvailability()
    }

    func loadDefaultWorkspace() {
        let screen = UIScreen.main.bounds
        let landscapeWidth = max(screen.width, screen.height)
        let landscapeHeight = min(screen.width, screen.height)

        let browserWidth = min(540, landscapeWidth * 0.56)
        let browserHeight = min(310, landscapeHeight * 0.72)
        let notesWidth = min(320, landscapeWidth * 0.34)
        let notesHeight = min(260, landscapeHeight * 0.62)

        windows = [
            PersistedWindow(
                id: UUID(),
                appType: .browser,
                title: "Safari Desktop",
                urlString: "https://apple.com",
                noteText: "",
                posX: landscapeWidth * 0.33,
                posY: landscapeHeight * 0.44,
                width: browserWidth,
                height: browserHeight,
                zIndex: 1,
                isMinimized: false
            ),
            PersistedWindow(
                id: UUID(),
                appType: .notes,
                title: "Scratchpad",
                urlString: "",
                noteText: "Trackpad gestures: 1-finger move, tap to click, 2-finger scroll, 2-finger pinch to zoom, 2-finger tap for menu.",
                posX: landscapeWidth * 0.74,
                posY: landscapeHeight * 0.46,
                width: notesWidth,
                height: notesHeight,
                zIndex: 2,
                isMinimized: false
            )
        ]
        cursorPosition = CGPoint(x: landscapeWidth * 0.5, y: landscapeHeight * 0.5)
        trackpadPosition = nil
        topZIndex = 3
        saveWorkspace()
    }

    func saveWorkspace() {
        if let data = try? JSONEncoder().encode(windows) {
            UserDefaults.standard.set(data, forKey: activeWorkspaceKey)
        }
    }

    func archiveCurrentWorkspaceForReopen() {
        guard !windows.isEmpty else { return }
        let snapshot = SavedWorkspaceSnapshot(windows: windows, savedAt: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: closedWorkspaceKey)
            hasClosedWorkspaceBackup = true
        }
    }

    func closeAllWindows() {
        archiveCurrentWorkspaceForReopen()
        webViewStore.removeAll()
        windows.removeAll()
        saveWorkspace()
    }

    func resetLayout() {
        archiveCurrentWorkspaceForReopen()
        webViewStore.removeAll()
        loadDefaultWorkspace()
    }

    func reopenPreviousWorkspace() {
        guard let data = UserDefaults.standard.data(forKey: closedWorkspaceKey),
              let snapshot = try? JSONDecoder().decode(SavedWorkspaceSnapshot.self, from: data),
              !snapshot.windows.isEmpty else {
            return
        }

        if !windows.isEmpty {
            let currentBackup = SavedWorkspaceSnapshot(windows: windows, savedAt: Date())
            if let currentData = try? JSONEncoder().encode(currentBackup) {
                UserDefaults.standard.set(currentData, forKey: closedWorkspaceKey)
            }
        }

        self.windows = snapshot.windows
        self.topZIndex = (snapshot.windows.map(\.zIndex).max() ?? 10) + 1
        saveWorkspace()
        refreshBackupAvailability()
    }

    func refreshBackupAvailability() {
        if let data = UserDefaults.standard.data(forKey: closedWorkspaceKey),
           let snapshot = try? JSONDecoder().decode(SavedWorkspaceSnapshot.self, from: data) {
            hasClosedWorkspaceBackup = !snapshot.windows.isEmpty
        } else {
            hasClosedWorkspaceBackup = false
        }
    }

    func openApp(_ type: DesktopAppType) {
        topZIndex += 1
        let screen = UIScreen.main.bounds
        let landscapeWidth = max(screen.width, screen.height)
        let landscapeHeight = min(screen.width, screen.height)
        let offset = CGFloat((windows.count % 5) * 22)

        let newWindow = PersistedWindow(
            id: UUID(),
            appType: type,
            title: type.rawValue,
            urlString: type.defaultURL,
            noteText: type == .notes ? "New note..." : "",
            posX: (landscapeWidth * 0.45) + offset,
            posY: (landscapeHeight * 0.44) + offset,
            width: type.isWebApp ? min(560, landscapeWidth * 0.60) : min(360, landscapeWidth * 0.4),
            height: type.isWebApp ? min(320, landscapeHeight * 0.74) : min(260, landscapeHeight * 0.62),
            zIndex: topZIndex,
            isMinimized: false
        )
        windows.append(newWindow)
        saveWorkspace()
    }

    func bringToFront(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        topZIndex += 1
        windows[index].zIndex = topZIndex
        windows[index].isMinimized = false
        saveWorkspace()
    }

    func closeWindow(_ id: UUID) {
        if windows.count == 1 {
            archiveCurrentWorkspaceForReopen()
        }
        webViewStore.removeValue(forKey: id)
        windows.removeAll { $0.id == id }
        saveWorkspace()
    }

    func toggleMinimize(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].isMinimized.toggle()
        saveWorkspace()
    }

    func toggleMaximize(_ id: UUID, desktopSize: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        if windows[index].isMaximized {
            if let prev = windows[index].preMaximizeFrame {
                windows[index].posX = prev.midX
                windows[index].posY = prev.midY
                windows[index].width = prev.width
                windows[index].height = prev.height
            }
            windows[index].isMaximized = false
        } else {
            windows[index].preMaximizeFrame = CGRect(
                x: windows[index].posX - windows[index].width / 2,
                y: windows[index].posY - windows[index].height / 2,
