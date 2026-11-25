import SwiftUI
import WebKit
import AVKit

/// Klassische Web-Ansicht (YouTube bzw. YouTube Music direkt), als Notlösung.
struct ClassicWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.applicationNameForUserAgent = Scripts.safariSuffix
        Scripts.installClassic(into: config.userContentController)
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = Theme.uiBackground
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(WebPolicy.decide(navigationAction))
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if Scripts.adblockEnabled, !Scripts.engineJS.isEmpty {
                webView.evaluateJavaScript(Scripts.engineJS, completionHandler: nil)
            }
        }
    }
}

struct ClassicSheet: View {
    let page: ClassicPage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ClassicWebView(url: page.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Klassische Ansicht")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

/// Google-Anmeldung (Cookies landen im gemeinsamen Datenspeicher).
struct LoginWebView: UIViewRepresentable {
    let onYouTube: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onYouTube) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = Scripts.safariSuffix
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        let login = "https://accounts.google.com/ServiceLogin?service=youtube&hl=de&continue=https%3A%2F%2Fm.youtube.com%2F"
        if let url = URL(string: login) { web.load(URLRequest(url: url)) }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onYouTube: () -> Void
        init(_ cb: @escaping () -> Void) { onYouTube = cb }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(WebPolicy.allowWithoutAppLink)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if webView.url?.host?.contains("youtube.com") == true { onYouTube() }
        }
    }
}

struct LoginSheet: View {
    @EnvironmentObject private var session: SessionState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView {
                Task {
                    await session.didChangeLogin()
                    if session.isLoggedIn { dismiss() }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Bei Google anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        Task { await session.didChangeLogin(); dismiss() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = Theme.uiAccent
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Anmeldestatus + Steuerung für Neuladen nach Login/Logout.
@MainActor
final class SessionState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var generation = 0
    @Published var showLogin = false
    @Published var classic: ClassicPage?
    @Published var pendingSearch: String?
    @Published var pendingRoute: Route?
    @Published var hidden: Set<String> = []
    @Published var newPlaylistFor: MediaItem?

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        isLoggedIn = await InnerTube.shared.isLoggedIn()
    }

    func didChangeLogin() async {
        InnerTube.shared.resetConfig()
        Feeds.clearCache()
        await refresh()
        generation += 1
        await YouTubePlaylists.shared.load(force: true)
    }

    func logout() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let mine = records.filter { r in
            ["youtube", "google"].contains { r.displayName.lowercased().contains($0) }
        }
        await store.removeData(ofTypes: types, for: mine)
        await didChangeLogin()
    }
}
