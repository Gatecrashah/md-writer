import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        // Menu key equivalents match unshifted characters, so ⌘/ is unreachable on layouts
        // where "/" needs Shift (e.g. Finnish ⇧7). There, with ⌘ held, `characters` is "7"
        // and `charactersIgnoringModifiers` is "/".
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            guard mods == .command, event.charactersIgnoringModifiers == "/" else { return event }
            NSApp.sendAction(#selector(EditorWindowController.toggleSourceMode(_:)), to: nil, from: nil)
            return nil
        }
    }
}

private func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
}

private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let menu = NSMenu(title: title)
    items.forEach(menu.addItem)
    let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    parent.submenu = menu
    return parent
}

private func makeMainMenu() -> NSMenu {
    let appName = ProcessInfo.processInfo.processName
    let recent = submenu("Open Recent", [item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))])

    let windowMenu = submenu("Window", [
        item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        item("Zoom", #selector(NSWindow.performZoom(_:))),
        .separator(),
        item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
    ])
    NSApp.windowsMenu = windowMenu.submenu

    let main = NSMenu()
    [
        submenu(appName, [
            item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"),
        ]),
        submenu("File", [
            item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recent,
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save…", #selector(NSDocument.save(_:)), "s"),
            item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]),
            item("Rename…", #selector(NSDocument.rename(_:))),
            item("Move To…", #selector(NSDocument.move(_:))),
            item("Revert To…", #selector(NSDocument.revertToSaved(_:))),
            .separator(),
            item("Print…", #selector(NSDocument.printDocument(_:)), "p"),
        ]),
        submenu("Edit", [
            item("Undo", #selector(EditorWindowController.undoEdit(_:)), "z"),
            item("Redo", #selector(EditorWindowController.redoEdit(_:)), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(EditorWindowController.showFind(_:)), "f"),
            item("Find Next", #selector(EditorWindowController.findNext(_:)), "g"),
            item("Find Previous", #selector(EditorWindowController.findPrevious(_:)), "g", [.command, .shift]),
        ]),
        submenu("Paragraph", (1...6).map { level in
            let heading = item("Heading \(level)", #selector(EditorWindowController.setHeading(_:)), "\(level)")
            heading.tag = level
            return heading
        } + [
            .separator(),
            item("Paragraph", #selector(EditorWindowController.setHeading(_:)), "0"),
        ]),
        submenu("View", [
            item("Source Code Mode", #selector(EditorWindowController.toggleSourceMode(_:)), "/"),
            .separator(),
            item("Actual Size", #selector(EditorWindowController.resetZoom(_:)), "0", [.command, .option]),
            item("Zoom In", #selector(EditorWindowController.zoomIn(_:)), "+"),
            item("Zoom Out", #selector(EditorWindowController.zoomOut(_:)), "-"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]),
        windowMenu,
    ].forEach(main.addItem)
    return main
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
