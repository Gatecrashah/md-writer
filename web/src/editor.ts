import { Crepe } from "@milkdown/crepe";
import { size } from "@floating-ui/dom";
import { callCommand } from "@milkdown/kit/utils";
import { undoCommand, redoCommand } from "@milkdown/kit/plugin/history";
import { wrapInHeadingCommand } from "@milkdown/kit/preset/commonmark";
import { remarkStringifyOptionsCtx } from "@milkdown/kit/core";
import { imageBlockSchema } from "@milkdown/kit/component/image-block";
import "@milkdown/crepe/theme/common/style.css";
import "@milkdown/crepe/theme/frame.css";

/** Messages sent to the native side through the `mdw` script message handler. */
type ToNative =
  | { type: "ready" }
  | { type: "changed"; markdown: string }
  | { type: "openURL"; url: string }
  | { type: "saveImage"; id: number; name: string; base64: string };

declare global {
  interface Window {
    webkit?: { messageHandlers: { mdw: { postMessage(m: ToNative): void } } };
    mdw: typeof api;
  }
}

const post = (m: ToNative) => window.webkit?.messageHandlers.mdw.postMessage(m);

const editorRoot = document.getElementById("editor")!;
const source = document.getElementById("source") as HTMLTextAreaElement;
const countEl = document.getElementById("count")!;
const modeEl = document.getElementById("mode")!;
const findBar = document.getElementById("findbar")!;
const findInput = document.getElementById("find") as HTMLInputElement;
const findInfo = document.getElementById("findinfo")!;

let crepe: Crepe | null = null;
let baseDir: string | null = null;
let sourceMode = false;
let pendingImages = new Map<number, (path: string) => void>();
let nextImageId = 1;

const hasScheme = (url: string) => /^[a-z][a-z0-9+.-]*:/i.test(url);

function resolveLocal(url: string): string {
  if (!url || hasScheme(url) || url.startsWith("#")) return url;
  if (url.startsWith("/")) return "file://" + encodeURI(url);
  if (!baseDir) return url;
  return new URL(url, "file://" + encodeURI(baseDir) + "/").href;
}

