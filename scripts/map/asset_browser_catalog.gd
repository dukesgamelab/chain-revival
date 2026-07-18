class_name AssetBrowserCatalog
extends RefCounted
## Builds the editor asset browser categories from the sprite manifest (not hardcoded).

const CATEGORY_ORDER: PackedStringArray = [
	"Terrain",
	"Floors",
	"Walls",
	"Windows",
	"Doors",
	"Corners",
	"Trees",
	"Bushes",
	"Rocks",
	"Hay",
	"Vehicles",
	"Props",
	"Special",
	"Spawn Points",
	"Victory Points",
	"Labels",
]


static func build_categories() -> Dictionary:
	## category -> Array[{ family, label, preview_path, kind }]
	CocTileCatalog.ensure_loaded()
	var categories: Dictionary = {}
	for cat in CATEGORY_ORDER:
		categories[cat] = []

	var root := _read_manifest()
	var seen: Dictionary = {}
	var sprites: Variant = root.get("sprites", [])
	if sprites is Array:
		for entry in sprites:
			if not entry is Dictionary:
				continue
			var fam := str(entry.get("family", "")).to_upper()
			if fam.is_empty() or seen.has(fam):
				continue
			if fam == "GRS" or fam == "ASAX" or fam == "ASID":
				## Ground variants / soldiers are not placeable props in the browser.
				if fam == "GRS":
					seen[fam] = true
					categories["Terrain"].append(_item(fam, "Ground (GRS)", "terrain"))
				continue
			seen[fam] = true
			var letter := str(entry.get("letter", "e")).to_lower()
			var path := str(entry.get("path", ""))
			var cat := categorize_family(fam)
			categories[cat].append(_item(fam, fam, "family", path, letter))

	categories["Spawn Points"].append(_item("SPAWN_USA", "USA Spawn", "spawn_usa"))
	categories["Spawn Points"].append(_item("SPAWN_GER", "Germany Spawn", "spawn_ger"))
	categories["Victory Points"].append(_item("VP", "Victory Point", "victory"))
	categories["Labels"].append(_item("LABEL", "Label", "label"))
	return categories


static func categorize_family(family: String) -> String:
	var fam := family.to_upper()
	if CocRenderRules.is_floor_family(fam):
		return "Floors"
	if fam.begins_with("WH") or fam.ends_with("WIN") or fam in ["SWIN", "WWIN", "WH11"]:
		return "Windows"
	if fam in ["WWAR", "WWAQ", "SWAR", "SWAQ", "WWAI", "SDOR", "WDOR"]:
		return "Doors"
	if fam.ends_with("COR") or fam.ends_with("ICR"):
		return "Corners"
	if CocRenderRules.is_wallish_family(fam) or fam in ["WWAL", "SWAL", "LIHW", "IWWL"]:
		return "Walls"
	if fam.begins_with("TR"):
		return "Trees"
	if fam.begins_with("BH") or fam.begins_with("CW"):
		return "Bushes"
	if fam.begins_with("RK") or fam.begins_with("RO"):
		return "Rocks"
	if fam.begins_with("HY") or fam.begins_with("HAY"):
		return "Hay"
	if fam.begins_with("VH") or fam.begins_with("VEH") or fam.begins_with("JE"):
		return "Vehicles"
	if fam.begins_with("TA") or fam.begins_with("SF") or fam.begins_with("WF"):
		return "Props"
	return "Special"


static func _item(
	family: String,
	label: String,
	kind: String,
	preview_path: String = "",
	letter: String = "e",
) -> Dictionary:
	var path := preview_path
	if path.is_empty() and kind == "family":
		var resolved := CocTileCatalog.resolve(family, letter)
		path = str(resolved.get("path", ""))
	return {
		"family": family,
		"label": label,
		"kind": kind,
		"preview_path": path,
		"letter": letter,
	}


static func _read_manifest() -> Dictionary:
	var path := CocTileCatalog.MANIFEST_PATH
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
