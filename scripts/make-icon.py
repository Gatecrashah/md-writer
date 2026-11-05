# /// script
# requires-python = ">=3.10"
# dependencies = ["resvg-py"]
# ///
"""Renders Resources/AppIcon.svg into Resources/AppIcon.icns.

Run with: uv run scripts/make-icon.py
Needs macOS iconutil.
"""
import pathlib
import subprocess
import tempfile

import resvg_py

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
            png = resvg_py.svg_to_bytes(svg_path=str(svg), width=px, height=px)
            (iconset / f"icon_{size}x{size}{suffix}.png").write_bytes(bytes(png))
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)

print(f"Wrote {icns.relative_to(root)}")