function updateCount(markdown: string) {
  const words = markdown.match(/[\p{L}\p{N}]+(?:['’-][\p{L}\p{N}]+)*/gu)?.length ?? 0;
  countEl.textContent = `${words} ${words === 1 ? "word" : "words"}`;
}

async function blobToBase64(file: Blob): Promise<string> {
  const buf = new Uint8Array(await file.arrayBuffer());
  let bin = "";
  for (let i = 0; i < buf.length; i += 0x8000) {
    bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  }
  return btoa(bin);
}

async function uploadImage(file: File): Promise<string> {
  if (!baseDir) {
    return `data:${file.type};base64,${await blobToBase64(file)}`;
  }
  const id = nextImageId++;
  const base64 = await blobToBase64(file);
  return new Promise((resolve) => {
    pendingImages.set(id, resolve);
    post({ type: "saveImage", id, name: file.name || "image.png", base64 });
  });
}

/** Shrinks the slash menu's item list so the whole menu fits on screen on whichever side it opens. */
const fitSlashMenu = size({
  padding: 8,
  apply({ availableHeight, elements }) {
    const list = elements.floating.querySelector<HTMLElement>(".menu-groups");
    if (!list) return;
    const chrome = elements.floating.offsetHeight - list.offsetHeight;
    list.style.maxHeight = `${Math.max(120, Math.min(420, availableHeight - chrome))}px`;
  },
});

async function mountEditor(markdown: string) {
  await crepe?.destroy();
  editorRoot.innerHTML = "";
  crepe = new Crepe({
    root: editorRoot,
    defaultValue: markdown,
    features: { [Crepe.Feature.AI]: false, [Crepe.Feature.TopBar]: false },
    featureConfigs: {
      [Crepe.Feature.ImageBlock]: { proxyDomURL: resolveLocal, onUpload: uploadImage },
      [Crepe.Feature.Placeholder]: { text: "Start writing…", mode: "doc" },
      [Crepe.Feature.BlockEdit]: { slashMenu: { middleware: [fitSlashMenu] } },
    },
  });
  crepe.editor.config((ctx) => {
    ctx.update(remarkStringifyOptionsCtx, (o) => ({ ...o, bullet: "-" as const }));
    // Upstream stores the resize ratio in the alt text; keep the real alt text instead.
    ctx.update(imageBlockSchema.key, (prev) => (ctx) => {
      const base = prev(ctx);
      return {
        ...base,
        attrs: { ...base.attrs, alt: { default: "", validate: "string" } },
        parseMarkdown: {
          match: ({ type }) => type === "image-block",
          runner: (state, node, type) => {
            state.addNode(type, {
              src: node.url as string,
              caption: (node.title as string | null) ?? "",
              alt: (node.alt as string | null) ?? "",
            });
          },
        },
        toMarkdown: {
          match: (node) => node.type.name === "image-block",
          runner: (state, node) => {
            state.openNode("paragraph");
            state.addNode("image", undefined, undefined, {
              title: node.attrs.caption || null,
              url: node.attrs.src,
              alt: node.attrs.alt,
            });
            state.closeNode();
          },
        },
      };
    });
  });
  crepe.on((l) =>
    l.markdownUpdated((_ctx, md, prev) => {
      if (md === prev) return;
      updateCount(md);
      post({ type: "changed", markdown: md });
    }),
  );
  await crepe.create();
  updateCount(markdown);
  editorRoot.querySelector<HTMLElement>(".ProseMirror")?.focus();
}

async function setSourceMode(on: boolean) {
  if (on === sourceMode) return;
  sourceMode = on;
  if (on) {
    source.value = crepe?.getMarkdown() ?? "";
    await crepe?.destroy();
    crepe = null;
    editorRoot.hidden = true;
    source.hidden = false;
    source.focus();
    source.setSelectionRange(0, 0);
  } else {
    source.hidden = true;
    editorRoot.hidden = false;
    await mountEditor(source.value);
  }
  modeEl.textContent = on ? "Source" : "";
}

source.addEventListener("input", () => {
  updateCount(source.value);
  post({ type: "changed", markdown: source.value });
});

source.addEventListener("keydown", (e) => {
  if (e.key !== "Tab") return;
  e.preventDefault();
  document.execCommand("insertText", false, "\t");
});

let matches: Range[] = [];
let current = -1;
const matchHighlight = new Highlight();
const currentHighlight = new Highlight();
CSS.highlights.set("find-match", matchHighlight);
CSS.highlights.set("find-current", currentHighlight);

function clearHighlights() {
  matchHighlight.clear();
  currentHighlight.clear();
}

function collectMatches(q: string): Range[] {
  const root = editorRoot.querySelector(".ProseMirror");
  if (!root || !q) return [];
  const needle = q.toLowerCase();
  const ranges: Range[] = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const text = n.textContent!.toLowerCase();
    for (let i = text.indexOf(needle); i >= 0; i = text.indexOf(needle, i + needle.length)) {
      const r = document.createRange();
      r.setStart(n, i);
      r.setEnd(n, i + needle.length);
      ranges.push(r);
    }
  }
  return ranges;
}

function showMatch() {
  clearHighlights();
  matches.forEach((r) => matchHighlight.add(r));
  if (current < 0) return;
  currentHighlight.add(matches[current]);
  matches[current].startContainer.parentElement?.scrollIntoView({ block: "center" });
}

function showFind() {
  findBar.hidden = false;
  const selected = sourceMode
    ? source.value.slice(source.selectionStart, source.selectionEnd)
    : getSelection()?.toString() ?? "";
  if (selected && !selected.includes("\n")) findInput.value = selected;
  findInput.focus();
  findInput.select();
  refreshMatches();
}

function refreshMatches() {
  findInfo.textContent = "";
  if (sourceMode) return;
  matches = collectMatches(findInput.value);
  current = -1;
  showMatch();
  if (findInput.value) findInfo.textContent = matches.length ? `${matches.length} found` : "Not found";
}

function hideFind() {
  findBar.hidden = true;
  clearHighlights();
  if (sourceMode) return source.focus();
  const pm = editorRoot.querySelector<HTMLElement>(".ProseMirror");
  pm?.focus();
  if (current >= 0) {
    getSelection()?.removeAllRanges();
    getSelection()?.addRange(matches[current]);
  }
}

function findNext(backwards = false) {
  const q = findInput.value;
  if (findBar.hidden || !q) return showFind();
  if (sourceMode) {
    const text = source.value.toLowerCase();
    const needle = q.toLowerCase();
    let at = backwards
      ? text.lastIndexOf(needle, source.selectionStart - 1)
      : text.indexOf(needle, source.selectionEnd);
    if (at < 0) at = backwards ? text.lastIndexOf(needle) : text.indexOf(needle);
    findInfo.textContent = at >= 0 ? "" : "Not found";
    if (at >= 0) {
      source.focus();
      source.setSelectionRange(at, at + q.length);
    }
    return;
  }
  if (!matches.length) return;
  current = (current + (backwards ? -1 : 1) + matches.length) % matches.length;
  findInfo.textContent = `${current + 1} of ${matches.length}`;
  showMatch();
}

findInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    findNext(e.shiftKey);
    findInput.focus();
  } else if (e.key === "Escape") {
    hideFind();
  }
});
findInput.addEventListener("input", refreshMatches);

document.addEventListener("click", (e) => {
  const a = (e.target as Element).closest?.("a[href]");
  if (!a || !(e.metaKey || !a.closest(".ProseMirror"))) return;
  e.preventDefault();
  post({ type: "openURL", url: resolveLocal(a.getAttribute("href")!) });
});

const api = {
  async load(markdown: string, dir: string | null) {
    baseDir = dir;
    if (sourceMode) {
      source.value = markdown;
      updateCount(markdown);
    } else {
      await mountEditor(markdown);
    }
  },
  setBaseDir(dir: string | null) {
    baseDir = dir;
  },
  toggleSourceMode() {
    return setSourceMode(!sourceMode);
  },
  undo() {
    if (sourceMode) document.execCommand("undo");
    else crepe?.editor.action(callCommand(undoCommand.key));
  },
  redo() {
    if (sourceMode) document.execCommand("redo");
    else crepe?.editor.action(callCommand(redoCommand.key));
  },
  /** Turns the current block into a heading of `level` (1–6), or a paragraph for 0. */
  setHeading(level: number) {
    if (!sourceMode) {
      crepe?.editor.action(callCommand(wrapInHeadingCommand.key, level));
      return;
    }
    const start = source.value.lastIndexOf("\n", source.selectionStart - 1) + 1;
    const prefix = /^#{1,6}[ \t]+/.exec(source.value.slice(start))?.[0] ?? "";
    source.focus();
    source.setSelectionRange(start, start + prefix.length);
    document.execCommand("insertText", false, level > 0 ? "#".repeat(level) + " " : "");
  },
  showFind,
  findNext: () => findNext(false),
  findPrevious: () => findNext(true),
  imageSaved(id: number, path: string) {
    pendingImages.get(id)?.(path);
    pendingImages.delete(id);
  },
};

window.mdw = api;
post({ type: "ready" });
