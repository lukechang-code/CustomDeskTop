import SwiftUI
import WebKit

// MARK: - Models & Persistence

enum DesktopAppType: String, Codable, CaseIterable, Identifiable {
    case browser = "Browser"
    case notes = "Notes"
    case files = "Files"
    case terminal = "Terminal"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .browser: return "safari.fill"
        case .notes: return "note.text"
        case .files: return "folder.fill"
        case .terminal: return "terminal.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .browser: return .blue
        case .notes: return .yellow
        case .files: return .cyan
        case .terminal: return .green
        }
    }
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
}

struct SavedWorkspaceSnapshot: Codable {
    var windows: [PersistedWindow]
    var savedAt: Date
}

final class DesktopState: ObservableObject {
    @Published var windows: [PersistedWindow] = []
    @Published var cursorPosition: CGPoint = CGPoint(x: 420, y: 260)
    @Published var isTrackpadActive: Bool = true
    @Published var hasClosedWorkspaceBackup: Bool = false

    private let activeWorkspaceKey = "pxs.desktop.activeWorkspace.v6"
    private let closedWorkspaceKey = "pxs.desktop.closedWorkspaceBackup.v6"
    private var topZIndex: Double = 10

    init() {
        restoreWorkspaceOnLaunch()
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
        windows = [
            PersistedWindow(
                id: UUID(),
                appType: .browser,
                title: "Safari Desktop",
                urlString: "https://www.apple.com",
                noteText: "",
                posX: 340,
                posY: 260,
                width: 520,
                height: 360,
                zIndex: 1,
                isMinimized: false
            ),
            PersistedWindow(
                id: UUID(),
                appType: .notes,
                title: "Scratchpad",
                urlString: "",
                noteText: "Pinch and two-finger drag scrolling is enabled inside web views.",
                posX: 680,
                posY: 320,
                width: 340,
                height: 280,
                zIndex: 2,
                isMinimized: false
            )
        ]
        topZIndex = 3
        saveWorkspace()
    }

    func saveWorkspace() {
        if let data = try? JSONEncoder().encode(windows) {
            UserDefaults.standard.set(data, forKey: activeWorkspaceKey)
        }
    }

    /// Archives the current workspace before closing all windows or resetting the layout
    /// so the user can reopen their previous session at any time.
    func archiveCurrentWorkspaceForReopen() {
        guard !windows.isEmpty else { return }
        let snapshot = SavedWorkspaceSnapshot(windows: windows, savedAt: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: closedWorkspaceKey)
            hasClosedWorkspaceBackup = true
        }
    }

    /// Closes all currently open windows after saving a reopen snapshot.
    func closeAllWindows() {
        archiveCurrentWorkspaceForReopen()
        windows.removeAll()
        saveWorkspace()
    }

    /// Resets the desktop to the clean default layout while preserving the previous session for Reopen Workspace.
    func resetLayout() {
        archiveCurrentWorkspaceForReopen()
        loadDefaultWorkspace()
    }

    /// Restores the last closed or reset workspace session.
    func reopenPreviousWorkspace() {
        guard let data = UserDefaults.standard.data(forKey: closedWorkspaceKey),
              let snapshot = try? JSONDecoder().decode(SavedWorkspaceSnapshot.self, from: data),
              !snapshot.windows.isEmpty else {
            return
        }

        // If current windows exist, swap them into backup so reopen acts cleanly
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
        let offset = CGFloat((windows.count % 5) * 28)
        let newWindow = PersistedWindow(
            id: UUID(),
            appType: type,
            title: type.rawValue,
            urlString: type == .browser ? "https://www.apple.com" : "",
            noteText: type == .notes ? "New note..." : "",
            posX: 380 + offset,
            posY: 260 + offset,
            width: type == .browser ? 540 : 380,
            height: type == .browser ? 380 : 280,
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
        windows.removeAll { $0.id == id }
        saveWorkspace()
    }

    func toggleMinimize(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].isMinimized.toggle()
        saveWorkspace()
    }
}

