import AppKit
import WebKit

/// Messages the web editor posts to the `mdw` script message handler.
private enum EditorMessage {
    case ready
    case changed(markdown: String)
    case openURL(URL)
    case saveImage(id: Int, name: String, data: Data)
    case requestReview
    case cancelReview
    case reviewOutcome(id: String, outcome: ReviewThread.Outcome)

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
        case "requestReview":
            self = .requestReview
        case "cancelReview":
            self = .cancelReview
        case "reviewOutcome":
            guard let id = dict["id"] as? String, let raw = dict["outcome"] as? String,
                  let outcome = ReviewThread.Outcome(rawValue: raw) else { return nil }
            self = .reviewOutcome(id: id, outcome: outcome)
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

final class EditorWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate,
    NSMenuItemValidation {
    private let webView: WKWebView
    private var editorReady = false
    private var reviewThread: ReviewThread?
    private var reviewRunner: ReviewRunner?

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
        case .requestReview:
            requestReview(nil)
        case .cancelReview:
            cancelReview(nil)
        case .reviewOutcome(let id, let outcome):
            reviewThread?.outcomes[id] = outcome
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
    @objc func setHeading(_ sender: NSMenuItem) { call("mdw.setHeading(level)", ["level": sender.tag]) }
    @objc func showFind(_ sender: Any?) { call("mdw.showFind()") }
    @objc func findNext(_ sender: Any?) { call("mdw.findNext()") }
    @objc func findPrevious(_ sender: Any?) { call("mdw.findPrevious()") }
    @objc func zoomIn(_ sender: Any?) { webView.pageZoom = min(webView.pageZoom + 0.1, 3) }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    @objc func resetZoom(_ sender: Any?) { webView.pageZoom = 1 }

    @objc func requestReview(_ sender: Any?) { showReviewSheet(fresh: false) }
    @objc func startFreshReview(_ sender: Any?) { showReviewSheet(fresh: true) }
    @objc func reviewAgain(_ sender: Any?) {
        guard let reviewThread else { return showReviewSheet(fresh: false) }
        runReview(reviewThread)
    }
    @objc func cancelReview(_ sender: Any?) { reviewRunner?.cancel() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(requestReview(_:)), #selector(startFreshReview(_:)), #selector(reviewAgain(_:)):
            return reviewRunner == nil
        case #selector(cancelReview(_:)):
            return reviewRunner != nil
        default:
            return true
        }
    }

    // MARK: Review

    private func showReviewSheet(fresh: Bool) {
        guard let window, reviewRunner == nil else { return }
        let defaults = UserDefaults.standard
        let last = reviewThread?.request ?? ReviewRequest(
            lens: ReviewLens(rawValue: defaults.string(forKey: "reviewLens") ?? "") ?? .lineEdit,
            model: ReviewModel(rawValue: defaults.string(forKey: "reviewModel") ?? "") ?? .sonnet,
            note: "")

        let lens = NSPopUpButton()
        lens.addItems(withTitles: ReviewLens.allCases.map(\.title))
        lens.selectItem(at: ReviewLens.allCases.firstIndex(of: last.lens)!)
        let model = NSPopUpButton()
        model.addItems(withTitles: ReviewModel.allCases.map(\.title))
        model.selectItem(at: ReviewModel.allCases.firstIndex(of: last.model)!)
        let note = NSTextField(string: last.note)
        note.placeholderString = "Optional, e.g. \"for a non-technical audience\""
        note.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Focus:"), lens],
            [NSTextField(labelWithString: "Model:"), model],
            [NSTextField(labelWithString: "Note:"), note],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.frame.size = grid.fittingSize

        let alert = NSAlert()
        alert.messageText = fresh || reviewThread == nil ? "Review This Draft" : "Review Again"
        alert.informativeText = fresh || reviewThread == nil
            ? "Claude reads the draft and leaves notes in the margin."
            : "Claude continues the previous review and sees which notes you applied or dismissed."
        alert.accessoryView = grid
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = lens
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let request = ReviewRequest(lens: ReviewLens.allCases[lens.indexOfSelectedItem],
                                        model: ReviewModel.allCases[model.indexOfSelectedItem],
                                        note: note.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            defaults.set(request.lens.rawValue, forKey: "reviewLens")
            defaults.set(request.model.rawValue, forKey: "reviewModel")
            // A different focus is a different review; resuming would carry the old lens's notes along.
            if fresh || reviewThread?.request.lens != request.lens {
                reviewThread = ReviewThread(request: request)
            } else {
                reviewThread?.request = request
            }
            runReview(reviewThread!)
        }
    }

    private func runReview(_ thread: ReviewThread) {
        guard let doc = markdownDocument, reviewRunner == nil else { return }
        let runner = ReviewRunner()
        reviewRunner = runner
        call("mdw.reviewStarted()")
        runner.start(markdown: doc.markdown, prompt: thread.prompt(), model: thread.request.model,
                     resume: thread.sessionID) { [weak self] result in
            guard let self else { return }
            reviewRunner = nil
            switch result {
            case .success(let (review, sessionID)):
                var next = thread
                next.sessionID = sessionID
                next.round += 1
                next.outcomes = [:]
                next.findings = Dictionary(uniqueKeysWithValues: review.findings.enumerated().map {
                    ("\(next.round).\($0.offset + 1)", $0.element)
                })
                reviewThread = next
                let findings = review.findings.indices.map { i -> [String: Any] in
                    let f = review.findings[i]
                    var dict: [String: Any] = ["id": "\(next.round).\(i + 1)", "kind": f.kind.rawValue,
                                               "quote": f.quote, "message": f.message]
                    if let r = f.replacement { dict["replacement"] = r }
                    return dict
                }
                let label = "\(thread.request.lens.title) · \(thread.request.model.title) · round \(next.round)"
                call("mdw.showReview(review)", ["review": ["summary": review.summary, "label": label,
                                                           "findings": findings]])
            case .failure(.cancelled):
                call("mdw.reviewEnded()")
            case .failure(let error):
                call("mdw.reviewEnded()")
                guard let window else { return }
                let alert = NSAlert()
                alert.messageText = "Review Failed"
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window)
            }
        }
    }

    func printOperation(with info: NSPrintInfo) -> NSPrintOperation {
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        return op
    }
}
