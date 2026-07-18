#!/usr/bin/env python3
"""Place authoritative Fortress handoff package into the Godot project."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

REPO = Path(r"C:\Users\danie\OneDrive\Documents\GitHub\chain-revival")
SRC = REPO / "_tmp_fortress_handoff"


def main() -> None:
    sprites = REPO / "assets" / "sprites" / "coc_tiles"
    data_dir = REPO / "assets" / "data"
    maps = REPO / "maps"
    docs = REPO / "docs" / "reverse_engineering" / "the_fortress"
    for d in (sprites, data_dir, maps, docs):
        d.mkdir(parents=True, exist_ok=True)

    # Sprites + manifest beside them
    for f in (SRC / "sprites" / "coc_tiles").iterdir():
        if f.is_file():
            shutil.copy2(f, sprites / f.name)
    shutil.copy2(SRC / "manifest.json", sprites / "manifest.json")

    # Metadata
    for name in (
        "facets_by_family.json",
        "fortress_asset_usage.json",
        "irregular_fallbacks.json",
    ):
        shutil.copy2(SRC / name, data_dir / name)

    # Map JSON — keep recovered schema; add sprite_directory + projection flags
    raw = json.loads((SRC / "TheFortress.json").read_text(encoding="utf-8"))
    raw["map_name"] = "the_fortress"
    raw["sprite_directory"] = "res://assets/sprites/coc_tiles"
    raw["uses_original_projection"] = True
    raw["apply_terrain_gameplay"] = True
    # Ensure native loader fields on objects
    for obj in raw["map_objects"]:
        gp = obj.get("grid_position", {})
        x = int(obj.get("x", gp.get("x", 0)))
        y = int(obj.get("y", gp.get("y", 0)))
        obj["x"] = x
        obj["y"] = y
        obj["grid_position"] = {"x": x, "y": y}
        obj["type"] = obj.get("object_type", obj.get("type", ""))
    (maps / "TheFortress.json").write_text(
        json.dumps(raw, indent="\t") + "\n", encoding="utf-8"
    )

    # Docs
    for name in (
        "cursor_fortress_implementation_notes.md",
        "camera_rotation_spec.md",
        "validation_report.md",
        "rotation_reference_sheet.png",
    ):
        shutil.copy2(SRC / name, docs / name)

    print("sprites", len(list(sprites.glob("*.png"))))
    print("wrote maps/TheFortress.json")
    print("objects", len(raw["map_objects"]), "floors", len(raw["floors"]))


if __name__ == "__main__":
    main()
