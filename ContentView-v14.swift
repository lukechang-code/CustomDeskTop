import SwiftUI
import WebKit
import UIKit

// MARK: - Models & Persistence

enum DesktopAppType: String, Codable, CaseIterable, Identifiable {
    case browser = "Browser"
    case youtube = "YouTube"
    case netflix = "Netflix"
    case tidal = "Tidal Music"
    case notes = "Notes"
    case files = "Files"
    case terminal = "Terminal"

    var id: String { rawValue }

    var isWebApp: Bool {
        switch self {
        case .browser, .youtube, .netflix, .tidal:
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
        case .tidal: return "https://tidal.com"
        default: return ""
        }
    }

    var iconName: String {
        switch self {
        case .browser: return "safari.fill"
        case .youtube: return "play.rectangle.fill"
        case .netflix: return "n.square.fill"
        case .tidal: return "music.note.list"
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
        case .tidal: return Color(red: 0.0, green: 0.85, blue: 0.85)
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

enum WindowResizeCorner: CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }
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
    var zoomScale: CGFloat = 1.0
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

    var topMostWindowID: UUID? {
        windows
            .filter { !$0.isMinimized }
            .max(by: { $0.zIndex < $1.zIndex })?
            .id
    }

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

    func openOrFocusTidal(url: String = "https://tidal.com") {
        if let existingIndex = windows.firstIndex(where: { $0.appType == .tidal }) {
            let id = windows[existingIndex].id
            windows[existingIndex].urlString = url
            bringToFront(id)
            if let parsed = URL(string: url) {
                webViewStore[id]?.load(URLRequest(url: parsed))
            }
        } else {
            openApp(.tidal)
            if let newWindow = windows.last, newWindow.appType == .tidal, url != DesktopAppType.tidal.defaultURL {
                if let idx = windows.firstIndex(where: { $0.id == newWindow.id }) {
                    windows[idx].urlString = url
                    saveWorkspace()
                }
            }
        }
    }

    func bringToFront(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        topZIndex += 1
        windows[index].zIndex = topZIndex
        windows[index].isMinimized = false
        saveWorkspace()
    }

    // MARK: - Window Corner Resize

    func applyCornerResize(
        id: UUID,
        corner: WindowResizeCorner,
        initialFrame: CGRect,
        translation: CGSize,
        desktopSize: CGSize
    ) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }

        let minWidth: CGFloat = 240
        let minHeight: CGFloat = 170
        let topLimit: CGFloat = 34
        let bottomLimit: CGFloat = desktopSize.height - 64

        var minX = initialFrame.minX
        var maxX = initialFrame.maxX
        var minY = initialFrame.minY
        var maxY = initialFrame.maxY

        switch corner {
        case .topLeft:
            minX = min(max(8, initialFrame.minX + translation.width), maxX - minWidth)
            minY = min(max(topLimit, initialFrame.minY + translation.height), maxY - minHeight)
        case .topRight:
            maxX = max(min(desktopSize.width - 8, initialFrame.maxX + translation.width), minX + minWidth)
            minY = min(max(topLimit, initialFrame.minY + translation.height), maxY - minHeight)
        case .bottomLeft:
            minX = min(max(8, initialFrame.minX + translation.width), maxX - minWidth)
            maxY = max(min(bottomLimit, initialFrame.maxY + translation.height), minY + minHeight)
        case .bottomRight:
            maxX = max(min(desktopSize.width - 8, initialFrame.maxX + translation.width), minX + minWidth)
            maxY = max(min(bottomLimit, initialFrame.maxY + translation.height), minY + minHeight)
        }

