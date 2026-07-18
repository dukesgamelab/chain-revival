# Wall/Window Selection — Additional Recovered Logic (v2)

Two pieces of original-engine information were missing; both are now recovered. No per-map
corrections were made.

## 1. Frame-selection sign (binary-exact, replaces the prior compensation)
The renderer previously used a negated Direction mapping — a compensation that survived because
plain walls are near-symmetric between their two same-diagonal faces. Windows and doors are NOT
symmetric, which produced the observed wrong-facing windows. The rule is now the literal
binary-recovered formula (2amhost.exe 0x4b05f0 + caller 0x4af4e0):

    slot = ((Direction − 90·camera_step + 45) mod 360) / 90   →  files [e, s, w, n]

with this renderer's world→screen projection (+x = down-right). Facets 1/2/8 as in the camera spec.

## 2. `Image1` — the engine's explicit under-image property (map data)
Wall tiles may carry a second sprite property `Image1` naming the floor drawn beneath that wall
cell (e.g. LIHW partitions carry `WFLO`; WWAR/WWAQ/SWAQ/SWAR door-frame pieces carry `SFL5`).
This is the ORIGINAL mechanism for floor-under-wall; the renderer draws it before the wall.
The adjacency-based half-diamond underlay remains as the documented fallback for wall cells
without `Image1` (most perimeter walls), preserving the footage-verified look.

## Investigated and ruled out (schema-exhaustive, 78 maps / 94,708 tiles)
No other selection metadata exists: no wall/window subtype fields, no connection masks, no
junction/T/L flags, no building or room membership, no orientation overrides, no hidden rotation
flags, no attachment flags, no alternate family mappings. The complete tile schema is:
x, y, Image, Image1, Direction, z, Static(=1), terrain, TTerrHight, Player Type, World,
No Player At variants, Width/Height (labels), OInternal. Variant choice in the original is
exactly: family + world Direction + camera, plus per-family facet art (including authored
rear-face/cutaway frames) — nothing procedural beyond the recovered formula.

## Known data gaps (original, not ours)
LIHW lacks an e-frame and its w-frame is a solid placeholder; ASID lacks s. Deterministic
fallbacks are in irregular_fallbacks.json, labeled non-original.
