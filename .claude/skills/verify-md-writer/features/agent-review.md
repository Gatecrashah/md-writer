# Agent review

The user asks Claude to review the open draft. A sheet picks the reviewer skill, the model and an optional
note; Claude runs in the background while the status bar counts up; the findings appear as notes in a right
panel, each highlighted in the text. Edit notes can be applied, any note dismissed, and a later round continues
the same Claude session knowing what the user did.

## Sub-features

- `review-request` opens the review sheet from every entry point.
- `review-sheet` chooses reviewer (Clarity, Plain writing, Writing review), model and note; remembers the last
  choice.
- `review-run` runs in the background with a live status, then shows notes; the header names the reviewer,
  the exact model in readable form, and the round.
- `review-notes` shows each note anchored to its passage; a note whose passage no longer matches says so.
- `review-apply` replaces the passage with the suggested text and removes the note.
- `review-dismiss` removes a note without changing the text.
- `review-again` runs another round in the same session, telling Claude what was applied, dismissed or left
  open.
- `review-fresh` starts a new session; changing the reviewer also does.
- `review-cancel` stops a running review.
- `review-panel` hides and shows the notes panel.

## How to get to it (user POV)

- Press ⇧⌘R or choose `Review > Review…`.
- Click `Review` in the status bar (bottom right) when no review exists yet.
- Press ⌥⌘R or choose `Review > Review Again` for the next round (skips the sheet).
- Choose `Review > Start Fresh Review…` to drop the session.
- Click `Reviewing… 0:07 ✕` in the status bar, or choose `Review > Cancel Review`, to cancel.
- Click `N notes` in the status bar, or the panel's `✕`, to toggle the panel.

## Driving it with mdw

Preconditions:

- `$M launch` (default `fixtures/draft.md`) and `$M doctor` pass, including the `claude` and
  no-other-review checks.

- **Open the sheet (status bar).** Press the idle status button. Run `$M press AXButton Review`. `$M sheet`
  lists `AXPopUpButton | <reviewer>`, `AXPopUpButton | <model>`, a text field and the `Cancel`/`Review` buttons.
- **Open the sheet (menu).** Cancel with `$M sheet-press Cancel`, then run `$M menu Review "Review…"`. The same
  sheet opens. (⇧⌘R is the same menu item; `$M keys r command,shift` drives it.)
- **Choose and start.** Run `$M sheet-select 0 "Writing review"`, `$M sheet-select 1 Sonnet`, optionally
  `$M sheet-note "for a non-technical audience"`, then `$M sheet-press Review`. `$M wait-text "Reviewing" 10`
  finds `[button] Reviewing… 0:0N ✕`.
- **Wait for notes.** Run `$M wait-review`, then `$M save-text round1`. The text has
  `WRITING REVIEW · SONNET 5.5 · ROUND 1`, a summary line, notes headed `EDIT`, `COMMENT` or `QUESTION`, their
  `[button] Apply`/`[button] Dismiss`, and the status `[button] N notes`. Take `$M shot round1`.
- **Apply.** Run `$M press AXButton Apply`. The status count drops by one (`$M has AXButton "notes"`). Run
  `$M menu File Save` and `$M save-doc after-apply`: the file contains that note's replacement text.
- **Dismiss.** Run `$M press AXButton Dismiss`. The count drops by one; the document is unchanged.
- **Review again.** Run `$M menu Review "Review Again"`, `$M wait-review`, `$M wait-text "ROUND 2" 5`. Run
  `$M save-prompts rounds`: the last prompt lists `- Applied: …`, `- Dismissed: …` and `- Left open: …` lines
  matching what you did.
- **Fresh review.** Run `$M menu Review "Start Fresh Review…"`, pick a different reviewer with
  `$M sheet-select 0 Clarity`, `$M sheet-press Review`, `$M wait-review`. The header reads
  `CLARITY · … · ROUND 1`, and `save-prompts` shows a new session ID with no outcome lines.
- **Cancel.** Start a review, then while `Reviewing` is visible run `$M menu Review "Cancel Review"`. The status
  returns to its previous state within a second, `$M wait-review 5` succeeds, and no error sheet appears.
- **Panel toggle.** Run `$M press AXButton "notes"`. `$M has AXButton Dismiss` now fails; press it again and
  the notes return.
- **Proof.** Keep `round1.txt`, `round1.png`, `after-apply.md` and `rounds.prompts.txt` from the run's evidence
  folder.

## Gotchas

- `Review > Review…`, `Review Again` and `Start Fresh Review…` are disabled while a review runs; `menu` fails
  on a disabled item. `Cancel Review` is disabled when nothing runs.
- `Review Again` without an earlier round opens the sheet instead of running.
- The reviewer and model you pick are saved to the shared preferences, so the user's next sheet opens with your
  choice. Restore their usual pick if you know it.
- Reviewers sometimes quote Markdown syntax (`**crucial**`); such notes must still anchor and apply without
  leaving `**` in the file. To force that path, set the sheet's note to "Quote passages exactly as written in
  the Markdown source, including the ** markers around bold words." On an untouched document, "This text
  changed after the review." means a quote failed to anchor: that is a bug.
- `Apply` refuses (the note turns stale) when the highlighted passage was edited after the review. To test
  that, type into the highlighted passage with `$M click` then `$M keys` before pressing `Apply`.
- Review output varies between runs. Assert on structure (header, note kinds, counts, outcome lines), not on
  Claude's wording.
- A review takes 10–60 s; `wait-review` defaults to 240 s.
