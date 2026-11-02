// Accessibility driver for ONE MD Writer process, addressed by PID. Called by `mdw`; run directly as:
//   osascript -l JavaScript ax.js <command> <pid> [args...]
//
// Reading (works in the background, no focus needed):
//   dump <pid> [maxDepth]           front window's tree: indent, role, then name/description/value
//   text <pid>                      visible text (AXStaticText values, and "[button] label" lines)
//   has <pid> <role> <text>         exit 0 and print the match if an element of <role> contains <text>
//   windows <pid>                   window titles, one per line
//   sheet <pid>                     the open sheet's controls as "role | value" lines; exit 1 if no sheet
//   menu-state <pid> <menu> <item>  "enabled" or "disabled"
// Acting:
//   press <pid> <role> <text>       AXPress the first matching element (web buttons too; no mouse or focus)
//   sheet-select <pid> <popupIndex> <title>   choose <title> in the sheet's Nth pop-up button (0-based)
//   sheet-note <pid> <text>         set the sheet's text field
//   sheet-press <pid> <title>       press a sheet button ("Review", "Cancel")
//   menu <pid> <menu> <item>        activate this instance, then choose a menu-bar item; fails if disabled
//   keys <pid> <text> [mods]        activate this instance and type; mods: comma list of command,shift,option,control
//   keycode <pid> <code> [mods]     same, for keys `keys` can't type (53 Escape, 36 Return, 51 Delete)
//   raise <pid>                     activate this instance and raise its front window
//
// Targeting: the process is resolved to System Events' own unique id and used via processes.byId(), never by
// name: the user's MD Writer and test instances share the name "MDWriter". `keys` refuses to type unless this
// PID is frontmost at the moment of typing, because keystrokes go to whatever app is frontmost.

ObjC.import("stdlib");

function run(argv) {
  const [cmd, pidArg, ...rest] = argv;
  const pid = Number(pidArg);
  const se = Application("System Events");
  const ids = se.processes.whose({ unixId: pid }).id();
  if (ids.length === 0) fail(`no process with pid ${pidArg}`);
  const proc = se.processes.byId(ids[0]);
  const win = () => {
    if (proc.windows.length === 0) fail("process has no windows");
    return proc.windows[0];
  };

  const attr = (el, name) => {
    try {
      const v = el[name]();
      return v === null || v === undefined ? "" : String(v);
    } catch (e) {
      return "";
    }
  };
  const label = (el) =>
    [attr(el, "name"), attr(el, "description"), attr(el, "value")].filter((s) => s && s !== "missing value");

  // System Events' `entire contents` does not descend into WKWebView content, so walk children explicitly.
  function walk(el, depth, max, visit) {
    if (visit(el, depth) === false) return false;
    if (depth >= max) return true;
    let kids = [];
    try {
      kids = el.uiElements();
    } catch (e) {}
    for (const k of kids) if (walk(k, depth + 1, max, visit) === false) return false;
    return true;
  }
  function find(role, text) {
    let found = null;
    walk(win(), 0, 40, (el) => {
      if (attr(el, "role") === role && label(el).some((s) => s.includes(text))) {
        found = el;
        return false;
      }
    });
    return found;
  }
  function activate() {
    proc.frontmost = true;
    for (let i = 0; i < 20 && !isFront(); i++) delay(0.1);
    if (!isFront()) fail(`pid ${pid} did not become frontmost`);
  }
  function isFront() {
    return se.processes.whose({ frontmost: true }).unixId()[0] === pid;
  }
  function sheet() {
    const w = win();
    if (w.sheets.length === 0) fail("no sheet is open");
    return w.sheets[0];
  }
  const press = (el) => el.actions.byName("AXPress").perform();

  switch (cmd) {
    case "dump": {
      const out = [];
      walk(win(), 0, Number(rest[0] || 40), (el, d) => {
        out.push(`${"  ".repeat(d)}${attr(el, "role")} ${label(el).map((s) => JSON.stringify(s.slice(0, 80))).join(" ")}`);
      });
      return out.join("\n");
    }
    case "text": {
      // Buttons are included because web elements with role="button" (the status-bar review item) expose
      // their text only as the button's label.
      const out = [];
      walk(win(), 0, 40, (el) => {
        const role = attr(el, "role");
        if (role === "AXStaticText") out.push(attr(el, "value"));
        else if (role === "AXButton") out.push(`[button] ${label(el).join(" ")}`);
      });
      return out.join("\n");
    }
    case "windows":
      return proc.windows.name().join("\n");
    case "has":
    case "press": {
      const el = find(rest[0], rest[1]);
      if (!el) fail(`no ${rest[0]} containing ${JSON.stringify(rest[1])}`);
      // Read the label first: pressing can remove the element (Apply removes its own note).
      const desc = `${attr(el, "role")} ${label(el).map((s) => JSON.stringify(s)).join(" ")}`;
      if (cmd === "press") press(el);
      return desc;
    }
    case "sheet": {
      const s = sheet();
      return s.uiElements().map((el) => `${attr(el, "role")} | ${attr(el, "value") || attr(el, "name")}`).join("\n");
    }
    case "sheet-select": {
      const popup = sheet().popUpButtons[Number(rest[0])];
      press(popup);
      delay(0.3);
      press(popup.menus[0].menuItems.byName(rest[1]));
      delay(0.3);
      const v = popup.value();
      if (v !== rest[1]) fail(`pop-up shows ${JSON.stringify(v)}, wanted ${JSON.stringify(rest[1])}`);
      return v;
    }
    case "sheet-note": {
      const field = sheet().textFields[0];
      field.value = rest[0];
      return field.value();
    }
    case "sheet-press":
      press(sheet().buttons.byName(rest[0]));
      return rest[0];
    case "menu-state": {
      const item = proc.menuBars[0].menuBarItems.byName(rest[0]).menus[0].menuItems.byName(rest[1]);
      return item.enabled() ? "enabled" : "disabled";
    }
    case "menu": {
      activate();
      const item = proc.menuBars[0].menuBarItems.byName(rest[0]).menus[0].menuItems.byName(rest[1]);
      if (!item.enabled()) fail(`menu item ${rest[0]} > ${rest[1]} is disabled`);
      press(item);
      return `${rest[0]} > ${rest[1]}`;
    }
    case "keys":
    case "keycode": {
      activate();
      const using = (rest[1] || "").split(",").filter(Boolean).map((m) => `${m} down`);
      const opts = using.length ? { using } : {};
      if (!isFront()) fail(`pid ${pid} is not frontmost; refusing to type`);
      if (cmd === "keys") se.keystroke(rest[0], opts);
      else se.keyCode(Number(rest[0]), opts);
      return `typed ${cmd === "keys" ? JSON.stringify(rest[0]) : `key code ${rest[0]}`}${using.length ? ` with ${using.join("+")}` : ""}`;
    }
    case "raise":
      activate();
      win().actions.byName("AXRaise").perform();
      return "raised";
    default:
      fail(`unknown command ${cmd}`);
  }
}

function fail(message) {
  const err = $.NSFileHandle.fileHandleWithStandardError;
  err.writeData($(`ax.js: ${message}\n`).dataUsingEncoding($.NSUTF8StringEncoding));
  $.exit(1);
}
