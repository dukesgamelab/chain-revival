#!/usr/bin/env python3
"""Offline handedness check for Fortress landmarks (mirrors MapCoordinateTransform)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / "maps" / "TheFortress.json"
N = 99


def view(x: int, y: int, cam_step: int) -> tuple[int, int]:
    for _ in range(cam_step % 4):
        x, y = y, N - x
    return x, y


def project(vx: int, vy: int) -> tuple[float, float]:
    return (vx - vy) * 31.0, (vx + vy) * 16.0


def screen(x: int, y: int, *, xflip: bool = True, cam: int = 0) -> tuple[float, float]:
    if xflip:
        x = N - x
    vx, vy = view(x, y, cam)
    return project(vx, vy)


def main() -> int:
    data = json.loads(MAP.read_text(encoding="utf-8"))
    labels = {e["text"]: (int(e["x"]), int(e["y"])) for e in data["labels"]}
    print("Authoritative CURRENT = CoC X-flip at cam 0 (matches OG screenshot)")
    for xflip, name in [(True, "CURRENT_XFLIP"), (False, "LEGACY_NO_FLIP")]:
        pts = {k: screen(*labels[k], xflip=xflip) for k in [
            "Hundred Acre Woods", "Hay field", "Western Approach", "The Fortress",
            "Garage", "Back Forty",
        ]}
        woods, hay, west, fort = (
            pts["Hundred Acre Woods"],
            pts["Hay field"],
            pts["Western Approach"],
            pts["The Fortress"],
        )
        print(f"\n=== {name} ===")
        print(f"  Woods left of Fort? {woods[0] < fort[0]}")
        print(f"  Hay right of Fort?  {hay[0] > fort[0]}")
        print(f"  Woods left of Hay?  {woods[0] < hay[0]}")
        print(f"  West right of Fort? {west[0] > fort[0]}")
        order = sorted(pts.items(), key=lambda kv: kv[1][0])
        print("  L->R:", " | ".join(k for k, _ in order))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
