import SwiftUI
import WebKit

extension Notification.Name {
    static let pxsHandScrollDelta = Notification.Name("pxs.hand.scrollDelta")
    static let pxsHandClickAtPoint = Notification.Name("pxs.hand.clickAtPoint")
}

struct HandWindowHitResult {
    let window: PersistedWindow
    let isTitleBar: Bool
}

struct AutomaticHandScrollModifier: ViewModifier {
    let windowID: UUID
    @State private var trackedScrollView: UIScrollView?

    func body(content: Content) -> some View {
        content
            .background(
                ScrollViewFinder { scrollView in
                    if trackedScrollView !== scrollView {
                        trackedScrollView = scrollView
                    }
                }
            )
            .onReceive(NotificationCenter.default.publisher(for: .pxsHandScrollDelta)) { notification in
                guard let targetID = notification.userInfo?["windowID"] as? UUID,
                      targetID == windowID,
                      let delta = notification.userInfo?["delta"] as? CGSize,
                      let scrollView = trackedScrollView else { return }

                let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right)
                let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)

                let nextX = min(max(-scrollView.adjustedContentInset.left, scrollView.contentOffset.x - delta.width * 1.6), maxOffsetX)
                let nextY = min(max(-scrollView.adjustedContentInset.top, scrollView.contentOffset.y - delta.height * 1.6), maxOffsetY)

                scrollView.setContentOffset(CGPoint(x: nextX, y: nextY), animated: false)
            }
    }
}

extension View {
    func enableHandPinchScroll(for windowID: UUID) -> some View {
        modifier(AutomaticHandScrollModifier(windowID: windowID))
    }
}

private struct ScrollViewFinder: UIViewRepresentable {
    let onResolve: (UIScrollView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let found = findScrollView(from: uiView) {
                onResolve(found)
            }
        }
    }

    private func findScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view.superview
        while let parent = current {
            if let scroll = parent as? UIScrollView {
                return scroll
            }
            if let nested = searchSubviews(of: parent) {
                return nested
            }
            current = parent.superview
        }
        return nil
    }

    private func searchSubviews(of root: UIView) -> UIScrollView? {
        for subview in root.subviews {
            if let scroll = subview as? UIScrollView {
                return scroll
            }
            if let deeper = searchSubviews(of: subview) {
                return deeper
            }
        }
        return nil
    }
}

extension DesktopState {
    func topmostWindow(at point: CGPoint) -> HandWindowHitResult? {
        let visibleWindows = windows
            .filter { !$0.isMinimized }
            .sorted { $0.zIndex > $1.zIndex }

        for win in visibleWindows {
            let frame = CGRect(
                x: win.posX - win.width / 2,
                y: win.posY - win.height / 2,
                width: win.width,
                height: win.height
            )
            if frame.contains(point) {
                let isTitleBar = (point.y - frame.minY) <= 34.0
                return HandWindowHitResult(window: win, isTitleBar: isTitleBar)
            }
        }
        return nil
    }

    func moveWindowByHand(id: UUID, delta: CGSize, desktopSize: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }),
              !windows[index].isMaximized else { return }

        bringToFront(id)
        let newX = min(max(windows[index].width * 0.25, windows[index].posX + delta.width), desktopSize.width - windows[index].width * 0.25)
        let newY = min(max(24, windows[index].posY + delta.height), desktopSize.height - 40)

        windows[index].posX = newX
        windows[index].posY = newY
        saveWorkspace()
    }

    func scrollWindowByHand(id: UUID, delta: CGSize) {
        guard let window = windows.first(where: { $0.id == id }) else { return }

        if window.appType.isWebApp, let webView = webViewStore[id] {
            let scrollView = webView.scrollView
            let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

            if maxOffsetY > 5 || maxOffsetX > 5 {
                let targetX = min(max(0, scrollView.contentOffset.x - delta.width * 1.6), maxOffsetX)
                let targetY = min(max(0, scrollView.contentOffset.y - delta.height * 1.6), maxOffsetY)
                scrollView.setContentOffset(CGPoint(x: targetX, y: targetY), animated: false)
            } else {
                let js = "window.scrollBy({ left: \(-delta.width * 1.6), top: \(-delta.height * 1.6), behavior: 'instant' });"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        } else {
            NotificationCenter.default.post(
                name: .pxsHandScrollDelta,
                object: nil,
                userInfo: ["windowID": id, "delta": delta]
            )
        }
    }

    func performHandClick(at point: CGPoint, desktopSize: CGSize) {
        if point.y >= desktopSize.height - 68 {
            let appTypes = DesktopAppType.allCases
            let dockWidth = CGFloat(appTypes.count) * 54.0
            let dockStartX = (desktopSize.width - dockWidth) / 2.0
            if point.x >= dockStartX && point.x <= dockStartX + dockWidth {
                let idx = Int((point.x - dockStartX) / 54.0)
                if appTypes.indices.contains(idx) {
                    openAppFromHandDock(appTypes[idx])
                    return
                }
            }
        }

        guard let hit = topmostWindow(at: point) else {
            if contextMenu.isPresented {
                contextMenu.isPresented = false
            }
            return
        }

        let win = hit.window
        bringToFront(win.id)

        let frame = CGRect(
            x: win.posX - win.width / 2,
            y: win.posY - win.height / 2,
            width: win.width,
            height: win.height
        )

        if hit.isTitleBar {
            let localX = point.x - frame.minX
            if localX <= 26 {
                closeWindow(win.id)
                return
            } else if localX <= 48 {
                toggleMinimize(win.id)
                return
            } else if localX <= 70 {
                toggleMaximize(win.id, desktopSize: desktopSize)
                return
            }
        }

        if win.appType.isWebApp, let webView = webViewStore[win.id] {
            let contentLocalX = point.x - frame.minX
            let contentLocalY = point.y - (frame.minY + 34.0)
            if contentLocalY >= 0 {
                let js = "(function() { var el = document.elementFromPoint(\(contentLocalX), \(contentLocalY)); if (el) { el.focus(); el.click(); } })();"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        NotificationCenter.default.post(
            name: .pxsHandClickAtPoint,
            object: nil,
            userInfo: ["windowID": win.id, "point": point]
        )
    }

    private func openAppFromHandDock(_ appType: DesktopAppType) {
        if let existingIndex = windows.firstIndex(where: { $0.appType == appType }) {
            windows[existingIndex].isMinimized = false
            bringToFront(windows[existingIndex].id)
            saveWorkspace()
            return
        }

        openApp(appType)
    }
}