// MARK: - Main Desktop View

struct ContentView: View {
    @EnvironmentObject var state: DesktopState
    @State private var showWorkspaceBanner: Bool = false
    @State private var bannerMessage: String = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Desktop Wallpaper
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.14, green: 0.18, blue: 0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Empty Desktop Prompt with Quick Reopen Workspace Action
                if state.windows.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 42))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("No Open Windows")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.85))
                        if state.hasClosedWorkspaceBackup {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    state.reopenPreviousWorkspace()
                                }
                                triggerBanner("Workspace Reopened")
                            } label: {
                                Label("Reopen Workspace", systemImage: "arrow.uturn.backward.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.blue, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }

                // Active Desktop Windows
                ForEach($state.windows) { $window in
                    if !window.isMinimized {
                        DesktopWindowView(window: $window)
                            .environmentObject(state)
                            .zIndex(window.zIndex)
                    }
                }

                // Status Toast Banner
                if showWorkspaceBanner {
                    VStack {
                        Text(bannerMessage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                            .padding(.top, 16)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(998)
                }

                // Virtual Trackpad Overlay (Bottom-Right Corner)
                if state.isTrackpadActive {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VirtualTrackpadView(desktopSize: geo.size)
                                .environmentObject(state)
                                .padding(.trailing, 16)
                                .padding(.bottom, 84)
                        }
                    }
                    .zIndex(990)
                }

                // Virtual Hardware Pointer
                Image(systemName: "cursorarrow")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 1, y: 1)
                    .position(state.cursorPosition)
                    .allowsHitTesting(false)
                    .zIndex(999)

                // Bottom Desktop Dock
                VStack {
                    Spacer()
                    DesktopDockView(onNotify: triggerBanner)
                        .environmentObject(state)
                        .padding(.bottom, 12)
                }
                .zIndex(995)
            }
        }
    }

    private func triggerBanner(_ text: String) {
        bannerMessage = text
        withAnimation { showWorkspaceBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showWorkspaceBanner = false }
        }
    }
}

// MARK: - Desktop Window Container

struct DesktopWindowView: View {
    @Binding var window: PersistedWindow
    @EnvironmentObject var state: DesktopState
    @State private var dragStartPos: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            // Window Title Bar
            HStack(spacing: 8) {
                Button {
                    state.closeWindow(window.id)
                } label: {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                }

                Button {
                    state.toggleMinimize(window.id)
                } label: {
                    Circle().fill(Color.yellow).frame(width: 12, height: 12)
                }

                Circle().fill(Color.green).frame(width: 12, height: 12)

                Image(systemName: window.appType.iconName)
                    .font(.caption)
                    .foregroundStyle(window.appType.accentColor)

                Text(window.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.black.opacity(0.65))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartPos == nil {
                            dragStartPos = CGPoint(x: window.posX, y: window.posY)
                            state.bringToFront(window.id)
                        }
                        if let start = dragStartPos {
                            window.posX = start.x + value.translation.width
                            window.posY = start.y + value.translation.height
                        }
                    }
                    .onEnded { _ in
                        dragStartPos = nil
                        state.saveWorkspace()
                    }
            )

            // Window Body
            Group {
                switch window.appType {
                case .browser:
                    NativeScrollWebView(urlString: $window.urlString) {
                        state.saveWorkspace()
                    }
                case .notes:
                    TextEditor(text: $window.noteText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color(white: 0.12))
                        .onChange(of: window.noteText) { _ in
                            state.saveWorkspace()
                        }
                case .files:
                    List {
                        Label("Documents", systemImage: "folder")
                        Label("Downloads", systemImage: "arrow.down.circle")
                        Label("Workspace_Backup.json", systemImage: "doc.text")
                    }
                    .listStyle(.plain)
                case .terminal:
                    ScrollView {
                        Text("pxs@desktop ~ % workspace ready\nPinch & pan gestures active.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(Color.black)
                }
            }
        }
        .frame(width: window.width, height: window.height)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 6)
        .position(x: window.posX, y: window.posY)
        .onTapGesture {
            state.bringToFront(window.id)
        }
    }
}

