import SafariServices
import SwiftUI
import WebKit

/// A den's own page, full screen. Only the den's origin loads here; any
/// other link opens in Safari. The page reaches the app through one bridge,
/// answered only for the den's own top frame.
struct DenView: UIViewRepresentable {
    let den: DenLink
    let state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(den: den, state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let passkeys = Epeaky.passkeyHosts.contains(den.host)
        let script = """
        (() => {
          const h = window.webkit.messageHandlers.epeaky;
          Object.defineProperty(window, 'epeakyApp', { value: Object.freeze({ passkeys: \(passkeys), call: (t, a = {}) => h.postMessage(Object.assign({}, a, { t })) }) });
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "epeaky")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(named: "Background")
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        #if DEBUG
        web.isInspectable = true
        #endif
        context.coordinator.web = web
        web.load(URLRequest(url: den.url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "epeaky", contentWorld: .page)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply, WKDownloadDelegate {
        let den: DenLink
        let state: AppState
        weak var web: WKWebView?
        private var downloads: [ObjectIdentifier: URL] = [:]

        init(den: DenLink, state: AppState) {
            self.den = den
            self.state = state
        }

        private func isDen(_ origin: WKSecurityOrigin) -> Bool {
            den.isOrigin(scheme: origin.protocol, host: origin.host, port: origin.port)
        }

        private func isDen(_ url: URL?) -> Bool {
            guard let url else { return false }
            return den.isOrigin(scheme: url.scheme, host: url.host, port: url.port)
        }

        // ---- The bridge -------------------------------------------------------------

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            guard message.frameInfo.isMainFrame, isDen(message.frameInfo.securityOrigin),
                  let body = message.body as? [String: Any], let t = body["t"] as? String else { return replyHandler(nil, "refused") }
            let origin = den.origin.absoluteString
            switch t {
            case "push":
                Task { @MainActor in
                    do { replyHandler(try await Push.shared.subscribe(origin: origin), nil) } catch { replyHandler(nil, error.localizedDescription) }
                }
            case "push-off":
                Task { @MainActor in replyHandler(Push.shared.unsubscribe(origin: origin), nil) }
            case "switch":
                Task { @MainActor in
                    state.switchDen()
                    replyHandler(nil, nil)
                }
            default:
                replyHandler(nil, "unknown")
            }
        }

        // ---- What loads where ---------------------------------------------------------

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            if action.shouldPerformDownload { return (.download, preferences) }
            guard let url = action.request.url else { return (.cancel, preferences) }
            if ["about", "blob", "data"].contains(url.scheme ?? "") { return (.allow, preferences) }
            // A frame inside the den's page (Cashboard): its own origin, as on the web.
            if action.targetFrame?.isMainFrame == false { return (url.scheme == "https" ? .allow : .cancel, preferences) }
            if isDen(url) { return (.allow, preferences) }
            await MainActor.run { self.openOutside(url) }
            return (.cancel, preferences)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            response.canShowMIMEType ? .allow : .download
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

        /// A new window (a link with a target, Cashboard's swap window): in Safari.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { openOutside(url) }
            return nil
        }

        /// The den's page may ask for the microphone (voice), and its person
        /// says yes each time; nothing framed in it may ask.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
            frame.isMainFrame && isDen(origin) && type == .microphone ? .prompt : .deny
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
            await withCheckedContinuation { c in
                let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default) { _ in c.resume() })
                present(a)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
            await withCheckedContinuation { c in
                let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in c.resume(returning: false) })
                a.addAction(UIAlertAction(title: "OK", style: .default) { _ in c.resume(returning: true) })
                present(a)
            }
        }

        // ---- Downloads: to the share sheet -------------------------------------------

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = suggestedFilename.replacingOccurrences(of: "/", with: "_")
            let url = dir.appendingPathComponent(name.isEmpty ? "file" : name)
            downloads[ObjectIdentifier(download)] = url
            return url
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
            Task { @MainActor in
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = self.web
                self.present(share)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloads.removeValue(forKey: ObjectIdentifier(download))
        }

        // ---- Helpers ---------------------------------------------------------------------

        @MainActor private func openOutside(_ url: URL) {
            guard url.scheme == "https" || url.scheme == "http" else {
                if url.scheme == "mailto" { UIApplication.shared.open(url) }
                return
            }
            present(SFSafariViewController(url: url))
        }

        @MainActor private func present(_ vc: UIViewController) {
            var top = web?.window?.rootViewController
            while let next = top?.presentedViewController { top = next }
            top?.present(vc, animated: true)
        }
    }
}
