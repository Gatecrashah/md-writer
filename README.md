# MD Writer

A Typora-style live-preview Markdown editor for macOS.

Architecture (modeled on how Typora's Mac app is built, as seen with REA and by inspecting the bundle): a native AppKit
`NSDocument` app hosting a `WKWebView` that runs the editor, with a single script message handler as the bridge.
The editor is [Milkdown Crepe](https://milkdown.dev) (ProseMirror, CodeMirror code blocks, KaTeX math, tables, tasks).

## Build

Requires Swift (Xcode command line tools) and [bun](https://bun.sh).

    ./scripts/build-app.sh
    open "dist/MD Writer.app"

## Features

- WYSIWYG Markdown editing, light/dark following the system
- Source code mode: ⌘/
- Autosave, versions (File ▸ Revert To…), tabs, recent files, rename/move via NSDocument
- Pasted/dropped images are saved to `assets/` next to the document
- Relative image paths resolve against the document's folder
- ⌘-click opens links; zoom with ⌘+ / ⌘- / ⌘0; Print / PDF with ⌘P
- Word count in the status bar
