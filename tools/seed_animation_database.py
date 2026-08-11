from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(r"c:\Users\danie\OneDrive\Documents\GitHub\chain-revival")
DB_PATH = ROOT / "assets/data/animation_database.json"
DIGIT_TO_DIR = {
	"1": "w",
	"2": "sw",
	"3": "s",
	"4": "se",
	"5": "e",
	"6": "ne",
	"7": "n",
	"8": "nw",
}
DIRS = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
PAT = re.compile(r"^([A-Za-z]+)([1-8])([A-Za-z])\.png$", re.I)


def collect(dir_rel: str, prefix: str) -> dict[str, list[str]]:
	d = ROOT / dir_rel
	by_dir: dict[str, list[tuple[str, str]]] = {k: [] for k in DIRS}
	if not d.is_dir():
		return {k: [] for k in DIRS}
	for p in sorted(d.glob("*.png")):
		m = PAT.match(p.name)
		if not m:
			continue
		pre, digit, frame = m.group(1).upper(), m.group(2), m.group(3).upper()
		if pre != prefix.upper():
			continue
		letter = DIGIT_TO_DIR[digit]
		rel = f"res://{dir_rel}/{p.name}".replace("\\", "/")
		by_dir[letter].append((frame, rel))
	out: dict[str, list[str]] = {}
	for letter in DIRS:
		frames = sorted(by_dir[letter], key=lambda t: t[0])
		out[letter] = [path for _, path in frames]
	return out


def make_anim(dirs: dict[str, list[str]], loop: bool, fps: float, **meta) -> dict:
	return {
		"loop": loop,
		"fps": fps,
		"metadata": {
			"movement_per_cycle": float(meta.get("movement_per_cycle", 0.0)),
			"sound_effect": str(meta.get("sound_effect", "")),
			"muzzle_flash_frame": int(meta.get("muzzle_flash_frame", -1)),
			"footstep_frame": int(meta.get("footstep_frame", -1)),
			"notes": str(meta.get("notes", "")),
		},
		"directions": {d: {"frames": list(dirs.get(d, []))} for d in DIRS},
	}


def main() -> None:
	db = json.loads(DB_PATH.read_text(encoding="utf-8"))
	us_walk = collect("assets/sprites/us_soldier/walk", "ASMOA")
	ger_walk = collect("assets/sprites/german_soldier/walk", "GSMOA")
	families = {
		"usa": {
			"id": "usa",
			"category": "soldiers",
			"faction": "usa",
			"animations": {
				"idle": make_anim(
					{d: us_walk.get(d, [])[:1] for d in DIRS},
					True,
					1.0,
					notes="Idle uses first walk frame until dedicated idle pack is assigned",
				),
				"walk": make_anim(us_walk, True, 12.0, footstep_frame=0),
				"hit": make_anim(
					collect("assets/sprites/us_soldier/hit_reaction", "AHTLA"),
					False,
					14.0,
				),
				"death": make_anim(
					collect("assets/sprites/us_soldier/fall_or_death", "AFALA"),
					False,
					12.0,
				),
				"corpse": make_anim(
					collect("assets/sprites/us_soldier/dead_fallen", "ADFUS"),
					True,
					1.0,
				),
			},
		},
		"germany": {
			"id": "germany",
			"category": "soldiers",
			"faction": "germany",
			"animations": {
				"idle": make_anim(
					{d: ger_walk.get(d, [])[:1] for d in DIRS},
					True,
					1.0,
					notes="Idle uses first walk frame until dedicated idle pack is assigned",
				),
				"walk": make_anim(ger_walk, True, 12.0, footstep_frame=0),
				"hit": make_anim(
					collect("assets/sprites/german_soldier/hit_reaction", "GHTLA"),
					False,
					14.0,
				),
				"death": make_anim(
					collect("assets/sprites/german_soldier/fall_or_death", "GFALA"),
					False,
					12.0,
				),
				"corpse": make_anim(
					collect("assets/sprites/german_soldier/dead_fallen", "GDFUS"),
					True,
					1.0,
				),
			},
		},
	}
	db["families"] = families
	DB_PATH.write_text(json.dumps(db, indent=2) + "\n", encoding="utf-8")
	for fid, fam in families.items():
		for aid, anim in fam["animations"].items():
			counts = {d: len(anim["directions"][d]["frames"]) for d in DIRS}
			print(fid, aid, counts)
	print("wrote", DB_PATH, DB_PATH.stat().st_size)


if __name__ == "__main__":
	main()
