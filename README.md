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
- Review ▸ Review… (⇧⌘R): Claude reviews the draft in the background and leaves notes in a side panel, anchored
  to the text. Review Again (⌥⌘R) continues the same Claude session and tells it which notes you applied or
  dismissed. Needs the [Claude Code](https://claude.com/claude-code) CLI (`claude`) on your login shell's `PATH`.
  The sheet's Reviewer picker lists the skills bundled in `skills/`: `writing-review`, plus
  [Clarity](https://github.com/addyosmani/clarity) and
  [plain-writing](https://github.com/docwriter-org/plain-writing-skill) (both MIT). To use one in your own Claude
  sessions too, link it, e.g. `ln -s "$PWD/skills/writing-review" ~/.claude/skills/`
