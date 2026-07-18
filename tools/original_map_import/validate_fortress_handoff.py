#!/usr/bin/env python3
"""Validate Fortress handoff resolution for all camera rotations."""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MAP = REPO / "maps" / "TheFortress.json"
MANIFEST = REPO / "assets" / "sprites" / "coc_tiles" / "manifest.json"
FACETS = REPO / "assets" / "data" / "facets_by_family.json"
FALLBACKS = REPO / "assets" / "data" / "irregular_fallbacks.json"
SPRITES = REPO / "assets" / "sprites" / "coc_tiles"
MAP_DATA = REPO / "scripts" / "map" / "map_data.gd"

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


def main() -> int:
    errors: list[str] = []
    data = json.loads(MAP.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    facets_root = json.loads(FACETS.read_text(encoding="utf-8"))
    fallbacks = json.loads(FALLBACKS.read_text(encoding="utf-8"))

    sprite_index = {}
    ground = 0
    for entry in manifest["sprites"]:
        key = (entry["family"].upper(), entry["letter"].lower(), int(entry.get("anim_frame", 0)))
        path = Path(entry["path"]).name
        sprite_index[key] = {
            "path": path,
            "hotspot": entry.get("hotspot"),
        }
        if entry["family"].upper() == "GRS":
            ground += 1
        if not (SPRITES / path).exists():
            errors.append("missing file %s" % path)
        if not entry.get("hotspot") or len(entry["hotspot"]) < 2:
            errors.append("missing hotspot for %s" % path)

    facet_counts = {}
    for key, entry in facets_root["families"].items():
        fam = key.split(":")[0].upper()
        raw = entry.get("facets", 1)
        if isinstance(raw, str) and raw.startswith("IRREGULAR"):
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

    placements = []
    for obj in data["map_objects"]:
        src = obj.get("source", {})
        placements.append((src.get("image", "").upper(), int(src.get("direction", 0)), "object"))
    for entry in data.get("floors", []):
        placements.append((entry.get("image", "").upper(), int(entry.get("direction", 0)), "floor"))
    for entry in data.get("decoration", []):
        placements.append((entry.get("image", "").upper(), int(entry.get("direction", 0)), "decor"))

    # Archive gap documented in validation_report.md — MDL declares TA03_w but BMP is absent.
    # No compatibility fallback is authorized; renderer must skip (not invent art).
    KNOWN_ARCHIVE_GAPS = {("TA03", "w")}

    unresolved = []
    known_gaps_hit = []
    for fam, direction, kind in placements:
        if not fam or fam == "NEAR":
            continue
        facets = facet_counts.get(fam, 1)
        for cam in (0, 90, 180, 270):
            display = (direction - cam) % 360
            slot = slot_for_facets(display, facets)
            letter = letter_for_slot(slot, facets)
            letter = apply_fallback(fam, letter)
            key = (fam, letter, 0)
            if key not in sprite_index:
                if (fam, letter) in KNOWN_ARCHIVE_GAPS:
                    known_gaps_hit.append((fam, letter, cam, kind))
                else:
                    unresolved.append((fam, letter, cam, kind))

    if unresolved:
        errors.append("unresolved frames: %s" % unresolved[:20])

    png_count = len(list(SPRITES.glob("*.png")))
    if png_count != 174:
        errors.append("expected 174 sprites, got %d" % png_count)
    if ground != 64:
        errors.append("expected 64 GRS ground sprites, got %d" % ground)

    text = MAP_DATA.read_text(encoding="utf-8")
    if "TheFortress.json" not in text:
        errors.append("DEV_MAP_FILE does not point at TheFortress.json")

    if errors:
        print("FAIL")
        for e in errors:
            print(" -", e)
        return 1

    print("PASS")
    print("  placements=%d objects=%d floors=%d decor=%d" % (
        len(placements), len(data["map_objects"]), len(data["floors"]), len(data["decoration"])
    ))
    print("  sprites=%d ground=%d cameras=0/90/180/270 resolve (LIHW/ASID fallbacks only)" % (png_count, ground))
    if known_gaps_hit:
        print("  known archive gaps skipped: %s" % sorted({(f, l) for f, l, _c, _k in known_gaps_hit}))
    print("  default map: maps/TheFortress.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
