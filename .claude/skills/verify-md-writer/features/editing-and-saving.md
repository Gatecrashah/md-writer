# Editing and saving

The user edits the rendered Markdown and saves; the file on disk is plain Markdown. Empty paragraphs are
written as blank lines, and files that still contain legacy `<br />` lines open as empty paragraphs without
showing the markup.

## Sub-features

- `edit-type` typing changes the document and the word count.
- `edit-save` saves the document to its file.
- `edit-empty-paragraphs` writes empty paragraphs as blank lines, never `<br />`.
- `edit-legacy-br` opens files with `<br />` lines without showing the raw markup.

## How to get to it (user POV)

- Type in the editor.
- Press ⌘S or choose `File > Save` (autosave also saves after a pause).

## Driving it with mdw

Preconditions:

- `$M launch .claude/skills/verify-md-writer/fixtures/empty-paragraphs.md` and `$M doctor` pass.

- **Legacy file opens clean.** Run `$M dump | grep AXTextArea`. The editor text reads
  `"Empty paragraphs\nFirst paragraph.\n\none\ntwo\n\nthree\nLast.\n"`: blank lines, no `<br />`.
- **Type.** The caret starts at the beginning of the heading. Run `$M keys "X"`. `$M text` shows
  `XEmpty paragraphs`.
- **Save.** Run `$M menu File Save`, then `$M save-doc saved`. The file starts with `# XEmpty paragraphs` and
  contains no `<br />` (`grep -c "<br" .verify/evidence/<run>/saved.md` prints `0`); each former `<br />` is
  now extra blank lines.
- **Proof.** Keep `saved.md` and a `$M shot saved`.

## Gotchas

- The window title shows "— Edited" until a save; don't rely on it, read the file.
- Autosave runs on its own schedule. Always `File > Save` before `save-doc`.
- The menu item is `Save` at runtime even though the code creates "Save…".
- Several blank lines collapse into one when a saved file is reopened, and two lists separated only by blank
  lines become one list. That is Markdown, not a bug.
