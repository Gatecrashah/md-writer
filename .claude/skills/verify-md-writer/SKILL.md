---
name: verify-md-writer
description: Launch and drive a disposable instance of MD Writer (the native macOS Markdown editor in this repo) through accessibility, and capture proof that a feature works: agent review and margin notes, editing and saving, headings, source mode, find. Use when asked to verify, test, demo or screenshot MD Writer behavior, or before calling an MD Writer change done.
---

# Verify MD Writer

MD Writer is an AppKit app hosting a WKWebView editor (Milkdown). Users touch it through the menu bar, keyboard
shortcuts, the editor text, a review sheet, a notes panel and a status bar. There is no CLI or server to drive:
everything goes through macOS accessibility, via the `mdw` helper in `scripts/`.

All commands below run from the repo root. `mdw` is `.claude/skills/verify-md-writer/scripts/mdw`; set
`M=.claude/skills/verify-md-writer/scripts/mdw` and call `$M <command>`. `$M help` lists every command.

## Safety rules (read first)

The user usually has their own MD Writer open. Both processes are named `MDWriter`, and a mistake lands in
their documents.

- **Only drive the instance `mdw launch` started.** `mdw` stores its PID in `.verify/current` and addresses that
  process by PID, never by name. Don't use `osascript ... tell process "MDWriter"`, `open` without `-n`,
  `killall` or `pkill`: each can hit the user's instance.
- **Never send keystrokes with plain `osascript keystroke`.** Keys go to whatever app is frontmost, not to the
  process you name. `mdw keys` activates the test instance and refuses to type unless it is frontmost.
- **Prefer `mdw press`/`sheet-*`/`menu` over `mdw keys` and `mdw click`.** They act on one element by
  accessibility and need no focus. Use `keys` only for typing text, and `click` only to put the caret somewhere.
- **Don't run a review while the user's instance is reviewing.** All instances share one review work folder
  (`~/Library/Application Support/MD Writer/Review`) and one set of preferences (last reviewer and model).
  `mdw doctor` checks for a running review in other instances.
- **Reviews cost money.** Each runs `claude -p` (about $0.05 on Sonnet, more on Opus). Pick Sonnet in the
  sheet unless the model is what you're verifying.

## Launch

1. Build if the app or web sources changed since `dist/` was built: `$M build` (runs `scripts/build-app.sh`,
   about 20 s).
2. `$M launch [file.md]`. It copies the file (default `fixtures/draft.md`) into `.verify/runs/<run>/`, opens it in
   a **new** process with `-ApplePersistenceIgnoreState YES` (so the user's restored tabs don't open in it), and
   waits until the editor shows its word count. It prints the PID, the document path and the evidence folder.
3. Ready means `launch` returned without error. It refuses to start a second run while one is alive.

A running app keeps the code it started with. After `$M build`, relaunch: `$M cleanup && $M launch`.

## Doctor

`$M doctor` is read-only and exits non-zero on any failure. Run it after launch and whenever something looks
off. It checks that the PID runs this repo's `dist/` binary, that it started after the last build (else it runs
stale code), that only the run's document is open, that the editor rendered, that the Review menu exists, that
a login shell finds `claude`, and that no other MD Writer is mid-review. It also names other MD Writer PIDs so
you know they exist and leave them alone.

## Drive

Read `features/README.md`, then the feature file you need. The building blocks:

- **Read the screen**: `$M text` prints the window's visible text (editor, notes panel, status bar), with
  buttons as `[button] <label>` lines. `$M dump` prints the accessibility tree. CSS `text-transform` applies, so
  the notes panel header reads `WRITING REVIEW · SONNET 5.5 · ROUND 1`.
- **Wait**: `$M wait-text "<text>" [secs]` polls `text`. `$M wait-review [secs]` waits until the review process
  under the instance exits. Never use fixed sleeps for reviews (they take 10–60 s).
