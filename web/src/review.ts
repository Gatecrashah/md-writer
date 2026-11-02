import { $prose } from "@milkdown/kit/utils";
import { Plugin, PluginKey, type EditorState } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet, type EditorView } from "@milkdown/kit/prose/view";
import type { Node } from "@milkdown/kit/prose/model";

/** A finding as the native side sends it; `id` is unique across review rounds. */
export type Finding = {
  id: string;
  kind: "edit" | "comment" | "question";
  quote: string;
  message: string;
  replacement?: string;
};
/** `modelID` is the exact model that wrote the review, e.g. `claude-opus-5-5`, when Claude Code reports it. */
export type Review = { summary: string; label: string; modelID: string | null; findings: Finding[] };
export type ReviewOutcome = "applied" | "dismissed";

type Range = { from: number; to: number };
type Anchors = Map<string, Range>;
type Meta = { anchors: Anchors } | { remove: string } | { active: string | null };
type PluginState = { anchors: Anchors; active: string | null };

const key = new PluginKey<PluginState>("review");

/** Characters Claude may type differently from the draft. Each maps to one character, so offsets survive. */
const normalize = (s: string) =>
  s.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/ /g, " ");

const OBJECT = "￼";

/** Finds `quote` inside a single textblock and returns its document range. */
function locate(doc: Node, quote: string): Range | null {
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

const textAt = (state: EditorState, r: Range) => normalize(state.doc.textBetween(r.from, r.to, OBJECT, OBJECT));

let review: Review | null = null;
let view: EditorView | null = null;
let onOutcome: (id: string, outcome: ReviewOutcome) => void = () => {};
let panelOpen = false;
let running: { started: number; timer: number } | null = null;

const panel = document.getElementById("notes")!;
const statusEl = document.getElementById("review")!;

const anchors = (): Anchors => (view ? key.getState(view.state)!.anchors : new Map());
const activeId = () => (view ? key.getState(view.state)!.active : null);

function dispatch(meta: Meta) {
  if (view) view.dispatch(view.state.tr.setMeta(key, meta));
}

export const reviewPlugin = $prose(
  () =>
    new Plugin<PluginState>({
      key,
      state: {
        init: () => ({ anchors: new Map(), active: null }),
        apply(tr, prev) {
          const meta = tr.getMeta(key) as Meta | undefined;
          if (meta && "anchors" in meta) return { anchors: meta.anchors, active: null };
          if (meta && "active" in meta) return { ...prev, active: meta.active };
          if (!tr.docChanged && !meta) return prev;
          const next: Anchors = new Map();
          for (const [id, r] of prev.anchors) {
            if (meta && "remove" in meta && meta.remove === id) continue;
            const from = tr.mapping.map(r.from, 1);
            const to = tr.mapping.map(r.to, -1);
            if (from < to) next.set(id, { from, to });
          }
          return { anchors: next, active: prev.active };
        },
      },
      props: {
        decorations(state) {
          const { anchors, active } = key.getState(state)!;
          return DecorationSet.create(
            state.doc,
            [...anchors].map(([id, r]) =>
              Decoration.inline(r.from, r.to, {
                class: id === active ? "review-mark active" : "review-mark",
                "data-review": id,
              }),
            ),
          );
        },
        handleClick(view, pos) {
          for (const [id, r] of key.getState(view.state)!.anchors) {
            if (pos >= r.from && pos <= r.to) {
              activate(id, false);
              break;
            }
          }
          return false;
        },
      },
      view(v) {
        view = v;
        // Dispatching while the view is still being constructed is not allowed.
        queueMicrotask(anchorAll);
        return {
          update: (_v, prevState) => {
            if (key.getState(v.state) !== key.getState(prevState)) render();
          },
          destroy: () => {
            view = null;
            render();
          },
        };
      },
    }),
);

/** Anchors every finding against the current document; findings whose quote is gone are left unanchored. */
function anchorAll() {
  if (!view || !review) return render();
  const next: Anchors = new Map();
  for (const f of review.findings) {
    const r = f.quote ? locate(view.state.doc, f.quote) : null;
    if (r) next.set(f.id, r);
  }
  dispatch({ anchors: next });
}

function resolve(id: string, outcome: ReviewOutcome) {
  if (!review) return;
  review.findings = review.findings.filter((f) => f.id !== id);
  onOutcome(id, outcome);
  if (anchors().has(id)) dispatch({ remove: id });
  render();
}

function apply(f: Finding) {
  const r = anchors().get(f.id);
  if (!view || !r) return;
  if (textAt(view.state, r) !== normalize(f.quote)) {
    // The author edited the passage after the review; applying would overwrite their change.
    dispatch({ remove: f.id });
    return;
  }
  view.dispatch(view.state.tr.insertText(f.replacement ?? "", r.from, r.to).setMeta(key, { remove: f.id }));
  resolve(f.id, "applied");
  view.focus();
}

function activate(id: string, scrollEditor: boolean) {
  setPanel(true);
  dispatch({ active: id });
  panel.querySelector(`[data-card="${CSS.escape(id)}"]`)?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  const r = anchors().get(id);
  if (scrollEditor && view && r) {
    const node = view.domAtPos(r.from).node;
    (node instanceof Element ? node : node.parentElement)?.scrollIntoView({ block: "center", behavior: "smooth" });
  }
}

function setPanel(open: boolean) {
  panelOpen = open && !!review;
  document.body.classList.toggle("notes-open", panelOpen);
  panel.hidden = !panelOpen;
  renderStatus();
}

function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls: string, text?: string) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function button(label: string, primary: boolean, onClick: () => void) {
  const b = el("button", primary ? "btn primary" : "btn", label);
  b.type = "button";
  b.addEventListener("click", (e) => {
    e.stopPropagation();
    onClick();
  });
  return b;
}

