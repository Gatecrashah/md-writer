# Headings

The Paragraph menu turns the block under the caret into a heading of level 1–6 or back into a paragraph, in
both the rendered editor and Source Code Mode.

## Sub-features

- `heading-set` sets heading level 1–6 on the current block.
- `heading-clear` turns a heading back into a paragraph.
- `heading-source` does the same on the current line in Source Code Mode.

## How to get to it (user POV)

- Choose `Paragraph > Heading 1` … `Heading 6`, or `Paragraph > Paragraph`.
- Press ⌘1 … ⌘6, or ⌘0 for paragraph.

## Driving it with mdw

Preconditions:

- `$M launch .claude/skills/verify-md-writer/fixtures/empty-paragraphs.md` and `$M doctor` pass. The caret
  starts in the first block, the heading `Empty paragraphs` (level 1).

- **Set a level.** Run `$M menu Paragraph "Heading 3"`. `$M dump | grep AXHeading` shows
  `AXHeading "Empty paragraphs" "3"` (the second value is the level).
- **Clear.** Run `$M menu Paragraph Paragraph`. `$M has AXHeading Empty` fails: the block is a paragraph.
- **Shortcut.** Run `$M keys 2 command`. The dump shows level `"2"`.
- **Source Code Mode.** Run `$M menu View "Source Code Mode"`, `$M menu Paragraph "Heading 4"`, then
  `$M dump | grep AXTextArea`: the first line starts with `#### `.
- **Saved.** Run `$M menu File Save` and `$M save-doc heading`: the first line has the matching number of `#`.

## Gotchas

- The command acts on the block containing the caret, which is the first block right after launch. To target
  another block, place the caret with `$M click <x> <y>` (window points; read positions from a `$M shot`).
- On keyboard layouts where `/` needs Shift (e.g. Finnish), ⌘/ for Source Code Mode is handled by an app-level
  key monitor; prefer the menu item when driving.
