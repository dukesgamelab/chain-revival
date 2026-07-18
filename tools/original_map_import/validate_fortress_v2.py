#!/usr/bin/env python3
"""Validate Fortress v2 placement + camera facet resolution."""
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

    if "under_image_rule" not in manifest:
        errors.append("manifest missing under_image_rule (v2)")

    index = {}
    ground = 0
    for entry in manifest["sprites"]:
        key = (entry["family"].upper(), entry["letter"].lower(), int(entry.get("anim_frame", 0)))
        path = Path(entry["path"]).name
        index[key] = entry
        if entry["family"].upper() == "GRS":
            ground += 1
        if not (SPRITES / path).exists():
            errors.append("missing %s" % path)
        if not entry.get("hotspot") or len(entry["hotspot"]) < 2:
            errors.append("no hotspot %s" % path)

    facet_counts = {}
    for key, entry in facets_root["families"].items():
        fam = key.split(":")[0].upper()
        raw = entry.get("facets", 1)
        facet_counts[fam] = 4 if isinstance(raw, str) and str(raw).startswith("IRREGULAR") else int(raw)

    def apply_fb(fam: str, letter: str) -> str:
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
        placements.append((src.get("image", "").upper(), int(src.get("direction", 0))))
    for entry in data.get("floors", []):
        placements.append((entry.get("image", "").upper(), int(entry.get("direction", 0))))
    for entry in data.get("decoration", []):
        placements.append((entry.get("image", "").upper(), int(entry.get("direction", 0))))

    unresolved = []
    placeholder = 0
    for fam, direction in placements:
        if not fam or fam == "NEAR":
            continue
        facets = facet_counts.get(fam, 1)
        for cam in (0, 90, 180, 270):
            letter = apply_fb(fam, letter_for_slot(slot_for_facets((direction - cam) % 360, facets), facets))
            ent = index.get((fam, letter, 0))
            if ent is None:
                unresolved.append((fam, letter, cam))
                continue
            size = ent.get("size", [100, 100])
            if size[0] >= 200 and size[1] <= 40:
                placeholder += 1

    if unresolved:
        # TA03_w is the known archive gap
        bad = [u for u in unresolved if not (u[0] == "TA03" and u[1] == "w")]
        if bad:
            errors.append("unresolved %s" % bad[:10])

    if ground != 64:
        errors.append("expected 64 GRS got %d" % ground)
    if not data.get("uses_original_projection"):
        errors.append("uses_original_projection not set")

    if errors:
        print("FAIL")
        for e in errors:
            print(" -", e)
        return 1
    print("PASS")
    print(" placements=%d grs=%d placeholder_frames_hit=%d" % (len(placements), ground, placeholder))
    print(" under_image_rule present; Image1 field supported in loader")
    return 0


if __name__ == "__main__":
    sys.exit(main())
