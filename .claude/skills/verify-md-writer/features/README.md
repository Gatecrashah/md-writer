# MD Writer verification map

This directory is the maintained source for verifying what an MD Writer user can do. Read this index, then use
the matching feature file as the recipe. `$M` is `.claude/skills/verify-md-writer/scripts/mdw`, run from the
repo root.

## Baseline preconditions

- `dist/MD Writer.app` is built from the code under test (`$M build`).
- A run is started with `$M launch [fixture]` and `$M doctor` passes. Fixtures live in
  `.claude/skills/verify-md-writer/fixtures/`; the default is `draft.md`.
- The run's document is a scratch copy in `.verify/runs/<run>/`. Never open the user's own documents.
- Never drive an MD Writer process this run did not start. The user's instance has the same process name.

## Driving conventions

- Prefer accessibility actions that need no focus: `$M press`, `$M sheet-*`. Then `$M menu`. Use `$M keys` only
  to type text, and `$M click` only to place the caret.
- Use runtime menu titles exactly as written in the recipes (`File > Save`, not "Save…").
- Wait on observable state (`$M wait-text`, `$M wait-review`), not fixed sleeps.
- For editing features, save with `$M menu File Save` before reading the file on disk.
- Choose `Sonnet` in the review sheet unless the model itself is under test; reviews call the real Claude.

## Proof and skip reporting

- Capture the user action and the resulting state: `$M save-text` or `$M shot` before and after.
- Editing proof includes the saved file (`$M save-doc`), not just the screen.
- Review proof includes the panel text and, for later rounds, the prompts Claude received (`$M save-prompts`).
- Name the feature ID and entry point with each artifact.
- An entry point you could not reach is reported as skipped, with the command tried and the unmet
  precondition. Don't report it as verified through a different entry point.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior, then exactly
four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with mdw` (starting
with `Preconditions:` and labeled bullets pairing each action with a command and its observable result), and
`Gotchas`.

## Features

- [Agent review](./agent-review.md) covers requesting a review, choosing reviewer and model, notes, Apply,
  Dismiss, Review Again, Start Fresh Review and Cancel Review.
- [Editing and saving](./editing-and-saving.md) covers typing, saving to disk and how empty paragraphs are
  written.
- [Headings](./headings.md) covers the Paragraph menu and its ⌘0–⌘6 shortcuts.
- [Source Code Mode](./source-mode.md) covers switching between the rendered editor and raw Markdown.
- [Find](./find.md) covers the find bar, match counts and stepping through matches.