- **Menus**: `$M menu <Menu> <Item>` with the titles AppKit shows at runtime, which can differ from the source:
  `File > Save` (the code says "Save…"), `Review > Review…`, `Review > Review Again`,
  `Review > Start Fresh Review…`, `Review > Cancel Review`, `Paragraph > Heading 1`…`Heading 6`,
  `Paragraph > Paragraph`, `View > Source Code Mode`, `Edit > Find…`, `Edit > Find Next`. List a menu with
  `$M dump` or the snippet in Gotchas below. Menus need the app frontmost; `menu` activates it, and a disabled
  item fails loudly.
- **Web buttons**: `$M press AXButton "<label>"` presses the first button whose label contains the text:
  `Review` (status bar, idle), `Apply`, `Dismiss`, `✕` (closes the notes panel), `N notes` (toggles the panel).
- **The review sheet**: `$M sheet` lists its controls and values. `$M sheet-select 0 "Clarity"` (Reviewer:
  `Clarity`, `Plain writing`, `Writing review`), `$M sheet-select 1 Sonnet` (Model: `Sonnet`, `Opus`, `Fable`,
  `Haiku`), `$M sheet-note "<text>"`, `$M sheet-press Review` or `Cancel`.
- **Typing**: `$M keys "<text>" [command,shift,option,control]`, and `$M keycode <code>` for keys that can't be
  typed (53 Escape, 36 Return, 51 Delete). The caret starts at the beginning of the document after launch.

## Evidence

Each run writes to `.verify/evidence/<run>/` (gitignored). `cleanup` never deletes it.

- `$M shot <name>`: window screenshot, captured by window ID, so other windows covering it don't matter.
- `$M save-text <name>`: the visible text, for asserting on wording.
- `$M save-doc <name>`: the document file **on disk**. This is the side effect that matters for editing
  features. Save first (`$M menu File Save`); autosave timing is not something to wait on.
- `$M save-prompts <name>`: the prompts of the newest review session in
  `~/.claude/projects/-Users-<you>-Library-Application-Support-MD-Writer-Review/`. This proves what Claude was
  told (e.g. which notes were applied or dismissed).

Proof standards:

- Drive the path a user takes: the menu item, the status-bar button, the sheet. Don't call the page's JS
  (`mdw.*`) or post bridge messages; those skip the native half.
- Capture the action and the resulting state: a `text` or `shot` before and after.
- Check side effects alongside the screen: the saved file after Apply, the prompts after Review Again.
- Reviews call the real Claude. There is no mock; that boundary is exactly what's being verified.

## Cleanup

`$M cleanup` stops the run's review process (if any) and the instance by PID, then deletes
`.verify/runs/<run>/` (the scratch document). It keeps `.verify/evidence/<run>/` and prints its path. Run it
after every attempt, including failed ones, so no instance is left running. If `.verify/current` points at a
PID that is already gone, cleanup just removes the scratch folder.

## Helpers

- `scripts/mdw`: the command above (bash). `$M help` for usage.
- `scripts/ax.js`: the accessibility driver `mdw` calls (`osascript -l JavaScript scripts/ax.js <cmd> <pid> ...`).
  It walks web content explicitly because System Events' `entire contents` does not enter WKWebView.
- `scripts/window.py`: window ID lookup and real mouse clicks, run as
  `uv run -q --with pyobjc-framework-Quartz python -I scripts/window.py id <pid>`.
- `fixtures/draft.md`: a short post with known problems (stock opener, "not X, it's Y", bold `**crucial**`).
- `fixtures/empty-paragraphs.md`: a file with legacy `<br />` lines between paragraphs and list items.

## Gotchas

- The terminal app running these commands needs Accessibility and Screen Recording permission (System Settings ›
  Privacy & Security). Without them, `ax.js` errors with -1719/-1728 and screenshots come out blank.
- macOS swallows the first click on an inactive window. `mdw click` activates first; raw Quartz clicks don't.
- Listing a menu's runtime item titles:
  `osascript -l JavaScript -e "const se=Application('System Events'); const p=se.processes.byId(se.processes.whose({unixId: PID}).id()[0]); p.menuBars[0].menuBarItems.byName('File').menus[0].menuItems.name()"`
- A pop-up menu that is left open blocks accessibility access to the sheet. `sheet-select` opens and closes it in
  one go. If a run dies mid-way, `$M cleanup` and relaunch.