const KIND_LABEL = { edit: "Edit", comment: "Comment", question: "Question" } as const;

function card(f: Finding, anchored: boolean, active: boolean) {
  const stale = !!f.quote && !anchored;
  const c = el("article", `card ${f.kind}${active ? " active" : ""}${stale ? " stale" : ""}`);
  c.dataset.card = f.id;
  c.append(el("span", "chip", KIND_LABEL[f.kind]));
  if (f.quote && f.kind !== "edit") c.append(el("blockquote", "quote", f.quote));
  c.append(el("p", "message", f.message));
  if (f.kind === "edit" && f.replacement !== undefined) {
    const diff = el("p", "diff");
    diff.append(el("del", "", f.quote));
    if (f.replacement) diff.append(" ", el("ins", "", f.replacement));
    c.append(diff);
  }
  const actions = el("div", "actions");
  if (stale) {
    c.append(el("p", "stale-note", view ? "This text changed after the review." : "Switch back from Source Code Mode to see this note in the text."));
  } else if (f.kind === "edit" && f.replacement !== undefined) {
    actions.append(button("Apply", true, () => apply(f)));
  }
  actions.append(button("Dismiss", false, () => resolve(f.id, "dismissed")));
  c.append(actions);
  if (anchored) c.addEventListener("click", () => activate(f.id, true));
  return c;
}

function render() {
  renderStatus();
  if (!review) return;
  const a = anchors();
  const active = activeId();
  const order = (f: Finding) => (!f.quote ? -1 : (a.get(f.id)?.from ?? Number.MAX_SAFE_INTEGER));
  const findings = [...review.findings].sort((x, y) => order(x) - order(y));

  const head = el("header", "notes-head");
  const label = el("span", "notes-label", review.label);
  if (review.modelID) label.title = review.modelID;
  head.append(label, button("✕", false, () => setPanel(false)));
  const body: HTMLElement[] = [head, el("p", "summary", review.summary)];
  body.push(...findings.map((f) => card(f, a.has(f.id), f.id === active)));
  if (!findings.length) body.push(el("p", "done", "All notes resolved. Review Again (⌥⌘R) for another pass."));
  panel.replaceChildren(...body);
}

function renderStatus() {
  statusEl.replaceChildren();
  if (running) {
    const s = Math.floor((Date.now() - running.started) / 1000);
    statusEl.append(`Reviewing… ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")} `, el("span", "cancel", "✕"));
    statusEl.title = "Cancel review";
  } else if (review) {
    const n = review.findings.length;
    statusEl.textContent = `${n} ${n === 1 ? "note" : "notes"}`;
    statusEl.title = panelOpen ? "Hide notes" : "Show notes";
  } else {
    statusEl.textContent = "Review";
    statusEl.title = "Review this draft (⇧⌘R)";
  }
}

export function initReview(handlers: { request(): void; cancel(): void; outcome(id: string, o: ReviewOutcome): void }) {
  onOutcome = handlers.outcome;
  statusEl.addEventListener("click", () => {
    if (running) handlers.cancel();
    else if (review) setPanel(!panelOpen);
    else handlers.request();
  });
  renderStatus();
}

export function reviewStarted() {
  if (running) clearInterval(running.timer);
  running = { started: Date.now(), timer: window.setInterval(renderStatus, 1000) };
  renderStatus();
}

export function reviewEnded() {
  if (running) clearInterval(running.timer);
  running = null;
  renderStatus();
}

export function showReview(next: Review) {
  reviewEnded();
  review = next;
  anchorAll();
  setPanel(true);
}
