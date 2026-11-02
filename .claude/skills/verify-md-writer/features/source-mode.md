# Source Code Mode

The user switches between the rendered editor and a plain text view of the Markdown source, and back, without
losing edits made in either.

## Sub-features

- `source-on` shows the raw Markdown and a `Source` label in the status bar.
- `source-edit` edits made in source appear in the rendered editor after switching back.
- `source-off` returns to the rendered editor.

## How to get to it (user POV)

- Choose `View > Source Code Mode`.
- Press ⌘/ (also on layouts where `/` needs Shift).

## Driving it with mdw

Preconditions:

- `$M launch` and `$M doctor` pass.

- **Turn on.** Run `$M menu View "Source Code Mode"`, then `$M wait-text Source 5`. `$M dump | grep AXTextArea`
  shows the Markdown with syntax, e.g. `## Why we moved off cron` and `**crucial**`.
- **Edit in source.** The caret is at the start of the text. Run `$M keys "Hello. "`.
- **Turn off.** Run `$M menu View "Source Code Mode"`. `$M has AXStaticText Source` fails, and `$M text` shows
  `Hello.` in the rendered editor.
- **Proof.** `$M save-text source-roundtrip` and `$M shot source-roundtrip`.

## Gotchas

- The rendered editor is rebuilt when leaving source mode, which re-anchors any review notes; notes whose
  passage changed become stale.
- Review highlights are not shown in source mode, and `Apply` is not available there.