        let newRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        windows[index].posX = newRect.midX
        windows[index].posY = newRect.midY
        windows[index].width = newRect.width
        windows[index].height = newRect.height
        windows[index].isMaximized = false
    }

    func resetWindowSize(_ id: UUID, desktopSize: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let isWeb = windows[index].appType.isWebApp
        windows[index].width = isWeb ? min(560, desktopSize.width * 0.60) : min(360, desktopSize.width * 0.40)
        windows[index].height = isWeb ? min(320, desktopSize.height * 0.74) : min(260, desktopSize.height * 0.62)
        windows[index].isMaximized = false
        saveWorkspace()
    }

    // MARK: - Batch Operations for All Windows

    func minimizeAllWindows() {
        for index in windows.indices {
            windows[index].isMinimized = true
        }
        saveWorkspace()
    }

    func restoreAllWindows() {
        for index in windows.indices {
            windows[index].isMinimized = false
        }
        saveWorkspace()
    }

    func maximizeAllWindows(desktopSize: CGSize) {
        let topMenuInset: CGFloat = 34
        let dockInset: CGFloat = 68
        let usableHeight = max(200, desktopSize.height - topMenuInset - dockInset)

        for index in windows.indices {
            if !windows[index].isMaximized {
                windows[index].preMaximizeFrame = CGRect(
                    x: windows[index].posX - windows[index].width / 2,
                    y: windows[index].posY - windows[index].height / 2,
                    width: windows[index].width,
                    height: windows[index].height
                )
            }
            windows[index].isMinimized = false
            windows[index].isMaximized = true
            windows[index].posX = desktopSize.width / 2
            windows[index].posY = topMenuInset + (usableHeight / 2)
            windows[index].width = desktopSize.width - 16
            windows[index].height = usableHeight
        }
        saveWorkspace()
    }

    func unmaximizeAllWindows() {
        for index in windows.indices where windows[index].isMaximized {
            if let prev = windows[index].preMaximizeFrame {
                windows[index].posX = prev.midX
                windows[index].posY = prev.midY
                windows[index].width = prev.width
                windows[index].height = prev.height
            }
            windows[index].isMaximized = false
        }
        saveWorkspace()
    }

    func cascadeAllWindows(desktopSize: CGSize) {
        let visibleIndices = windows.indices.filter { !windows[$0].isMinimized }
        guard !visibleIndices.isEmpty else { return }

        let baseWidth = min(520, desktopSize.width * 0.55)
        let baseHeight = min(320, desktopSize.height * 0.65)
        let startX = desktopSize.width * 0.35
        let startY = desktopSize.height * 0.42
        let step: CGFloat = 26

        for (offsetIndex, winIndex) in visibleIndices.enumerated() {
            topZIndex += 1
            let shift = CGFloat(offsetIndex % 6) * step
            windows[winIndex].isMaximized = false
            windows[winIndex].width = baseWidth
            windows[winIndex].height = baseHeight
            windows[winIndex].posX = startX + shift
            windows[winIndex].posY = startY + shift
            windows[winIndex].zIndex = topZIndex
        }
        saveWorkspace()
    }

    func tileAllWindows(desktopSize: CGSize) {
        let visibleIndices = windows.indices.filter { !windows[$0].isMinimized }
        let count = visibleIndices.count
        guard count > 0 else { return }

        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let padding: CGFloat = 12
        let topMenuInset: CGFloat = 36
        let dockInset: CGFloat = 68

        let usableWidth = desktopSize.width - (padding * CGFloat(columns + 1))
        let usableHeight = desktopSize.height - topMenuInset - dockInset - (padding * CGFloat(rows + 1))
        let cellWidth = usableWidth / CGFloat(columns)
        let cellHeight = usableHeight / CGFloat(rows)

        for (i, winIndex) in visibleIndices.enumerated() {
            let row = i / columns
            let col = i % columns

            windows[winIndex].isMaximized = false
            windows[winIndex].width = cellWidth
            windows[winIndex].height = cellHeight
            windows[winIndex].posX = padding + (cellWidth / 2) + CGFloat(col) * (cellWidth + padding)
            windows[winIndex].posY = topMenuInset + padding + (cellHeight / 2) + CGFloat(row) * (cellHeight + padding)
        }
        saveWorkspace()
    }

    // MARK: - Virtual Trackpad Input Routing

    func windowAt(point: CGPoint) -> PersistedWindow? {
        windows
            .filter { !$0.isMinimized }
            .sorted(by: { $0.zIndex > $1.zIndex })
            .first { win in
                let rect = CGRect(
                    x: win.posX - win.width / 2,
                    y: win.posY - win.height / 2,
                    width: win.width,
                    height: win.height
                )
                return rect.contains(point)
            }
    }

    func handleTrackpadClick(at point: CGPoint) {
        clickPulsePoint = point
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if self?.clickPulsePoint == point {
                self?.clickPulsePoint = nil
            }
        }

        if contextMenu.isPresented {
            contextMenu.isPresented = false
            return
        }

        guard let target = windowAt(point: point) else { return }
        bringToFront(target.id)

        if target.appType.isWebApp, let webView = webViewStore[target.id] {
            let titleBarHeight: CGFloat = 66
            let winLeft = target.posX - target.width / 2
            let winTop = target.posY - target.height / 2
            let localX = point.x - winLeft
            let localY = point.y - winTop - titleBarHeight

            if localY > 0 {
                let js = """
                (function() {
                    var el = document.elementFromPoint(\(localX), \(localY));
                    if (el) {
                        el.focus();
                        el.click();
                    }
                })();
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    func handleTrackpadTwoFingerScroll(deltaX: CGFloat, deltaY: CGFloat) {
        let target = windowAt(point: cursorPosition) ?? windows.first(where: { $0.id == topMostWindowID })
        guard let win = target else { return }

        if win.appType.isWebApp, let webView = webViewStore[win.id] {
            let scrollView = webView.scrollView
            let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

            let nextX = min(max(0, scrollView.contentOffset.x - deltaX * 1.4), maxOffsetX)
            let nextY = min(max(0, scrollView.contentOffset.y - deltaY * 1.4), maxOffsetY)
            scrollView.setContentOffset(CGPoint(x: nextX, y: nextY), animated: false)
        }
    }

    func handleTrackpadPinch(scale: CGFloat) {
        let target = windowAt(point: cursorPosition) ?? windows.first(where: { $0.id == topMostWindowID })
        guard let win = target, let index = windows.firstIndex(where: { $0.id == win.id }) else { return }

        let clamped = min(max(windows[index].zoomScale * scale, 0.5), 3.0)
        windows[index].zoomScale = clamped

        if win.appType.isWebApp, let webView = webViewStore[win.id] {
            webView.pageZoom = clamped
        }
    }

    func resetZoomForAllWindows() {
        for index in windows.indices {
            windows[index].zoomScale = 1.0
            let id = windows[index].id
            webViewStore[id]?.pageZoom = 1.0
        }
        saveWorkspace()
    }
}
