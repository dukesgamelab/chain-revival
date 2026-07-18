#!/usr/bin/env python3
"""Place Fortress handoff v2 into the Godot project (exact PNG copies)."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "_tmp_fortress_v2" / "handoff"
REFS = REPO / "_tmp_fortress_v2"


def main() -> None:
    sprites = REPO / "assets" / "sprites" / "coc_tiles"
    data_dir = REPO / "assets" / "data"
    maps = REPO / "maps"
    docs = REPO / "docs" / "reverse_engineering" / "the_fortress"
    for d in (sprites, data_dir, maps, docs):
        d.mkdir(parents=True, exist_ok=True)

    # Clear old GRS_* named tiles so stale imports cannot win over 8GRS*
    for old in sprites.glob("GRS_*.png"):
        old.unlink(missing_ok=True)
    for old in sprites.glob("GRS_*.png.import"):
        old.unlink(missing_ok=True)

    for f in (SRC / "sprites" / "coc_tiles").iterdir():
        if f.is_file() and not f.name.endswith(".import"):
            shutil.copy2(f, sprites / f.name)
    shutil.copy2(SRC / "manifest.json", sprites / "manifest.json")

    for name in (
        "facets_by_family.json",
        "fortress_asset_usage.json",
        "irregular_fallbacks.json",
    ):
        shutil.copy2(SRC / name, data_dir / name)

    raw = json.loads((SRC / "TheFortress.json").read_text(encoding="utf-8"))
    raw["map_name"] = "the_fortress"
    raw["sprite_directory"] = "res://assets/sprites/coc_tiles"
    raw["uses_original_projection"] = True
    raw["apply_terrain_gameplay"] = True
    for obj in raw["map_objects"]:
        gp = obj.get("grid_position", {})
        x = int(obj.get("x", gp.get("x", 0)))
        y = int(obj.get("y", gp.get("y", 0)))
        obj["x"] = x
        obj["y"] = y
        obj["grid_position"] = {"x": x, "y": y}
        obj["type"] = obj.get("object_type", obj.get("type", ""))
        # Preserve Image1 if present under any casing.
        src = obj.get("source", {})
        if isinstance(src, dict):
            img1 = src.get("image1") or src.get("Image1") or obj.get("Image1") or obj.get("image1")
            if img1:
                src["image1"] = str(img1).upper()
            obj["source"] = src
    (maps / "TheFortress.json").write_text(
        json.dumps(raw, indent="\t") + "\n", encoding="utf-8"
    )

    for name in (
        "cursor_fortress_implementation_notes.md",
        "camera_rotation_spec.md",
        "validation_report.md",
        "wall_selection_recovery.md",
        "rotation_reference_sheet.png",
        "thefortress_preview_fullres.png",
        "rotation_previews_4cameras.png",
        "reference_renderer.py",
    ):
        src_path = SRC / name
        if src_path.exists():
            shutil.copy2(src_path, docs / name)

    for name in (
        "thefortress_reference_v2_cam0.png",
        "thefortress_reference_v2_4cameras.png",
        "thefortress_reference_v2_cam0_fullres.png",
    ):
        src_path = REFS / name
        if src_path.exists():
            shutil.copy2(src_path, docs / name)

    print("sprites", len(list(sprites.glob("*.png"))))
    print("grs8", len(list(sprites.glob("8GRS*.png"))))
    print("wrote", maps / "TheFortress.json")


if __name__ == "__main__":
    main()
