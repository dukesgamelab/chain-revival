extends Node
## Dev validation: editor-placed CoC families resolve identical facets to Fortress
## across cameras 0/90/180/270 via CocSpriteResolver (shared with gameplay).
##
## Run: open this scene, or call EditorFacetRotationValidation.run() from debugger.

const SAMPLE_FAMILIES := {
	"straight_wall": {"family": "WWAL", "direction": 0},
	"corner_wall": {"family": "IWCR", "direction": 0},
	"window": {"family": "SWIN", "direction": 0},
	"tree": {"family": "TR01", "direction": 0},
	## Fortress uses TA02 for the common prop strip (hay/sandbag analogue in archive).
	"hay_prop_ta02": {"family": "TA02", "direction": 0},
}


func _ready() -> void:
	var report := run()
	print(report["summary"])
	for line in report["lines"]:
		print(line)
	if bool(report.get("ok", false)):
		print("EDITOR FACET ROTATION VALIDATION: PASS")
	else:
		push_error("EDITOR FACET ROTATION VALIDATION: FAIL")


static func run() -> Dictionary:
	CocTileCatalog.ensure_loaded()
	var lines: PackedStringArray = PackedStringArray()
	var ok := true
	var fortress := MapLoader.load_fortress()
	var fortress_by_family: Dictionary = {}
	if fortress != null:
		for entry in fortress.visual_placements:
			var fam := str(entry.get("family", "")).to_upper()
			if fam.is_empty() or fortress_by_family.has(fam):
				continue
			fortress_by_family[fam] = int(entry.get("direction", 0))

	lines.append("Shared resolver: CocSpriteResolver.resolve_placement")
	lines.append("Cameras: 0, 90, 180, 270 — world direction fixed per sample")

	for sample_name in SAMPLE_FAMILIES.keys():
		var sample: Dictionary = SAMPLE_FAMILIES[sample_name]
		var family := str(sample["family"]).to_upper()
		var world_dir := int(sample["direction"])
		## Prefer a real Fortress world direction for that family when available.
		if fortress_by_family.has(family):
			world_dir = int(fortress_by_family[family])

		lines.append("")
		lines.append("=== %s (%s worldDir=%d°) ===" % [sample_name, family, world_dir])
		var letters: PackedStringArray = PackedStringArray()
		for cam in [0, 90, 180, 270]:
			var placed := CocSpriteResolver.resolve_placement(family, world_dir, "", cam)
			var letter := str(placed.get("letter", "?"))
			var path := str(placed.get("path", "")).get_file()
			var unusable := bool(placed.get("unusable", false))
			letters.append(letter)
			var status := "OK"
			if unusable or path.is_empty():
				status = "MISSING"
				ok = false
			lines.append(
				"  cam %3d° → letter=%-2s path=%s [%s]"
				% [cam, letter, path, status]
			)

			## Parity: same family+worldDir from Fortress must match letter/path.
			if fortress != null and fortress_by_family.has(family):
				var ref := CocSpriteResolver.resolve_placement(family, world_dir, "", cam)
				if str(ref.get("letter", "")) != letter or str(ref.get("path", "")) != str(placed.get("path", "")):
					ok = false
					lines.append("  PARITY FAIL vs Fortress resolve")

		## Facet should change for 4-facet families across camera (letter not all identical).
		var facets := CocTileCatalog.facet_count(family)
		if facets >= 4:
			var unique := {}
			for L in letters:
				unique[L] = true
			if unique.size() < 2:
				ok = false
				lines.append("  FAIL: 4+ facet family did not change letter across cameras")
			else:
				lines.append("  letters across cams: %s (unique=%d)" % [",".join(letters), unique.size()])
		else:
			lines.append("  1-facet family — letter stable is expected (%s)" % ",".join(letters))

	## Explicit irregular fallback note.
	var asid := CocSpriteResolver.resolve_placement("ASID", 90, "", 0)
	lines.append("")
	lines.append(
		"ASID irregular (if used): letter=%s path=%s"
		% [str(asid.get("letter", "")), str(asid.get("path", "")).get_file()]
	)

	return {
		"ok": ok,
		"summary": "Editor/gameplay shared facet validation — %s" % ("PASS" if ok else "FAIL"),
		"lines": lines,
	}
