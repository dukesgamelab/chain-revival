# Cursor Implementation Notes — The Fortress (Godot)

## Resource layout
```
maps/TheFortress.json
assets/sprites/coc_tiles/*.png     # exact archive decodes, never edited
assets/sprites/coc_tiles/manifest.json
assets/data/facets_by_family.json
assets/data/fortress_asset_usage.json
assets/data/irregular_fallbacks.json
```

## Parsing
- `TheFortress.json` is a superset of the existing `maps/test_map.json` schema: standard keys
  (`map_objects`, `blocked_tiles`, spawn point arrays) plus `floors`, `victory_points`, `labels`,
  `starting_points`; every object keeps its `source` dict (family code, world Direction, z, terrain,
  original sprite reference). Ignore unknown keys gracefully.
- `manifest.json` maps (family, letter[, anim_frame]) → PNG path + exact original hotspot + size.
  Sprite lookup at draw time: family + letter from the camera spec → manifest entry.

## Geometry
- Tile pitch 62×32; neighbor steps (+31,+16)/(−31,+16); scale by `project_tile_width / 62.0`.
- Blit each sprite with its top-left at `cell_screen_point + hotspot` (hotspots are per-sprite in the
  manifest, typically [-50,-73]; canvases are full originals — never center or crop).
- Layers: (1) ground — every in-bounds cell gets a GRS variant chosen by a well-mixed per-cell hash
  (stable across frames; avoid linear congruences, they stripe); (2) floors (`floors` array), no
  depth sort; (3) objects, depth-sorted by `vx+vy`; (4) labels (yellow, 1px black shadow).
- Camera rotation per camera_rotation_spec.md: rotate coords, re-sort, re-select facets. Default 0.

## Hard rules — remove these experimental assumptions if present anywhere
1. NO `(-Direction/90) mod 4` frame mapping — use the camera-relative positive rule from the spec.
2. NO pixel heuristics of any kind: no row-56 cropping, no opaque-height filters, no span-width
   filters, no footing/grass stripping, no mirroring, no recoloring, no "face extraction".
3. NO placeholder/+2-frame fallbacks for wall & window families — every needed frame is real art in
   this package (only the two families in irregular_fallbacks.json lack a slot; apply exactly those
   deterministic rules and nothing else).
4. Rear-facing stone walls render as slivers, wooden as full backs, WH01/WH02 fieldstone tiles as
   dashed runs — all authored; do not compensate.

## Known open item (display-only)
Gameplay footage shows the SFLO stone-floor family rendering warm tan in-game while its archive art
is green-moss; the mechanism (theme/frame indirection) was never recovered. This package ships the
exact archive art. If visual parity with footage is preferred over archive literalism for floors,
gate it behind a renderer option that swaps SFLO's art for the SFL5 w-frame — clearly labeled
non-original.
