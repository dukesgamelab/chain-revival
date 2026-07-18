class_name AssetBrowserCatalog
extends RefCounted
## Editor asset browser built from:
##   1) assets/data/editor_asset_catalog.json  — editable labels / categories (source of truth for names)
##   2) assets/sprites/coc_tiles/manifest.json — which CoC families have sprites
##   3) optional MapData — guarantees every family used on the open map appears

const CATALOG_PATH := "res://assets/data/editor_asset_catalog.json"
const MANIFEST_PATH := "res://assets/sprites/coc_tiles/manifest.json"

const DEFAULT_CATEGORY_ORDER: PackedStringArray = [
	"On This Map",
	"Terrain",
	"Floors",
	"Walls",
	"Corners",
	"Windows",
	"Doors",
	"Trees",
	"Bushes",
	"Props",
	"Rocks",
	"Hay",
	"Vehicles",
	"Special",
	"Spawn Points",
	"Victory Points",
	"Labels",
]

static var _catalog_cache: Dictionary = {}
static var _catalog_loaded: bool = false


static func catalog_path() -> String:
	return CATALOG_PATH


static func reload() -> void:
	_catalog_loaded = false
	_catalog_cache.clear()
	_ensure_catalog()


static func category_order() -> PackedStringArray:
	_ensure_catalog()
	var order: Variant = _catalog_cache.get("category_order", [])
	var packed := PackedStringArray()
	if order is Array and not order.is_empty():
		for item in order:
			packed.append(str(item))
		return packed
	return DEFAULT_CATEGORY_ORDER.duplicate()


static func build_categories(map_data: MapData = null) -> Dictionary:
	## category -> Array[{ family, label, kind, preview_path, letter, category, sort }]
	_ensure_catalog()
	CocTileCatalog.ensure_loaded()
	_sync_manifest_families()
	var map_families := _families_on_map(map_data)
	for fam in map_families:
		_ensure_entry(fam)

	var categories: Dictionary = {}
	for cat in category_order():
		categories[cat] = []

	var entries: Dictionary = _catalog_cache.get("entries", {})
	var sorted_keys: Array = entries.keys()
	sorted_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ea: Dictionary = entries[a]
		var eb: Dictionary = entries[b]
		var sa := int(ea.get("sort", 100))
		var sb := int(eb.get("sort", 100))
		if sa == sb:
			return str(ea.get("label", a)) < str(eb.get("label", b))
		return sa < sb
	)

	for key in sorted_keys:
		var fam := str(key).to_upper()
		var entry: Dictionary = entries[key]
		var cat := str(entry.get("category", categorize_family(fam)))
		if not categories.has(cat):
			categories[cat] = []
		var item := _item_from_entry(fam, entry)
		categories[cat].append(item)
		if map_families.has(fam) and cat != "On This Map":
			## Duplicate under On This Map for quick access (same brush metadata).
			var map_item := item.duplicate(true)
			map_item["category"] = "On This Map"
			categories["On This Map"].append(map_item)

	## Stable sort for On This Map by label.
	var on_map: Array = categories.get("On This Map", [])
	on_map.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	categories["On This Map"] = on_map
	return categories


static func rename_family(family: String, new_label: String) -> bool:
	_ensure_catalog()
	var fam := family.to_upper()
	var entries: Dictionary = _catalog_cache.get("entries", {})
	if not entries.has(fam):
		_ensure_entry(fam)
	var entry: Dictionary = entries[fam]
	var label := new_label.strip_edges()
	if label.is_empty():
		return false
	entry["label"] = label
	entries[fam] = entry
	_catalog_cache["entries"] = entries
	return _save_catalog()


static func set_family_category(family: String, category: String) -> bool:
	_ensure_catalog()
	var fam := family.to_upper()
	var cat := category.strip_edges()
	if cat.is_empty():
		return false
	var entries: Dictionary = _catalog_cache.get("entries", {})
	if not entries.has(fam):
		_ensure_entry(fam)
	var entry: Dictionary = entries[fam]
	entry["category"] = cat
	entries[fam] = entry
	_catalog_cache["entries"] = entries
	## Keep category_order aware of custom categories.
	var order: Array = _catalog_cache.get("category_order", [])
	if order is Array and not order.has(cat) and cat != "On This Map":
		## Insert before Spawn Points if present, else append.
		var spawn_i := order.find("Spawn Points")
		if spawn_i >= 0:
			order.insert(spawn_i, cat)
		else:
			order.append(cat)
		_catalog_cache["category_order"] = order
	return _save_catalog()


static func display_label(family: String) -> String:
	_ensure_catalog()
	var fam := family.to_upper()
	var entries: Dictionary = _catalog_cache.get("entries", {})
	if entries.has(fam):
		return str(entries[fam].get("label", fam))
	return fam


