#!/usr/bin/env python3
"""Import OG idle rest/breathing/static sprites and wire animation_database.json."""
from __future__ import annotations

import json
import re
import shutil
import string
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ZIP = Path(
	r"c:\Users\danie\OneDrive\Desktop\Chain Revival\OG Game Files\Extractor\recovered_assets.zip"
)
DB = ROOT / "assets" / "data" / "animation_database.json"

# Matches AnimationDatabase.soldier_digit_to_direction (digit -> world dir key in JSON).
DIGIT_TO_DIR = {
	"1": "nw",
	"2": "w",
	"3": "sw",
	"4": "s",
	"5": "se",
	"6": "e",
	"7": "ne",
	"8": "n",
}
DIRS = ["e", "n", "ne", "nw", "s", "se", "sw", "w"]
DIR_TO_DIGIT = {v: k for k, v in DIGIT_TO_DIR.items()}

NAME_RE = re.compile(r"magall_\d+_([A-Z]+)(\d)([A-Z])\.png$", re.I)

# stem -> (nation_folder, subfolder)
IMPORT_FOLDERS = {
	"ASRWA": ("us_soldier", "idle_rest"),
	"ASSSA": ("us_soldier", "idle_rest"),
	"ASFBA": ("us_soldier", "idle_rest"),
	"GSRWA": ("german_soldier", "idle_rest"),
	"GSSSA": ("german_soldier", "idle_rest"),
	"GSFBA": ("german_soldier", "idle_rest"),
	"ASIDA": ("us_soldier", "idle_static"),
	"GSIDA": ("german_soldier", "idle_static"),
}

BREATHING_STEMS = {"ABRLA": ("us_soldier", "idle_standing"), "GBRLA": ("german_soldier", "idle_standing")}

LETTERS_20 = list(string.ascii_uppercase[:20])  # A-T
LETTERS_12 = list(string.ascii_uppercase[:12])  # A-L


def res(path: Path) -> str:
	return "res://" + path.relative_to(ROOT).as_posix()


def inventory_from_disk(stem: str, folder_rel: str) -> dict[str, list[str]]:
	inv: dict[str, list[str]] = defaultdict(list)
	folder = ROOT / "assets" / "sprites" / folder_rel
	pat = re.compile(f"^{stem}(\\d)([A-Z])\\.png$", re.I)
	for p in folder.glob(f"{stem}*.png"):
		m = pat.match(p.name)
		if m:
			inv[m.group(1)].append(m.group(2).upper())
	for dig in inv:
		inv[dig] = sorted(set(inv[dig]))
	return dict(inv)


def extract_inventory() -> dict[str, dict[str, list[str]]]:
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
			if stem not in IMPORT_FOLDERS:
				continue
			nation, folder = IMPORT_FOLDERS[stem]
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
	for stem, (nation, folder) in BREATHING_STEMS.items():
		folder_rel = f"{nation}/{folder}"
		inventory[stem] = inventory_from_disk(stem, folder_rel)
	return inventory


def frames_for_stem(
	stem: str,
	folder_rel: str,
	letters: list[str],
	inventory: dict[str, dict[str, list[str]]],
) -> dict:
	directions: dict = {}
	for direction in DIRS:
		dig = DIR_TO_DIGIT[direction]
		avail = set(inventory.get(stem, {}).get(dig, []))
		frames = []
		for letter in letters:
			if letter not in avail:
				raise RuntimeError(f"{stem} dig{dig} ({direction}) missing letter {letter}")
			frames.append(res(ROOT / "assets" / "sprites" / folder_rel / f"{stem}{dig}{letter}.png"))
		directions[direction] = {"frames": frames}
	return directions


