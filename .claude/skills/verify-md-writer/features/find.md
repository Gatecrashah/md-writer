# Find

A find bar at the top right searches the document as the user types, shows how many matches there are, and
steps through them.

## Sub-features

- `find-open` opens the find bar, prefilled with a single-line selection.
- `find-count` shows `N found` or `Not found` while typing.
- `find-step` steps forward and back through matches as `i of N`.
- `find-close` closes the bar with Escape.

## How to get to it (user POV)

- Choose `Edit > Find…` or press ⌘F.
- Choose `Edit > Find Next` / `Find Previous`, press ⌘G / ⇧⌘G, or Return / Shift-Return in the field.
- Press Escape in the field to close.

## Driving it with mdw

Preconditions:

- `$M launch .claude/skills/verify-md-writer/fixtures/empty-paragraphs.md` and `$M doctor` pass.

- **Open.** Run `$M menu Edit "Find…"`. `$M dump | grep AXTextField` shows the empty find field.
- **Count.** Run `$M keys "t"`. `$M text` contains `5 found`. Run `$M keys "zzz"`: it shows `Not found`.
- **Step.** Clear and retype with `$M keys a command` then `$M keys "t"`, then `$M menu Edit "Find Next"`.
  `$M text` contains `1 of 5`; a second `Find Next` shows `2 of 5`.
- **Close.** Run `$M keycode 53` (Escape). The `AXTextField` is gone from the dump.
- **Proof.** `$M save-text find` and `$M shot find` while `1 of 5` is visible.

## Gotchas

- Match counts come from the rendered text, so Markdown syntax (`#`, `**`) is not matched.
- In Source Code Mode, find selects matches in the text area and shows no count.
- `keys` types into whatever has focus in the instance; open the bar first so the text goes into the field.
- `keys` can't send Escape or Return; use `$M keycode 53` / `$M keycode 36`.
