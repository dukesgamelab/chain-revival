# Validation Report — Fortress Final Handoff

- Fortress map objects (placed tiles): **834**
- Distinct families referenced by the map: **32** (BH01, BH02, CW01, CW02, IWCR, IWWL, LIHW, SCOR, SFL5, SFLO, SICR, SWAL, SWAQ, SWAR, SWIN, TA01, TA02, TA03, TR01, TR02, WCOR, WFL5, WFLO, WH01, WH02, WH11, WICR, WWAI, WWAL, WWAQ, WWAR, WWIN)
- Sprite PNGs included: **174** (all facets of every referenced family, plus the ASAX
  soldier family and the 64-variant GRS ground family)
- Missing archive files: **1** — [{'code': 'TA03', 'letter': 'w', 'file': '8TA03S7A.BMP', 'reason': 'not in archive'}]
  (TA03's w-frame is declared in the MDL but absent from the archive; TA03 appears once in the map
  with Direction 0, which resolves to its present e-frame, so no Fortress object is affected)
- Irregular families relevant to this map: **LIHW** (no e-frame; 27 map objects — deterministic
  fallback in irregular_fallbacks.json). ASID is not used by this map but its rule is included for
  soldier rendering completeness.
- Resolution check: every one of the 834 map objects maps to a family present in
  manifest.json; per-object frame resolution
  under the camera spec succeeds for all four camera rotations given the fallback rules above.
- Usage index: fortress_asset_usage.json (per-family facets, letters, sprite paths, usage counts).
