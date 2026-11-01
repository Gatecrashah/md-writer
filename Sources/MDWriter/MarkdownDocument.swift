import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The document's Markdown, kept in sync with the editor on every change.
    var markdown = ""

    override class var autosavesInPlace: Bool { true }

    override init() {
        super.init()
        // Edits are tracked from the editor's content; WebKit's undo registrations
        // (e.g. typing in the find field) must not mark the document as edited.
        hasUndoManager = false
    }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController())
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        markdown = text
        editor?.loadDocument()
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(markdown.utf8)
    }

    override var fileURL: URL? {
        didSet { editor?.updateBaseDirectory() }
    }

    var directoryURL: URL? { fileURL?.deletingLastPathComponent() }

    private var editor: EditorWindowController? {
        windowControllers.first as? EditorWindowController
    }
}

extension MarkdownDocument {
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let editor else { throw CocoaError(.featureUnsupported) }
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        return editor.printOperation(with: info)
    }
}
