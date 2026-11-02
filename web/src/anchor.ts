import type { Node } from "@milkdown/kit/prose/model";

export type Range = { from: number; to: number };

/** Characters Claude may type differently from the draft. Each maps to one character, so offsets survive. */
export const normalize = (s: string) =>
  s.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/ /g, " ");

/** Stands in for an inline non-text node (image, hard break) when matching text. */
export const OBJECT = "￼";

/** Finds `quote` inside a single textblock and returns its document range. */
export function locate(doc: Node, quote: string): Range | null {
  const needle = normalize(quote);
  let found: Range | null = null;
  doc.descendants((node, pos) => {
    if (found) return false;
    if (!node.isTextblock) return true;
    let text = "";
    const at: number[] = [];
    node.forEach((child, offset) => {
      const start = pos + 1 + offset;
      const chunk = child.isText ? child.text! : OBJECT;
      for (let i = 0; i < chunk.length; i++) at.push(start + i);
      text += chunk;
    });
    const i = normalize(text).indexOf(needle);
    if (i >= 0) found = { from: at[i], to: at[i + needle.length - 1] + 1 };
    return false;
  });
  return found;
}

/**
 * Removes inline Markdown syntax, leaving the text a reader sees: `**bold**`, `__bold__`, `*em*`, `_em_`,
 * `~~strike~~`, `` `code` ``, `[text](url)` and `![alt](src)`. Underscores inside words and asterisks
 * surrounded by spaces are left alone.
 */
export function stripInlineMarkdown(s: string): string {
  return s
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/(\*\*|__|~~)(?=\S)(.+?)(?<=\S)\1/g, "$2")
    .replace(/\*(?=\S)(.+?)(?<=\S)\*/g, "$1")
    .replace(/(?<![\p{L}\p{N}])_(?=\S)(.+?)(?<=\S)_(?![\p{L}\p{N}])/gu, "$1");
}

/**
 * Finds a finding's quote in the document. Reviewers are told to quote the text as it reads, but sometimes
 * copy Markdown syntax from the source they were given, so a quote that isn't found is retried without it.
 * Returns the range and the quote as it reads in the document, which callers should use from then on (for
 * display and for checking the passage before applying).
 */
export function anchor(doc: Node, quote: string): { range: Range; quote: string } | null {
  for (const candidate of new Set([quote, stripInlineMarkdown(quote)])) {
    const range = locate(doc, candidate);
    if (range) return { range, quote: candidate };
  }
  return null;
}