// MARK: - Native Pinch & Drag WKWebView

struct NativeScrollWebView: UIViewRepresentable {
    @Binding var urlString: String
    var onURLChanged: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        // Enable native iOS pinch-to-zoom and simultaneous pan/drag scrolling
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.scrollView.bouncesZoom = true
        webView.scrollView.minimumZoomScale = 0.5
        webView.scrollView.maximumZoomScale = 4.0
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: NativeScrollWebView
        init(_ parent: NativeScrollWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let current = webView.url?.absoluteString, current != parent.urlString {
                parent.urlString = current
                parent.onURLChanged()
            }
        }
    }
}

// MARK: - Virtual Trackpad

struct VirtualTrackpadView: View {
    @EnvironmentObject var state: DesktopState
    let desktopSize: CGSize
    @State private var lastTranslation: CGSize = .zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            VStack(spacing: 4) {
                Image(systemName: "hand.draw.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
                Text("Trackpad")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 150, height: 110)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let dx = value.translation.width - lastTranslation.width
                    let dy = value.translation.height - lastTranslation.height
                    lastTranslation = value.translation

                    let newX = min(max(0, state.cursorPosition.x + dx * 1.4), desktopSize.width)
                    let newY = min(max(0, state.cursorPosition.y + dy * 1.4), desktopSize.height)
                    state.cursorPosition = CGPoint(x: newX, y: newY)
                }
                .onEnded { _ in
                    lastTranslation = .zero
                }
        )
    }
}

// MARK: - Desktop Dock with Reopen Workspace

struct DesktopDockView: View {
    @EnvironmentObject var state: DesktopState
    var onNotify: (String) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(DesktopAppType.allCases) { app in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        state.openApp(app)
                    }
                } label: {
                    Image(systemName: app.iconName)
                        .font(.title3)
                        .foregroundStyle(app.accentColor)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            Divider()
                .frame(height: 26)
                .background(Color.white.opacity(0.3))

            // Minimized Windows Restore Pills
            ForEach(state.windows.filter(\.isMinimized)) { minimized in
                Button {
                    withAnimation { state.bringToFront(minimized.id) }
                } label: {
                    Image(systemName: minimized.appType.iconName)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.blue.opacity(0.45), in: Circle())
                }
            }

            // Reopen Workspace Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    state.reopenPreviousWorkspace()
                }
                onNotify("Reopened Previous Workspace")
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.hasClosedWorkspaceBackup ? .white : .white.opacity(0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .disabled(!state.hasClosedWorkspaceBackup)

            // Workspace Menu (Close All / Reset Layout / Toggle Trackpad)
            Menu {
                Button {
                    withAnimation { state.reopenPreviousWorkspace() }
                    onNotify("Reopened Previous Workspace")
                } label: {
                    Label("Reopen Workspace", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(!state.hasClosedWorkspaceBackup)

                Button {
                    withAnimation { state.closeAllWindows() }
                    onNotify("Workspace Closed (Saved for Reopen)")
                } label: {
                    Label("Close All Windows", systemImage: "xmark.rectangle.portrait")
                }
                .disabled(state.windows.isEmpty)

                Button(role: .destructive) {
                    withAnimation { state.resetLayout() }
                    onNotify("Layout Reset (Previous Saved)")
                } label: {
                    Label("Reset Layout", systemImage: "arrow.counterclockwise")
                }

                Divider()

                Button {
                    state.isTrackpadActive.toggle()
                } label: {
                    Label(
                        state.isTrackpadActive ? "Hide Trackpad" : "Show Trackpad",
                        systemImage: "hand.draw"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
    }
}
