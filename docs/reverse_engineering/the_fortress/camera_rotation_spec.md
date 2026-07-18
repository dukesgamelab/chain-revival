# Camera Rotation & Frame Selection — Renderer Specification

Evidence: disassembly of the original host engine (`2amhost.exe`): facet quantizer at VA 0x4b05f0
(`CPieceMakerIndex::OnUpdateDir`) and its caller at 0x4af4e0 (camera subtraction). All rules below
are binary-recovered, not inferred.

## 1. Displayed angle

`Direction` in the map data is **world-space**. The camera holds a direction in degrees
(0/90/180/270; default 0 — maps store no WorldView Direction).

```
display_angle = (Direction - CameraDirection + 360) mod 360
```

## 2. Facet quantizer (original pseudocode)

```
switch (Facets):                       # per family, from facets_by_family.json
  1: slot = 0
  2: slot = ((display_angle + 90) % 360) / 180      # engine frame = slot*4
  4: slot = ((display_angle + 45) % 360) /  90      # engine frame = slot*2
  8: slot = ((display_angle + 22) % 360) /  45      # engine frame = slot
```

Frames live in one 8-wide facet space (engine frame = slot scaled as noted); on disk each family
stores only its own facets.

## 3. Slot → direction letter (file naming)

- 4-facet: slots 0..3 → `e, s, w, n` (world angles 0/90/180/270; archive suffixes S3A/S5A/S7A/S1A)
- 8-facet: slots 0..7 → `e, se, s, sw, w, nw, n, ne` (45° steps)
- 1-facet: always `e`

## 4. Coordinate rotation per camera step

Rotate grid coordinates before the isometric projection (about the map center; N = max index):

| camera | (x,y) → view |
|---|---|
| 0° | (x, y) |
| 90° | (y, N−x) |
| 180° | (N−x, N−y) |
| 270° | (N−y, x) |

Then project: `screen = (vx−vy)·31, (vx+vy)·16`, depth-sort by `vx+vy`.

## 5. What changes on rotation

**Both** positions (via the coordinate rotation) and sprite facets (via the display-angle formula)
change. Nothing else does. Camera state must never be baked into the map data or the PNGs.

## 6. Authored rear-face behavior (do not "fix")

The frame shown when a wall faces directly away from the camera is per-family authored art:
stone walls (SWAL family) collapse to a narrow edge sliver — the original cutaway system that keeps
interiors visible; wooden walls (WWAL) draw a full back face; windows/doors have distinct full
back-face art. Trees, floors, ground, cows and other 1-facet families never change with camera.

Caveat (documented, low-risk): the rotate-handler's write to the camera field and the spin sign of
the world→view mapping were not read out of the binary; if in-game rotation visibly spins opposite
to the original, negate the camera step in the coordinate table only — the frame formula is shared.
