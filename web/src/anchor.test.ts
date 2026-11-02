import { describe, expect, test } from "bun:test";
import { Schema, type Node } from "@milkdown/kit/prose/model";
import { anchor } from "./anchor";

const schema = new Schema({
  nodes: {
    doc: { content: "block+" },
    paragraph: { group: "block", content: "inline*" },
    text: { group: "inline" },
  },
  marks: { strong: {}, em: {}, code: {}, link: { attrs: { href: {} } } },
});

const t = (text: string, ...marks: string[]) =>
  schema.text(text, marks.map((m) => (m === "link" ? schema.marks.link.create({ href: "https://x.test" }) : schema.mark(m))));
const p = (...children: Node[]) => schema.node("paragraph", null, children);
const doc = (...paragraphs: Node[]) => schema.node("doc", null, paragraphs);

/** The document text the anchor covers. */
const covered = (d: Node, quote: string) => {
  const found = anchor(d, quote);
  return found && { text: d.textBetween(found.range.from, found.range.to), quote: found.quote };
};

describe("anchor", () => {
  const draft = doc(
    p(t("In today's world, jobs are a "), t("crucial", "strong"), t(" part of any backend.")),
    p(t("Use "), t("cron", "code"), t(" or a "), t("queue", "em"), t(", see "), t("the docs", "link"), t(".")),
    p(t("Keep snake_case names and 2 * 3 * 4 as written.")),
  );

  test("finds a plain quote", () => {
    expect(covered(draft, "part of any backend")).toEqual({ text: "part of any backend", quote: "part of any backend" });
  });

  test("finds a quote spanning bold text when Claude quotes the rendered text", () => {
    expect(covered(draft, "a crucial part")?.text).toBe("a crucial part");
  });

  test("finds a quote that includes Markdown bold syntax, and reports it as rendered", () => {
    expect(covered(draft, "jobs are a **crucial** part")).toEqual({
      text: "jobs are a crucial part",
      quote: "jobs are a crucial part",
    });
  });

  test("finds quotes with italic, code and link syntax", () => {
    expect(covered(draft, "Use `cron` or a _queue_, see [the docs](https://x.test).")?.text).toBe(
      "Use cron or a queue, see the docs.",
    );
    expect(covered(draft, "or a *queue*")?.text).toBe("or a queue");
  });

  test("leaves underscores inside words and spaced asterisks alone", () => {
    expect(covered(draft, "Keep snake_case names and 2 * 3 * 4 as written.")?.text).toBe(
      "Keep snake_case names and 2 * 3 * 4 as written.",
    );
  });

  test("returns null for a quote that is not in the document", () => {
    expect(anchor(draft, "**not here**")).toBeNull();
  });
});
