import AppKit
import SwiftUI
import WebKit

@MainActor final class SharedBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = SharedBrowser()
    @Published var address = "https://www.wikipedia.org"
    @Published var error: String?
    @Published var zoom: Double = 1.25
    let web = WKWebView(frame: .zero)
    private var window: NSWindow?
    override init() {
        super.init(); web.navigationDelegate = self; web.uiDelegate = self
        web.pageZoom = zoom
        web.loadHTMLString("<html><meta name='viewport' content='width=device-width'><body style='margin:0;background:#141416;color:#f1f1f3;font:28px -apple-system;padding:70px'><p style='color:#b7abff;font-size:16px'>ANIMA STUDIO · COMPARTIR</p><h1>Una ventana.<br>Lo que quieras mostrar.</h1><p>Abrí una web en la barra de arriba.</p><p style='font-size:18px;color:#a4a4ae'>Seleccioná esta ventana en NDI.<br>Los chats quedan afuera.</p></body></html>", baseURL: nil)
    }
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "COMPARTIR — Anima Studio"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SharedBrowserView(browser: self)); w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    static func webURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let value = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    func go() { guard let url = Self.webURL(address) else { error = "Pegá una dirección web válida (https://…)."; return }; error = nil; web.load(URLRequest(url: url)) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if let u = webView.url, u.scheme != "about" { address = u.absoluteString }; error = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.error = "La página no cargó. Podés usar Chrome y seleccionarlo en NDI." }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, Self.webURL(url.absoluteString) != nil { web.load(URLRequest(url: url)) }; return nil
    }
}
struct SharedWebContent: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
struct SharedBrowserView: View {
    @ObservedObject var browser: SharedBrowser
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { browser.web.goBack() } label: { Image(systemName: "chevron.left") }.help("Volver")
                TextField("Dirección web", text: $browser.address).textFieldStyle(.roundedBorder).onSubmit { browser.go() }
                Button("Abrir") { browser.go() }
                Button("A−") { browser.zoom = max(0.75, browser.zoom - 0.15); browser.web.pageZoom = browser.zoom }
                Button("A+") { browser.zoom = min(3, browser.zoom + 0.15); browser.web.pageZoom = browser.zoom }
            }.padding(12)
            if let error = browser.error { Text(error).foregroundStyle(.orange).padding(8) }
            SharedWebContent(web: browser.web)
        }.background(StudioPalette.canvas).preferredColorScheme(.dark)
    }
}
