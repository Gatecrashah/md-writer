import AppKit
import WebKit

/// Messages the web editor posts to the `mdw` script message handler.
private enum EditorMessage {
    case ready
    case changed(markdown: String)
    case openURL(URL)
    case saveImage(id: Int, name: String, data: Data)

    init?(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "changed":
            guard let md = dict["markdown"] as? String else { return nil }
            self = .changed(markdown: md)
        case "openURL":
            guard let s = dict["url"] as? String, let url = URL(string: s) else { return nil }
            self = .openURL(url)
        case "saveImage":
            guard let id = dict["id"] as? Int, let name = dict["name"] as? String,
                  let b64 = dict["base64"] as? String, let data = Data(base64Encoded: b64) else { return nil }
            self = .saveImage(id: id, name: name, data: data)
        default:
            return nil
        }
    }
}

/// WKUserContentController retains its handlers strongly; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

final class EditorWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {
    private let webView: WKWebView
    private var editorReady = false

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .preferred
        window.minSize = NSSize(width: 400, height: 300)
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255, alpha: 1)
                : .white
        }
        let container = NSView()
        window.contentView = container
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        let content = window.contentLayoutGuide as! NSLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        window.setFrameAutosaveName("EditorWindow")
        if window.frame.origin == .zero { window.center() }
        super.init(window: window)

        config.userContentController.add(WeakMessageHandler(self), name: "mdw")
        webView.navigationDelegate = self
        let web = Bundle.main.resourceURL!.appendingPathComponent("web")
        webView.loadFileURL(web.appendingPathComponent("index.html"),
                            allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Native → editor

    func loadDocument() {
        guard editorReady, let doc = markdownDocument else { return }
        call("mdw.load(markdown, dir)", ["markdown": doc.markdown, "dir": doc.directoryURL?.path ?? NSNull()])
    }

    func updateBaseDirectory() {
        guard editorReady else { return }
        call("mdw.setBaseDir(dir)", ["dir": markdownDocument?.directoryURL?.path ?? NSNull()])
    }

    private func call(_ js: String, _ args: [String: Any] = [:]) {
        webView.callAsyncJavaScript(js, arguments: args, in: nil, in: .page) { result in
            if case .failure(let error) = result { NSLog("MDWriter JS error: \(error)") }
        }
    }

    // MARK: Editor → native

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let msg = EditorMessage(message.body) else {
            NSLog("MDWriter: ignoring malformed message \(message.body)")
            return
        }
        switch msg {
        case .ready:
            editorReady = true
            window?.makeFirstResponder(webView)
            loadDocument()
        case .changed(let md):
            markdownDocument?.markdown = md
            markdownDocument?.updateChangeCount(.changeDone)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .saveImage(let id, let name, let data):
            let path = (try? saveImage(named: name, data: data)) ?? ""
            call("mdw.imageSaved(id, path)", ["id": id, "path": path])
        }
    }

    /// Writes a pasted or dropped image to `assets/` next to the document and returns its relative path.
    private func saveImage(named name: String, data: Data) throws -> String {
        guard let dir = markdownDocument?.directoryURL else { throw CocoaError(.fileNoSuchFile) }
        let assets = dir.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.isEmpty ? "png" : (name as NSString).pathExtension
        var candidate = "\(stem).\(ext)"
        var n = 1
        while FileManager.default.fileExists(atPath: assets.appendingPathComponent(candidate).path) {
            candidate = "\(stem)-\(n).\(ext)"
            n += 1
        }
        try data.write(to: assets.appendingPathComponent(candidate))
        return "assets/\(candidate)"
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .other, action.targetFrame?.isMainFrame == true,
           action.request.url?.lastPathComponent == "index.html" {
            decisionHandler(.allow)
            return
        }
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    // MARK: Menu actions

    @objc func undoEdit(_ sender: Any?) { call("mdw.undo()") }
    @objc func redoEdit(_ sender: Any?) { call("mdw.redo()") }
    @objc func toggleSourceMode(_ sender: Any?) { call("mdw.toggleSourceMode()") }
    @objc func showFind(_ sender: Any?) { call("mdw.showFind()") }
    @objc func findNext(_ sender: Any?) { call("mdw.findNext()") }
    @objc func findPrevious(_ sender: Any?) { call("mdw.findPrevious()") }
    @objc func zoomIn(_ sender: Any?) { webView.pageZoom = min(webView.pageZoom + 0.1, 3) }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    @objc func resetZoom(_ sender: Any?) { webView.pageZoom = 1 }

    func printOperation(with info: NSPrintInfo) -> NSPrintOperation {
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        return op
    }
}
