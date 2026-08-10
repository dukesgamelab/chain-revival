#!/usr/bin/env python3
"""Compare direction-8 aim sprites vs direction-7 for wrong-pose detection."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def opaque_bbox(im: Image.Image) -> tuple[int, int, int, int] | None:
	a = im.split()[-1] if im.mode == "RGBA" else None
	if a is None:
		return im.getbbox()
	return a.getbbox()


def diff_ratio(a: Path, b: Path) -> float:
	ia = Image.open(a).convert("RGBA")
	ib = Image.open(b).convert("RGBA")
	if ia.size != ib.size:
		ib = ib.resize(ia.size, Image.NEAREST)
	pa, pb = ia.load(), ib.load()
	w, h = ia.size
	diff = 0
	opaque = 0
	for y in range(h):
		for x in range(w):
			ca, cb = pa[x, y], pb[x, y]
			if ca[3] < 8 and cb[3] < 8:
				continue
			opaque += 1
			if abs(ca[0] - cb[0]) + abs(ca[1] - cb[1]) + abs(ca[2] - cb[2]) + abs(ca[3] - cb[3]) > 40:
				diff += 1
	return diff / max(opaque, 1)


def main() -> int:
	pairs = [
		("us_soldier/aim_standing", "ASAPA", "I"),  # last frame dig8
		("us_soldier/aim_standing_hold", "ASAIS", "A"),
		("us_soldier/aim_prone_hold", "APAIS", "A"),
		("german_soldier/aim_standing", "GSAPA", "I"),
		("german_soldier/aim_standing_hold", "GSAIS", "A"),
		("german_soldier/aim_prone_hold", "GPAIS", "A"),
	]
	# Also compare ASAIS5A vs fire_standing last frame if present
	fire_c = ROOT / "assets/sprites/us_soldier"
	# find ASFIA5C
	candidates = list(ROOT.glob("assets/sprites/us_soldier/**/ASFIA5C.png"))
	print("ASFIA5C candidates", candidates)

	for folder, stem, letter in pairs:
		p7 = ROOT / "assets/sprites" / folder / f"{stem}7{letter}.png"
		p8 = ROOT / "assets/sprites" / folder / f"{stem}8{letter}.png"
		if not p7.exists() or not p8.exists():
			print(f"MISSING {stem} dig7/8 letter {letter}")
			continue
		ratio = diff_ratio(p7, p8)
		b7, b8 = opaque_bbox(Image.open(p7).convert("RGBA")), opaque_bbox(Image.open(p8).convert("RGBA"))
		print(f"{stem}7{letter} vs 8{letter}: diff_ratio={ratio:.3f} bbox7={b7} bbox8={b8}")

	if candidates:
		asais = ROOT / "assets/sprites/us_soldier/aim_standing_hold/ASAIS5A.png"
		print("ASAIS5A vs ASFIA5C:", f"{diff_ratio(asais, candidates[0]):.4f}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
