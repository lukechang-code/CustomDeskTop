import SwiftUI
import WebKit

struct ExternalDesktopView: View {
    @EnvironmentObject var desktopState: DesktopState
    @State private var windowOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Desktop Wallpaper
            LinearGradient(colors: [Color.indigo, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            // Desktop Browser Window
            VStack(spacing: 0) {
                // Window Title Bar (Draggable)
                HStack {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                    Circle().fill(Color.yellow).frame(width: 12, height: 12)
                    Circle().fill(Color.green).frame(width: 12, height: 12)
                    Spacer()
                    Text(desktopState.currentURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color(UIColor.systemGray5))

                // Desktop Web View
                DesktopWebView(
                    urlString: desktopState.currentURL,
                    scrollDelta: desktopState.scrollDelta,
                    clickTrigger: desktopState.clickTrigger,
                    cursorPosition: desktopState.cursorPosition
                )
            }
            .frame(width: 1100, height: 750)
            .cornerRadius(12)
            .shadow(radius: 20)
            .position(x: desktopState.desktopSize.width / 2 + windowOffset.width,
                      y: desktopState.desktopSize.height / 2 + windowOffset.height)

            // Virtual Mouse Pointer
            Image(systemName: "cursorarrow")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 2)
                .position(desktopState.cursorPosition)
                .allowsHitTesting(false)
        }
    }
}

struct DesktopWebView: UIViewRepresentable {
    var urlString: String
    var scrollDelta: CGPoint
    var clickTrigger: Bool
    var cursorPosition: CGPoint

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        // Force desktop user agent like PXS Desktop
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url?.absoluteString != urlString, let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        // Inject pinch-and-drag scroll into the webpage
        if scrollDelta != .zero {
            let js = "window.scrollBy(\(scrollDelta.x), \(scrollDelta.y));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