def breathing_entry(stem: str, folder_rel: str, faction: str, inventory: dict) -> dict:
	return {
		"comment": "UM_ImageBreathing — full ABRLA/GBRLA one-shot A–T (excludes U).",
		"loop": False,
		"fps": 8.0,
		"directions": frames_for_stem(stem, folder_rel, LETTERS_20, inventory),
		"metadata": {
			"category": "soldier/idle_breathing",
			"faction": faction,
			"footstep_frame": -1.0,
			"frame_letters": "A-T",
			"movement_per_cycle": 0.0,
			"muzzle_flash_frame": -1.0,
			"notes": "Original StBreathing slot; continuous 20-frame one-shot, not sliced fidgets.",
			"source_family": stem,
			"stance": "standing",
			"verification": "pixel-delta one-shot; excludes U (21st frame)",
			"verified": True,
		},
	}


def rest_entry(
	slot: str,
	stem: str,
	folder_rel: str,
	faction: str,
	letters: list[str],
	og_slot: str,
	inventory: dict,
) -> dict:
	return {
		"comment": f"Original {og_slot} — {stem} one-shot.",
		"loop": False,
		"fps": 8.0,
		"directions": frames_for_stem(stem, folder_rel, letters, inventory),
		"metadata": {
			"category": f"soldier/{slot}",
			"faction": faction,
			"footstep_frame": -1.0,
			"frame_letters": "".join(letters),
			"movement_per_cycle": 0.0,
			"muzzle_flash_frame": -1.0,
			"notes": f"Original {og_slot}; distinct rest one-shot.",
			"source_family": stem,
			"stance": "standing",
			"verification": "pixel-delta one-shot",
			"verified": True,
		},
	}


def wire_family(fam: dict, nation: str, inventory: dict) -> None:
	anims = fam["animations"]
	for key in ["idle_fidget_1", "idle_fidget_2", "idle_fidget_3", "idle_fidget_4"]:
		anims.pop(key, None)

	if nation == "usa":
		folder_breath = "us_soldier/idle_standing"
		folder_rest = "us_soldier/idle_rest"
		anims["idle_breathing"] = breathing_entry("ABRLA", folder_breath, "American", inventory)
		anims["idle_rest_1"] = rest_entry(
			"idle_rest_1", "ASRWA", folder_rest, "American", LETTERS_20, "StRest1", inventory
		)
		anims["idle_rest_2"] = rest_entry(
			"idle_rest_2", "ASSSA", folder_rest, "American", LETTERS_20, "StRest2", inventory
		)
		anims["idle_rest_3"] = rest_entry(
			"idle_rest_3", "ASFBA", folder_rest, "American", LETTERS_12, "StRest3", inventory
		)
		if anims.get("idle_crouch", {}).get("loop") is False:
			anims["idle_crouch"]["loop"] = True
			anims["idle_crouch"]["metadata"]["notes"] = (
				"ADHPA kneel aim A-B loop. Held crouch/stress pose."
			)
	else:
		folder_breath = "german_soldier/idle_standing"
		folder_rest = "german_soldier/idle_rest"
		anims["idle_breathing"] = breathing_entry("GBRLA", folder_breath, "Germany", inventory)
		anims["idle_rest_1"] = rest_entry(
			"idle_rest_1", "GSRWA", folder_rest, "Germany", LETTERS_20, "StRest1", inventory
		)
		anims["idle_rest_2"] = rest_entry(
			"idle_rest_2", "GSSSA", folder_rest, "Germany", LETTERS_20, "StRest2", inventory
		)
		anims["idle_rest_3"] = rest_entry(
			"idle_rest_3", "GSFBA", folder_rest, "Germany", LETTERS_12, "StRest3", inventory
		)


def main() -> int:
	inventory = extract_inventory()
	for stem in sorted(IMPORT_FOLDERS):
		digs = inventory.get(stem, {})
		print(f"{stem}: {len(digs)} dirs, dig5={''.join(sorted(set(digs.get('5', []))))}")

	db = json.loads(DB.read_text(encoding="utf-8"))
	families = db["families"]
	wire_family(families["usa"], "usa", inventory)
	wire_family(families["germany"], "germany", inventory)
	DB.write_text(json.dumps(db, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
	print("Wrote", DB)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
