#!/usr/bin/env python3
"""Stage 1: import aim sprites from recovered_assets.zip and wire DB entries."""
from __future__ import annotations

import json
import re
import shutil
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ZIP = Path(
	r"c:\Users\danie\OneDrive\Desktop\Chain Revival\OG Game Files\Extractor\recovered_assets.zip"
)
DB = ROOT / "assets" / "data" / "animation_database.json"

DIGIT_TO_DIR = {"1": "w", "2": "sw", "3": "s", "4": "se", "5": "e", "6": "ne", "7": "n", "8": "nw"}
DIRS = ["e", "n", "ne", "nw", "s", "se", "sw", "w"]
DIR_TO_DIGIT = {v: k for k, v in DIGIT_TO_DIR.items()}

STEM_FOLDERS = {
	"ASAPA": ("us_soldier", "aim_standing"),
	"ASAIS": ("us_soldier", "aim_standing_hold"),
	"APAIS": ("us_soldier", "aim_prone_hold"),
	"GSAPA": ("german_soldier", "aim_standing"),
	"GSAIS": ("german_soldier", "aim_standing_hold"),
	"GPAIS": ("german_soldier", "aim_prone_hold"),
}

NAME_RE = re.compile(r"magall_\d+_([A-Z]+)(\d)([A-Z])\.png$", re.I)


def res(path: Path) -> str:
	return "res://" + path.relative_to(ROOT).as_posix()


def extract_and_inventory() -> dict[str, dict[str, list[str]]]:
	"""stem -> digit -> sorted letters present. Also copy files into assets."""
	inventory: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
	with zipfile.ZipFile(ZIP) as zf:
		for info in zf.infolist():
			base = Path(info.filename).name
			m = NAME_RE.match(base)
			if not m:
				continue
			stem = m.group(1).upper()
			dig = m.group(2)
			letter = m.group(3).upper()
			if stem not in STEM_FOLDERS:
				continue
			nation, folder = STEM_FOLDERS[stem]
			out_dir = ROOT / "assets" / "sprites" / nation / folder
			out_dir.mkdir(parents=True, exist_ok=True)
			out_name = f"{stem}{dig}{letter}.png"
			out_path = out_dir / out_name
			if not out_path.exists():
				with zf.open(info) as src, open(out_path, "wb") as dst:
					shutil.copyfileobj(src, dst)
			inventory[stem][dig].append(letter)
	for stem in inventory:
		for dig in inventory[stem]:
			inventory[stem][dig] = sorted(set(inventory[stem][dig]))
	return inventory


def print_inventory(inventory: dict[str, dict[str, list[str]]]) -> None:
	for stem in sorted(STEM_FOLDERS):
		print(f"=== {stem}")
		for dig in sorted(inventory.get(stem, {}), key=int):
			letters = "".join(inventory[stem][dig])
			print(f"  dig{dig} ({DIGIT_TO_DIR[dig]}): {len(letters)} [{letters}]")


def anim_entry(
	stem: str,
	folder_rel: str,
	inventory: dict[str, dict[str, list[str]]],
	*,
	loop: bool,
	fps: float,
	comment: str,
) -> dict:
	directions = {}
	for direction in DIRS:
		dig = DIR_TO_DIGIT[direction]
		letters = inventory[stem].get(dig, [])
		if not letters:
			raise RuntimeError(f"{stem} missing direction digit {dig} ({direction})")
		frames = [
			res(ROOT / "assets" / "sprites" / folder_rel / f"{stem}{dig}{letter}.png")
			for letter in letters
		]
		directions[direction] = {"frames": frames}
	return {"comment": comment, "loop": loop, "fps": fps, "directions": directions}


def main() -> int:
	inventory = extract_and_inventory()
	print_inventory(inventory)

	usa = {
		"aim_standing": anim_entry(
			"ASAPA",
			"us_soldier/aim_standing",
			inventory,
			loop=False,
			fps=12.0,
			comment="Stage 1: ASAPA ragged 9–11 frames by direction — do not pad.",
		),
		"aim_standing_hold": anim_entry(
			"ASAIS",
			"us_soldier/aim_standing_hold",
			inventory,
			loop=True,
			fps=1.0,
			comment="Stage 1: ASAIS single-frame aim hold (pixel-identical to fire_standing C).",
		),
		"aim_prone_hold": anim_entry(
			"APAIS",
			"us_soldier/aim_prone_hold",
			inventory,
			loop=True,
			fps=1.0,
			comment="Stage 1: APAIS single-frame prone aim hold.",
		),
	}
	ger = {
		"aim_standing": anim_entry(
			"GSAPA",
			"german_soldier/aim_standing",
			inventory,
			loop=False,
			fps=12.0,
			comment="Stage 1: GSAPA ragged frame counts by direction — do not pad.",
		),
		"aim_standing_hold": anim_entry(
			"GSAIS",
			"german_soldier/aim_standing_hold",
			inventory,
			loop=True,
			fps=1.0,
			comment="Stage 1: GSAIS single-frame aim hold.",
		),
		"aim_prone_hold": anim_entry(
			"GPAIS",
			"german_soldier/aim_prone_hold",
			inventory,
			loop=True,
			fps=1.0,
			comment="Stage 1: GPAIS single-frame prone aim hold.",
		),
	}

	data = json.loads(DB.read_text(encoding="utf-8"))
	for fam_id, fam in data["families"].items():
		chosen = ger if fam_id.startswith("german_") else usa
		anims = fam.setdefault("animations", {})
		for anim_id, payload in chosen.items():
			anims[anim_id] = payload
		print(f"updated {fam_id} (+{len(chosen)} aim anims, total={len(anims)})")

	DB.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
	print("wrote", DB)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
