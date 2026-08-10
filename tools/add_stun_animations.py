#!/usr/bin/env python3
"""Add stun_knockdown / stun_idle / stun_recover to all six soldier families."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "assets" / "data" / "animation_database.json"

DIGIT_TO_DIR = {"1": "w", "2": "sw", "3": "s", "4": "se", "5": "e", "6": "ne", "7": "n", "8": "nw"}
DIR_TO_DIGIT = {v: k for k, v in DIGIT_TO_DIR.items()}
DIRS = ["e", "n", "ne", "nw", "s", "se", "sw", "w"]

# Knockdown: AFALA/GFALA A–Q (17). Drop R–W corpse-settle so stun ≠ death.
KNOCKDOWN_LETTERS = [chr(ord("A") + i) for i in range(17)]  # A–Q
IDLE_LETTERS = ["A", "B"]
RECOVER_LETTERS = [chr(ord("A") + i) for i in range(20)]  # A–T


def res(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def frames_for(prefix: str, folder: Path, letters: list[str]) -> dict:
    out: dict = {}
    for direction in DIRS:
        digit = DIR_TO_DIGIT[direction]
        paths = []
        for letter in letters:
            p = folder / f"{prefix}{digit}{letter}.png"
            if not p.is_file():
                raise FileNotFoundError(p)
            paths.append(res(p))
        out[direction] = {"frames": paths}
    return out


def main() -> int:
    data = json.loads(DB.read_text(encoding="utf-8"))
    usa_fall = ROOT / "assets/sprites/us_soldier/fall_or_death"
    ger_fall = ROOT / "assets/sprites/german_soldier/fall_or_death"
    usa_crouch = ROOT / "assets/sprites/us_soldier/idle_crouch"
    ger_crouch = ROOT / "assets/sprites/german_soldier/idle_crouch"
    usa_recover = ROOT / "assets/sprites/us_soldier/hit_reaction"
    ger_recover = ROOT / "assets/sprites/coc_soldiers"

    usa_anims = {
        "stun_knockdown": {
            "comment": "Stage 2 grenade stun fall. AFALA A–Q (trimmed before corpse-settle R–W).",
            "loop": False,
            "fps": 12.0,
            "directions": frames_for("AFALA", usa_fall, KNOCKDOWN_LETTERS),
        },
        "stun_idle": {
            "comment": "Stage 2 lying stunned. ADHPA A–B loop ~2 fps.",
            "loop": True,
            "fps": 2.0,
            "directions": frames_for("ADHPA", usa_crouch, IDLE_LETTERS),
        },
        "stun_recover": {
            "comment": "Stage 2 get-up after stun. AHTBA A–T (20 frames).",
            "loop": False,
            "fps": 12.0,
            "directions": frames_for("AHTBA", usa_recover, RECOVER_LETTERS),
        },
    }
    ger_anims = {
        "stun_knockdown": {
            "comment": "Stage 2 grenade stun fall. GFALA A–Q (trimmed before corpse-settle R–W).",
            "loop": False,
            "fps": 12.0,
            "directions": frames_for("GFALA", ger_fall, KNOCKDOWN_LETTERS),
        },
        "stun_idle": {
            "comment": "Stage 2 lying stunned. GDHPA A–B loop ~2 fps.",
            "loop": True,
            "fps": 2.0,
            "directions": frames_for("GDHPA", ger_crouch, IDLE_LETTERS),
        },
        "stun_recover": {
            "comment": "Stage 2 get-up after stun. GHTBA A–T from coc_soldiers pack.",
            "loop": False,
            "fps": 12.0,
            "directions": frames_for("GHTBA", ger_recover, RECOVER_LETTERS),
        },
    }

    for fam_id, fam in data["families"].items():
        anims = fam.setdefault("animations", {})
        chosen = ger_anims if fam_id.startswith("german_") else usa_anims
        for anim_id, payload in chosen.items():
            anims[anim_id] = payload
        print(f"updated {fam_id}")

    DB.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote", DB)
    print("stun_knockdown frames:", len(KNOCKDOWN_LETTERS), "".join(KNOCKDOWN_LETTERS))
    print("stun_recover frames:", len(RECOVER_LETTERS), "".join(RECOVER_LETTERS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
