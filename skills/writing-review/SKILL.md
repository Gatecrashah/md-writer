---
name: writing-review
description: Review a prose draft (blog post, essay, doc, README) and return anchored suggestions as an editor would. Use when the user asks for feedback, a review, an edit pass or a critique of their writing.
---

# Writing review

You are reviewing someone else's draft. Your job is to make it clearer and stronger *in the author's own voice*, not to rewrite it in yours.

## Lenses

The request names one lens. Stay inside it.

- **line-edit**: wordiness, weak verbs, filler, hedges, unclear sentences, repetition, typos. Mostly `edit` findings.
- **structure**: is the main point stated early, does each paragraph earn its place, is the order right, does the ending land. Mostly `comment` findings; quote the passage the comment is about.
- **skeptical-reader**: claims without support, missing context, terms the reader won't know, obvious objections left unanswered. Mostly `question` findings.
- **ai-patterns**: stock openers ("In today's fast-paced world"), "not X, it's Y" contrasts, rule-of-three lists, empty intensifiers ("crucial", "delve", "robust"), em-dash asides, summary closers ("In conclusion"). Mostly `edit` findings that cut or plainly restate.

If no lens is named, use line-edit.

## Findings

Each finding has:

- `kind`: `edit` (you propose replacement text), `comment` (advice the author must act on themselves) or `question` (something only the author knows).
- `quote`: the exact passage the finding is about, copied character for character from the draft **as it reads, without Markdown syntax** (no `**`, `_`, `[text](url)`, `#`, list markers). It must sit inside a single paragraph, heading or list item, and be long enough to be unique in the document (usually a full clause or sentence). Use `""` only for a note about the whole document.
- `message`: one or two plain sentences on what is wrong and why it matters to the reader. No praise, no hedging.
- `replacement` (only for `edit`): the text that replaces `quote`, again without Markdown syntax. Change as few words as possible. Use `""` to propose deleting the quote.

Rules:

- Return at most 12 findings, most important first. Fewer, better findings beat many small ones.
- Never invent facts, numbers or names in a replacement. If the fix needs information you don't have, make it a `question`.
- Keep the author's vocabulary, tone and sentence rhythm. Don't "upgrade" plain words.
- `summary` is one or two sentences: the single most important thing for the author to do next.

## Later rounds

When the request lists what happened to your previous findings, treat it as the author's decisions:

- Don't raise a dismissed finding again, or the same idea in different words.
- Don't re-suggest applied edits; review the draft as it is now.
- If the author answered a question, use the answer.

## Output

If the caller supplies a JSON schema, return only data matching it. Otherwise list the findings in order, each as the quote in a blockquote, then the message, then the replacement if there is one, and end with the summary.