static func categorize_family(family: String) -> String:
	var fam := family.to_upper()
	if fam == "GRS":
		return "Terrain"
	if CocRenderRules.is_floor_family(fam):
		return "Floors"
	if fam.begins_with("WH") or fam.ends_with("WIN") or fam in ["SWIN", "WWIN", "WH11"]:
		return "Windows"
	if fam in ["WWAR", "WWAQ", "SWAR", "SWAQ", "WWAI", "SDOR", "WDOR"]:
		return "Doors"
	if fam.ends_with("COR") or fam.ends_with("ICR") or fam == "IWCR":
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


static func _ensure_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	_catalog_cache = _read_json_dict(CATALOG_PATH)
	if _catalog_cache.is_empty():
		_catalog_cache = {
			"category_order": Array(DEFAULT_CATEGORY_ORDER),
			"entries": {},
		}
	if not _catalog_cache.has("entries") or not _catalog_cache["entries"] is Dictionary:
		_catalog_cache["entries"] = {}
	if not _catalog_cache.has("category_order") or not _catalog_cache["category_order"] is Array:
		_catalog_cache["category_order"] = Array(DEFAULT_CATEGORY_ORDER)
	## Marker markers always present.
	_ensure_entry("SPAWN_USA", "USA Spawn", "Spawn Points", "spawn_usa")
	_ensure_entry("SPAWN_GER", "Germany Spawn", "Spawn Points", "spawn_ger")
	_ensure_entry("VP", "Victory Point", "Victory Points", "victory")
	_ensure_entry("LABEL", "Label", "Labels", "label")


static func _sync_manifest_families() -> void:
	var root := _read_json_dict(MANIFEST_PATH)
	var sprites: Variant = root.get("sprites", [])
	if not sprites is Array:
		return
	var seen: Dictionary = {}
	for entry in sprites:
		if not entry is Dictionary:
			continue
		var fam := str(entry.get("family", "")).to_upper()
		if fam.is_empty() or seen.has(fam):
			continue
		## Soldier idle families are not map props.
		if fam == "ASAX" or fam == "ASID":
			continue
		seen[fam] = true
		_ensure_entry(fam)


static func _ensure_entry(
	family: String,
	label: String = "",
	category: String = "",
	kind: String = "",
) -> void:
	var fam := family.to_upper()
	var entries: Dictionary = _catalog_cache.get("entries", {})
	if entries.has(fam):
		return
	var resolved_kind := kind
	if resolved_kind.is_empty():
		resolved_kind = "terrain" if fam == "GRS" else "family"
	var resolved_cat := category if not category.is_empty() else categorize_family(fam)
	var resolved_label := label if not label.is_empty() else _default_label(fam)
	entries[fam] = {
		"label": resolved_label,
		"category": resolved_cat,
		"kind": resolved_kind,
		"sort": 100,
	}
	_catalog_cache["entries"] = entries


static func _default_label(family: String) -> String:
	var fam := family.to_upper()
	if fam == "GRS":
		return "Ground Grass"
	return "%s (%s)" % [fam, fam]


static func _families_on_map(map_data: MapData) -> Dictionary:
	var found: Dictionary = {}
	if map_data == null:
		return found
	for entry in map_data.visual_placements:
		var fam := str(entry.get("family", "")).to_upper()
		if fam.is_empty():
			var source: Dictionary = entry.get("source", {}) if entry.get("source", {}) is Dictionary else {}
			fam = str(source.get("image", "")).to_upper()
		if not fam.is_empty() and fam != "NEAR":
			found[fam] = true
	for entry in map_data.floors:
		var fam := str(entry.get("image", "")).to_upper()
		if not fam.is_empty():
			found[fam] = true
	for entry in map_data.decoration:
		var fam := str(entry.get("image", "")).to_upper()
		if not fam.is_empty():
			found[fam] = true
	return found


static func _item_from_entry(family: String, entry: Dictionary) -> Dictionary:
	var kind := str(entry.get("kind", "family"))
	var label := str(entry.get("label", family))
	## Show code alongside label so search still finds WWAL, etc.
	var display := label
	if kind == "family" or kind == "terrain":
		if label.to_upper().find(family) < 0:
			display = "%s  [%s]" % [label, family]
	var path := ""
	var letter := ""
	if kind == "family" or kind == "terrain":
		var resolved := CocSpriteResolver.resolve_preview(family, 0)
		path = str(resolved.get("path", ""))
		letter = str(resolved.get("letter", ""))
	return {
		"family": family,
		"label": display,
		"edit_label": label,
		"kind": kind,
		"category": str(entry.get("category", categorize_family(family))),
		"sort": int(entry.get("sort", 100)),
		"preview_path": path,
		"letter": letter,
	}


static func _save_catalog() -> bool:
	var abs_path := ProjectSettings.globalize_path(CATALOG_PATH)
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		## Fallback: try res path (works in editor export-disabled writes sometimes).
		file = FileAccess.open(CATALOG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("AssetBrowserCatalog: could not write %s" % CATALOG_PATH)
		return false
	file.store_string(JSON.stringify(_catalog_cache, "\t"))
	file.store_string("\n")
	return true


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
