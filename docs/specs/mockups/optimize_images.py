"""Converts the rendered mockup PNGs to high-quality WebP (about 10x smaller) and removes the PNGs.
Usage: python optimize_png.py <folder>"""
import sys, pathlib
from PIL import Image
for p in pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "img").rglob("*.png"):
    Image.open(p).convert("RGB").save(p.with_suffix(".webp"), "WEBP", quality=90, method=6)
    p.unlink()
