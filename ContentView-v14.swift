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

    var gradientColors: [Color] {
        switch self {
        case .illini:
            return [Color(red: 0.07, green: 0.16, blue: 0.29), Color(red: 0.91, green: 0.29, blue: 0.15)]
        case .illiniSunset:
            return [Color(red: 0.91, green: 0.29, blue: 0.15), Color(red: 0.28, green: 0.12, blue: 0.28), Color(red: 0.07, green: 0.16, blue: 0.29)]
        case .midnight:
            return [Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.12, green: 0.14, blue: 0.22)]
        }
    }
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

    func closeWindow(_ id: UUID) {
        webViewStore.removeValue(forKey: id)
        windows.removeAll { $0.id == id }
        saveWorkspace()
    }

    func toggleMinimize(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].isMinimized.toggle()
        if !windows[index].isMinimized {
            bringToFront(id)
        } else {
            saveWorkspace()
        }
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
            let topMenuInset: CGFloat = 34
            let dockInset: CGFloat = 68
            let usableHeight = max(200, desktopSize.height - topMenuInset - dockInset)
            windows[index].preMaximizeFrame = CGRect(
                x: windows[index].posX - windows[index].width / 2,
                y: windows[index].posY - windows[index].height / 2,
                width: windows[index].width,
                height: windows[index].height
            )
            windows[index].posX = desktopSize.width / 2
            windows[index].posY = topMenuInset + (usableHeight / 2)
            windows[index].width = desktopSize.width - 16
            windows[index].height = usableHeight
            windows[index].isMaximized = true
        }
        bringToFront(id)
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

// MARK: - WebView Wrapper

struct DesktopWebView: UIViewRepresentable {
    let windowID: UUID
    let urlString: String
    @ObservedObject var state: DesktopState

    func makeUIView(context: Context) -> WKWebView {
        if let existing = state.webViewStore[windowID] {
            return existing
        }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        state.webViewStore[windowID] = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url?.absoluteString != urlString, let url = URL(string: urlString), urlString.hasPrefix("http") {
            if uiView.url == nil {
                uiView.load(URLRequest(url: url))
            }
        }
    }
}

// MARK: - Window View

struct DesktopWindowView: View {
    @Binding var window: PersistedWindow
    @ObservedObject var state: DesktopState
    let desktopSize: CGSize

    @State private var dragStartCenter: CGPoint? = nil
    @State private var resizeStartFrame: CGRect? = nil
    @State private var urlInput: String = ""

    private var isFocused: Bool {
        state.topMostWindowID == window.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button { state.closeWindow(window.id) } label: {
                        Circle().fill(Color.red).frame(width: 12, height: 12)
                    }
                    Button { state.toggleMinimize(window.id) } label: {
                        Circle().fill(Color.yellow).frame(width: 12, height: 12)
                    }
                    Button { state.toggleMaximize(window.id, desktopSize: desktopSize) } label: {
                        Circle().fill(Color.green).frame(width: 12, height: 12)
                    }
                }
                .buttonStyle(.plain)

                Image(systemName: window.appType.iconName)
                    .font(.caption)
                    .foregroundColor(window.appType.accentColor)

                Text(window.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isFocused ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartCenter == nil {
                            state.bringToFront(window.id)
                            dragStartCenter = CGPoint(x: window.posX, y: window.posY)
                        }
                        if let start = dragStartCenter {
                            window.posX = min(max(40, start.x + value.translation.width), desktopSize.width - 40)
                            window.posY = min(max(45, start.y + value.translation.height), desktopSize.height - 60)
                            window.isMaximized = false
                        }
                    }
                    .onEnded { _ in
                        dragStartCenter = nil
                        state.saveWorkspace()
                    }
            )

            // Browser URL Bar if Web App
            if window.appType.isWebApp {
                HStack(spacing: 6) {
                    Button {
                        state.webViewStore[window.id]?.goBack()
                    } label: {
                        Image(systemName: "chevron.left").font(.caption)
                    }
                    Button {
                        state.webViewStore[window.id]?.goForward()
                    } label: {
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    Button {
                        state.webViewStore[window.id]?.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }

                    TextField("Enter URL", text: $urlInput, onCommit: {
                        var formatted = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
                            formatted = "https://" + formatted
                        }
                        window.urlString = formatted
                        urlInput = formatted
                        if let parsed = URL(string: formatted) {
                            state.webViewStore[window.id]?.load(URLRequest(url: parsed))
                        }
                        state.saveWorkspace()
                    })
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(6)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 36)
                .background(Color.black.opacity(0.25))
            }

            // App Content
            Group {
                switch window.appType {
                case .browser, .youtube, .netflix, .tidal:
                    DesktopWebView(windowID: window.id, urlString: window.urlString, state: state)
                case .notes:
                    TextEditor(text: $window.noteText)
                        .font(.system(.body, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                        .foregroundColor(.white)
                        .padding(8)
                        .onChange(of: window.noteText) { _ in
                            state.saveWorkspace()
                        }
                case .files:
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Desktop", systemImage: "menubar.dock.rectangle")
                        Label("Documents", systemImage: "doc.text.fill")
                        Label("Downloads", systemImage: "arrow.down.circle.fill")
                        Spacer()
                    }
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(red: 0.11, green: 0.12, blue: 0.15))
                case .terminal:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("pxs@desktop ~ % uname -a")
                        Text("PXS-Desktop Darwin Kernel 24.0.0 arm64")
                            .foregroundColor(.green.opacity(0.8))
                        Text("pxs@desktop ~ % _")
                        Spacer()
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.black.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: window.width, height: window.height)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.94))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.white.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isFocused ? 0.45 : 0.25), radius: isFocused ? 16 : 8, x: 0, y: 8)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .padding(6)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if resizeStartFrame == nil {
                                state.bringToFront(window.id)
                                resizeStartFrame = CGRect(
                                    x: window.posX - window.width / 2,
                                    y: window.posY - window.height / 2,
                                    width: window.width,
                                    height: window.height
                                )
                            }
                            if let initial = resizeStartFrame {
                                state.applyCornerResize(
                                    id: window.id,
                                    corner: .bottomRight,
                                    initialFrame: initial,
                                    translation: value.translation,
                                    desktopSize: desktopSize
                                )
                            }
                        }
                        .onEnded { _ in
                            resizeStartFrame = nil
                            state.saveWorkspace()
                        }
                )
        }
        .position(x: window.posX, y: window.posY)
        .zIndex(window.zIndex)
        .onAppear {
            urlInput = window.urlString
        }
        .onTapGesture {
            state.bringToFront(window.id)
        }
    }
}

