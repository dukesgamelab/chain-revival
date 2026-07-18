#!/usr/bin/env python3
"""Mirror CocFacetSelector / CocSpriteResolver for editor placement validation."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    facets = json.loads((ROOT / "assets/data/facets_by_family.json").read_text(encoding="utf-8"))[
        "families"
    ]
    manifest = json.loads(
        (ROOT / "assets/sprites/coc_tiles/manifest.json").read_text(encoding="utf-8")
    )
    fallbacks = json.loads(
        (ROOT / "assets/data/irregular_fallbacks.json").read_text(encoding="utf-8")
    )
    fort = json.loads((ROOT / "maps/TheFortress.json").read_text(encoding="utf-8"))

    idx: dict[str, str] = {}
    for e in manifest["sprites"]:
        fam = e["family"].upper()
        let = e["letter"].lower()
        idx[f"{fam}|{let}"] = e["path"]

    letters_4 = ["e", "s", "w", "n"]
    letters_8 = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

    def facet_count(fam: str) -> int:
        for key in (f"{fam}:static", f"{fam}:action", fam):
            if key in facets:
                return int(facets[key]["facets"])
        present = {k.split("|")[1] for k in idx if k.startswith(fam + "|")}
        n = len(present)
        if n >= 8:
            return 8
        if n >= 4:
            return 4
        return max(n, 1)

    def slot_for(angle: int, n: int) -> int:
        a = angle % 360
        if n == 1:
            return 0
        if n == 2:
            return ((a + 90) % 360) // 180
        if n == 4:
            return ((a + 45) % 360) // 90
        return ((a + 22) % 360) // 45

    def letter_for(slot_i: int, n: int) -> str:
        if n == 1:
            return "e"
        if n <= 4:
            return letters_4[slot_i % 4]
        return letters_8[slot_i % 8]

    def apply_fallback(fam: str, let: str) -> str:
        rule = fallbacks.get(fam)
        if not rule:
            return let
        missing = str(rule.get("missing_letter", "")).lower()
        if let != missing:
            return let
        if fam == "LIHW" and let == "e":
            return "w"
        if fam == "ASID" and let == "s":
            return "se"
        return let

    def resolve(fam: str, world: int, cam: int) -> tuple[str, str, int]:
        n = facet_count(fam)
        disp = (world - cam) % 360
        let = apply_fallback(fam, letter_for(slot_for(disp, n), n))
        path = idx.get(f"{fam}|{let}", "")
        return let, path, n

    fdir: dict[str, int] = {}
    for o in fort["map_objects"]:
        src = o.get("source") or {}
        fam = str(src.get("image", "")).upper()
        if fam and fam not in fdir:
            fdir[fam] = int(src.get("direction", 0))

    samples = [
        ("straight_wall", "WWAL"),
        ("corner_wall", "IWCR"),
        ("window", "SWIN"),
        ("tree", "TR01"),
        ("hay_prop_ta02", "TA02"),
    ]

    ok = True
    print("Shared facet validation (Python mirror of CocSpriteResolver)")
    for name, fam in samples:
        world = fdir.get(fam, 0)
        print(f"\n=== {name} ({fam} worldDir={world}) ===")
        letters: list[str] = []
        for cam in (0, 90, 180, 270):
            let, path, n = resolve(fam, world, cam)
            letters.append(let)
            status = "OK" if path else "MISSING"
            if not path:
                ok = False
            pname = Path(path).name if path else ""
            print(f"  cam {cam:3d} -> letter={let:2s} path={pname} [{status}] facets={n}")
        uniq = len(set(letters))
        n = facet_count(fam)
        if n >= 4 and uniq < 2:
            ok = False
            print("  FAIL: letter did not change across cameras")
        else:
            print(f"  letters: {','.join(letters)} unique={uniq}")

    print("\nRESULT", "PASS" if ok else "FAIL")
    print("\nIrregular fallbacks configured:", list(fallbacks.keys()))
    print("\nFamilies with declared-letter gaps (sample set):")
    for fam in {s[1] for s in samples} | set(fallbacks):
        entry = facets.get(f"{fam}:static") or facets.get(f"{fam}:action") or {}
        raw = entry.get("facets", 1)
        if isinstance(raw, str):
            continue
        n = int(raw)
        if n < 2:
            continue
        declared = set(entry.get("letters", []))
        present = {k.split("|")[1] for k in idx if k.startswith(fam + "|")}
        missing = sorted(declared - present) if declared else []
        if missing:
            print(f"  {fam}: missing {missing} (have {sorted(present)})")
        else:
            print(f"  {fam}: complete ({sorted(present)})")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
