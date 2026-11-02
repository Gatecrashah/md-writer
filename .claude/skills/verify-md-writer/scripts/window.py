"""Window-server helpers for one MD Writer process. Called by `mdw`; run directly as:

    uv run -q --with pyobjc-framework-Quartz python -I window.py id <pid>
    uv run -q --with pyobjc-framework-Quartz python -I window.py click <pid> <x> <y>

`id` prints the CGWindowID of the process's largest on-screen window (for `screencapture -l`, which captures
that window even when other windows cover it). `click` posts a real left click at window-relative points; use it
only for things accessibility can't reach (placing the caret in the editor text).
"""

import sys
import time

from Quartz import (
    CGEventCreateMouseEvent,
    CGEventPost,
    CGWindowListCopyWindowInfo,
    kCGEventLeftMouseDown,
    kCGEventLeftMouseUp,
    kCGEventMouseMoved,
    kCGHIDEventTap,
    kCGMouseButtonLeft,
    kCGNullWindowID,
    kCGWindowListOptionOnScreenOnly,
)


def main_window(pid: int) -> dict:
    windows = [
        w
        for w in CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID)
        if w["kCGWindowOwnerPID"] == pid and w["kCGWindowLayer"] == 0
    ]
    if not windows:
        sys.exit(f"window.py: no on-screen window for pid {pid}")
    return max(windows, key=lambda w: w["kCGWindowBounds"]["Width"] * w["kCGWindowBounds"]["Height"])


def click(x: float, y: float) -> None:
    for kind in (kCGEventMouseMoved, kCGEventLeftMouseDown, kCGEventLeftMouseUp):
        CGEventPost(kCGHIDEventTap, CGEventCreateMouseEvent(None, kind, (x, y), kCGMouseButtonLeft))
        time.sleep(0.08)


if __name__ == "__main__":
    cmd, pid = sys.argv[1], int(sys.argv[2])
    window = main_window(pid)
    if cmd == "id":
        print(window["kCGWindowNumber"])
    elif cmd == "click":
        bounds = window["kCGWindowBounds"]
        click(bounds["X"] + float(sys.argv[3]), bounds["Y"] + float(sys.argv[4]))
    else:
        sys.exit(f"window.py: unknown command {cmd}")