// MARK: - Main ContentView

struct ContentView: View {
    @StateObject private var state = DesktopState()

    var body: some View {
        GeometryReader { geo in
            let desktopSize = geo.size

            ZStack {
                // Desktop Wallpaper
                LinearGradient(
                    colors: state.wallpaperTheme.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .onTapGesture {
                    state.contextMenu.isPresented = false
                }

                // Active Windows
                ForEach($state.windows) { $win in
                    if !win.isMinimized {
                        DesktopWindowView(window: $win, state: state, desktopSize: desktopSize)
                    }
                }

                // Top Menu Bar
                VStack {
                    HStack(spacing: 14) {
                        Image(systemName: "desktopcomputer")
                            .font(.caption.bold())

                        Text("PXS Desktop")
                            .font(.caption.bold())

                        Menu("Window") {
                            Button("Tile All") { state.tileAllWindows(desktopSize: desktopSize) }
                            Button("Cascade All") { state.cascadeAllWindows(desktopSize: desktopSize) }
                            Button("Maximize All") { state.maximizeAllWindows(desktopSize: desktopSize) }
                            Button("Unmaximize All") { state.unmaximizeAllWindows() }
                            Divider()
                            Button("Minimize All") { state.minimizeAllWindows() }
                            Button("Restore All") { state.restoreAllWindows() }
                            Button("Close All") { state.closeAllWindows() }
                            if state.hasClosedWorkspaceBackup {
                                Button("Reopen Closed Workspace") { state.reopenPreviousWorkspace() }
                            }
                        }
                        .font(.caption)

                        Menu("Wallpaper") {
                            ForEach(WallpaperTheme.allCases) { theme in
                                Button {
                                    state.setWallpaper(theme)
                                } label: {
                                    HStack {
                                        Text(theme.rawValue)
                                        if state.wallpaperTheme == theme {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        .font(.caption)

                        Spacer()

                        Button {
                            state.isTrackpadActive.toggle()
                        } label: {
                            Image(systemName: state.isTrackpadActive ? "rectangle.and.hand.point.up.left.filled" : "rectangle.and.hand.point.up.left")
                                .font(.caption)
                        }

                        Text(Date(), style: .time)
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(.ultraThinMaterial)

                    Spacer()
                }

                // Virtual Trackpad Overlay (Bottom Right)
                if state.isTrackpadActive {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                                .frame(width: 170, height: 115)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                                .overlay(
                                    Text("Trackpad")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.45))
                                )
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if let last = state.trackpadPosition {
                                                let dx = value.location.x - last.x
                                                let dy = value.location.y - last.y
                                                state.cursorPosition.x = min(max(0, state.cursorPosition.x + dx * 1.8), desktopSize.width)
                                                state.cursorPosition.y = min(max(0, state.cursorPosition.y + dy * 1.8), desktopSize.height)
                                            }
                                            state.trackpadPosition = value.location
                                        }
                                        .onEnded { value in
                                            state.trackpadPosition = nil
                                            if abs(value.translation.width) < 4 && abs(value.translation.height) < 4 {
                                                state.handleTrackpadClick(at: state.cursorPosition)
                                            }
                                        }
                                )
                                .padding(.trailing, 16)
                                .padding(.bottom, 74)
                        }
                    }
                }

                // Bottom Dock
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        ForEach(DesktopAppType.allCases) { app in
                            Button {
                                if let existing = state.windows.first(where: { $0.appType == app }) {
                                    state.bringToFront(existing.id)
                                } else {
                                    state.openApp(app)
                                }
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: app.iconName)
                                        .font(.title3)
                                        .foregroundColor(.white)
                                        .frame(width: 38, height: 38)
                                        .background(app.accentColor.gradient)
                                        .cornerRadius(10)

                                    Circle()
                                        .fill(state.windows.contains(where: { $0.appType == app }) ? Color.white : Color.clear)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .padding(.bottom, 8)
                }

                // Virtual Cursor
                if state.isTrackpadActive {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2, x: 1, y: 1)
                        .position(state.cursorPosition)
                        .allowsHitTesting(false)
                        .zIndex(9999)
                }
            }
        }
    }
}
