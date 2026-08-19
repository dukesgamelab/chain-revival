"""Add kneel transition animations to animation_database.json for grenade presentation."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "assets/data/animation_database.json"
SPRITE_ROOT = ROOT / "assets/sprites/coc_soldiers"

DIRS = ["e", "n", "ne", "nw", "s", "se", "sw", "w"]
DIR_TO_DIGIT = {
    "w": 1,
    "sw": 2,
    "s": 3,
    "se": 4,
    "e": 5,
    "ne": 6,
    "n": 7,
    "nw": 8,
}

KNEEL_FPS = 15.0

FAMILY_CONFIG = {
    "usa": {
        "transition_standing_to_kneel": ("ASKNA", list("ABCD")),
        "transition_kneel_to_stand": ("AKUPA", list("ABCD")),
        "transition_prone_to_kneel": ("APKNA", list("ABCDEFG")),
        "transition_kneel_to_prone": ("APKNA", list("GFEDCBA")),
    },
    "germany": {
        "transition_standing_to_kneel": ("GSKNA", list("ABCD")),
        "transition_kneel_to_stand": ("GKUPA", list("ABCD")),
        "transition_prone_to_kneel": ("GPKNA", list("ABCDEFG")),
        "transition_kneel_to_prone": ("GPKNA", list("GFEDCBA")),
    },
}


def frame_paths_for_direction(prefix: str, direction: str, letters: list[str]) -> list[str]:
    digit = DIR_TO_DIGIT[direction]
    frames: list[str] = []
    last_path: str | None = None
    for letter in letters:
        rel = f"assets/sprites/coc_soldiers/{prefix}{digit}{letter}.png"
        full = ROOT / rel
        if full.exists():
            last_path = f"res://{rel}"
        elif last_path is not None:
            pass  # duplicate last frame when authored letter missing (e.g. AKUPA nw D)
        else:
            raise FileNotFoundError(full)
        frames.append(last_path)
    return frames


def build_animation(prefix: str, letters: list[str], faction_label: str, category: str) -> dict:
    directions = {}
    for direction in DIRS:
        frames = frame_paths_for_direction(prefix, direction, letters)
        directions[direction] = {"frames": frames}
    return {
        "directions": directions,
        "fps": KNEEL_FPS,
        "loop": False,
        "metadata": {
            "category": category,
            "faction": faction_label,
            "source_family": prefix,
        },
    }


def main() -> None:
    with DB_PATH.open(encoding="utf-8") as f:
        db = json.load(f)

    faction_labels = {"usa": "USA", "germany": "German"}
    for family_id, anims in FAMILY_CONFIG.items():
        animations = db["families"][family_id]["animations"]
        for semantic, (prefix, letters) in anims.items():
            category = f"soldier/grenade_kneel/{semantic}"
            animations[semantic] = build_animation(
                prefix,
                letters,
                faction_labels[family_id],
                category,
            )
            print(f"Added {family_id}/{semantic} ({prefix}, {len(letters)} frames, {KNEEL_FPS} fps)")

    with DB_PATH.open("w", encoding="utf-8") as f:
        json.dump(db, f, indent="\t")
        f.write("\n")
    print(f"Updated {DB_PATH}")


if __name__ == "__main__":
    main()
