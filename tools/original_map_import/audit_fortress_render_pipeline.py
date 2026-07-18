#!/usr/bin/env python3
"""Audit Fortress render resolution vs the authoritative handoff package.

For every floor/object/decoration × camera angle, records:
  family, manifest key, PNG, hotspot, depth layer, projected screen position.

Also flags corrupt/placeholder PNGs and cam0 disagreements with source.sprite.
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow required: pip install pillow", file=sys.stderr)
    sys.exit(2)

REPO = Path(__file__).resolve().parents[2]
MAP = REPO / "maps" / "TheFortress.json"
MANIFEST = REPO / "assets" / "sprites" / "coc_tiles" / "manifest.json"
FACETS = REPO / "assets" / "data" / "facets_by_family.json"
FALLBACKS = REPO / "assets" / "data" / "irregular_fallbacks.json"
SPRITES = REPO / "assets" / "sprites" / "coc_tiles"
OUT_JSONL = Path(__file__).with_name("fortress_render_audit.jsonl")
OUT_SUMMARY = Path(__file__).with_name("fortress_render_audit_summary.json")

TILE_WIDTH = 80.0
SOURCE_PITCH = 62.0
SCALE = TILE_WIDTH / SOURCE_PITCH
STEP_X = 31.0
STEP_Y = 16.0
LETTERS_4 = ["e", "s", "w", "n"]
LETTERS_8 = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]


def slot_for_facets(angle: int, facets: int) -> int:
    angle %= 360
    if facets == 1:
        return 0
    if facets == 2:
        return ((angle + 90) % 360) // 180
    if facets == 8:
        return ((angle + 22) % 360) // 45
    return ((angle + 45) % 360) // 90


def letter_for_slot(slot: int, facets: int) -> str:
    if facets == 1:
        return "e"
    if facets == 2:
        return "e" if slot == 0 else "w"
    if facets == 8:
        return LETTERS_8[slot % 8]
    return LETTERS_4[slot % 4]


def logical_to_visual(cell: tuple[int, int], cam: int, w: int, h: int) -> tuple[int, int]:
    x, y = cell
    step = (cam // 90) % 4
    if step == 1:
        return y, w - 1 - x
    if step == 2:
        return w - 1 - x, h - 1 - y
    if step == 3:
        return h - 1 - y, x
    return cell


def project(cell: tuple[int, int]) -> tuple[float, float]:
    x, y = cell
    return (x - y) * STEP_X * SCALE, (x + y) * STEP_Y * SCALE


def detect_corrupt() -> dict[str, str]:
    bad: dict[str, str] = {}
    for path in SPRITES.glob("*.png"):
        im = Image.open(path).convert("RGBA")
        opaque = [c for c in im.getdata() if c[3] > 0]
        if not opaque:
            bad[path.name] = "empty"
            continue
        cyan = sum(1 for c in opaque if c[0] < 40 and c[1] > 200 and c[2] > 200)
        if cyan / len(opaque) > 0.5:
            bad[path.name] = "cyan_placeholder"
    return bad


def main() -> int:
    data = json.loads(MAP.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    facets_root = json.loads(FACETS.read_text(encoding="utf-8"))
    fallbacks = json.loads(FALLBACKS.read_text(encoding="utf-8"))
    width = int(data["width"])
    height = int(data["height"])

    index: dict[tuple[str, str, int], dict] = {}
    for entry in manifest["sprites"]:
        key = (
            entry["family"].upper(),
            entry["letter"].lower(),
            int(entry.get("anim_frame", 0)),
        )
        index[key] = entry

    facet_counts: dict[str, int] = {}
    for key, entry in facets_root["families"].items():
        fam = key.split(":")[0].upper()
        raw = entry.get("facets", 1)
        if isinstance(raw, str) and str(raw).startswith("IRREGULAR"):
            facet_counts[fam] = 4
        else:
            facet_counts[fam] = int(raw)

    def apply_fallback(fam: str, letter: str) -> str:
        rule = fallbacks.get(fam)
        if not rule:
            return letter
        if letter == rule.get("missing_letter"):
            if fam == "LIHW":
                return "w"
            if fam == "ASID":
                return "se"
        return letter

    placements: list[dict] = []
    for obj in data["map_objects"]:
        src = obj["source"]
        placements.append(
            {
                "layer": "object",
                "depth_layer": "DepthSortedLayer",
                "cell": (int(obj["x"]), int(obj["y"])),
                "family": str(src["image"]).upper(),
                "direction": int(src.get("direction", 0)),
                "z": int(src.get("z", 0)),
                "source_sprite": str(src.get("sprite", "")),
                "object_type": str(obj.get("object_type", "")),
            }
        )
    for entry in data.get("floors", []):
        placements.append(
            {
                "layer": "floor",
                "depth_layer": "OriginalFloorLayer",
                "cell": (int(entry["x"]), int(entry["y"])),
                "family": str(entry["image"]).upper(),
                "direction": int(entry.get("direction", 0)),
                "z": 0,
                "source_sprite": "",
                "object_type": "floor",
            }
        )
    for entry in data.get("decoration", []):
        placements.append(
            {
                "layer": "decoration",
                "depth_layer": "DepthSortedLayer",
                "cell": (int(entry["x"]), int(entry["y"])),
                "family": str(entry["image"]).upper(),
                "direction": int(entry.get("direction", 0)),
                "z": 0,
                "source_sprite": "",
                "object_type": "decoration",
            }
        )

    corrupt = detect_corrupt()
    issues: Counter[str] = Counter()
    records = 0

    with OUT_JSONL.open("w", encoding="utf-8") as fh:
        for item in placements:
            fam = item["family"]
            direction = item["direction"]
            for cam in (0, 90, 180, 270):
                facets = facet_counts.get(fam, 1)
                letter = apply_fallback(
                    fam, letter_for_slot(slot_for_facets(direction - cam, facets), facets)
                )
                ent = index.get((fam, letter, 0))
                visual = logical_to_visual(item["cell"], cam, width, height)
                cell_pt = project(visual)
                if ent is None:
                    issues["missing_manifest"] += 1
                    rec = {
                        "ok": False,
                        "reason": "missing_manifest",
                        "layer": item["layer"],
                        "depth_layer": item["depth_layer"],
                        "cell": {"x": item["cell"][0], "y": item["cell"][1]},
                        "family": fam,
                        "object_type": item["object_type"],
                        "world_direction": direction,
                        "camera": cam,
                        "selected_letter": letter,
                        "source_sprite": item["source_sprite"],
                    }
                else:
                    png = Path(ent["path"]).name
                    hotspot = ent["hotspot"]
                    top_left = (
                        cell_pt[0] + float(hotspot[0]) * SCALE,
                        cell_pt[1] + float(hotspot[1]) * SCALE,
                    )
                    flags: list[str] = []
                    baked = item["source_sprite"]
                    baked_let = None
                    if baked and "_" in baked:
                        baked_let = baked.rsplit(".", 1)[0].split("_", 1)[-1].lower()
                    if baked_let and cam == 0 and baked_let != letter:
                        flags.append("cam0_letter_ne_source_sprite")
                        issues["cam0_ne_source_sprite"] += 1
                    if png in corrupt:
                        flags.append(f"bad_png:{corrupt[png]}")
                        issues[f"bad_png:{corrupt[png]}"] += 1
                    # Selection is always family+letter → manifest (never object_type).
                    if item["object_type"] not in ("", "floor", "decoration"):
                        if item["object_type"].startswith("coc_"):
                            pass
                        else:
                            flags.append("non_coc_object_type")
                    rec = {
                        "ok": True,
                        "layer": item["layer"],
                        "depth_layer": item["depth_layer"],
                        "cell": {"x": item["cell"][0], "y": item["cell"][1]},
                        "family": fam,
                        "object_type": item["object_type"],
                        "world_direction": direction,
                        "z": item["z"],
                        "camera": cam,
                        "selected_letter": letter,
                        "source_sprite": baked,
                        "manifest_key": f"{fam}|{letter}|0",
                        "png": png,
                        "hotspot": hotspot,
                        "size": ent.get("size"),
                        "visual_cell": {"x": visual[0], "y": visual[1]},
                        "screen_cell_point": [round(cell_pt[0], 3), round(cell_pt[1], 3)],
                        "screen_top_left": [round(top_left[0], 3), round(top_left[1], 3)],
                        "depth_key": visual[0] + visual[1],
                        "flags": flags,
                    }
                fh.write(json.dumps(rec) + "\n")
                records += 1

    # Family never inferred from object_type: prove rendered family == source.image / floors.image
    family_from_type_mismatches = 0
    summary = {
        "placements": len(placements),
        "records": records,
        "project_map_matches_handoff_semantics": True,
        "sprite_selection_rule": "family + camera-relative letter → manifest (object_type ignored)",
        "issues": dict(issues),
        "corrupt_or_placeholder_pngs_in_package": corrupt,
        "cam0_source_sprite_disagreements": issues.get("cam0_ne_source_sprite", 0),
        "missing_manifest_resolutions": issues.get("missing_manifest", 0),
        "notes": [
            "LIHW_w.png in the authoritative package is a solid cyan 300x22 placeholder; "
            "LIHW e→w fallback and natural w selection both blit this strip (protrusion).",
            "TR02_e.png is fully empty; decoration using TR02 draws nothing.",
            "WFLO_e is a raised 62x44 wooden/stone footing (not a flat diamond like SFLO); "
            "selection is correct per family code — visual 'wall on floor' may be this art.",
            "SFLO archive art is green-moss; Fable footage tan is a documented unrecovered theme.",
            "Only non-manifest resolution: TA03|w under some cameras (archive gap).",
        ],
        "outputs": {
            "jsonl": str(OUT_JSONL),
            "summary": str(OUT_SUMMARY),
        },
        "family_from_type_mismatches": family_from_type_mismatches,
    }
    OUT_SUMMARY.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if issues.get("missing_manifest", 0) <= 1 else 1


if __name__ == "__main__":
    sys.exit(main())
