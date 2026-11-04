# /// script
# requires-python = ">=3.10"
# dependencies = ["cairosvg"]
# ///
"""Renders Resources/AppIcon.svg into Resources/AppIcon.icns.

Run with: uv run scripts/make-icon.py
Needs cairo (brew install cairo) and macOS iconutil.
"""
import pathlib
import subprocess
import tempfile

import cffi

# Homebrew's lib folder is not on the default dlopen path on Apple Silicon.
_dlopen = cffi.FFI.dlopen


def _dlopen_with_homebrew(self, name, *args):
    try:
        return _dlopen(self, name, *args)
    except OSError:
        return _dlopen(self, f"/opt/homebrew/lib/{name}", *args)


cffi.FFI.dlopen = _dlopen_with_homebrew

import cairosvg  # noqa: E402

root = pathlib.Path(__file__).resolve().parent.parent
svg = root / "Resources" / "AppIcon.svg"
icns = root / "Resources" / "AppIcon.icns"

with tempfile.TemporaryDirectory() as tmp:
    iconset = pathlib.Path(tmp) / "AppIcon.iconset"
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "" if scale == 1 else "@2x"
            px = size * scale
            cairosvg.svg2png(
                url=str(svg),
                write_to=str(iconset / f"icon_{size}x{size}{suffix}.png"),
                output_width=px,
                output_height=px,
            )
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)

print(f"Wrote {icns.relative_to(root)}")
