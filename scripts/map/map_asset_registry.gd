class_name MapAssetRegistry
extends RefCounted
## Authorable static CoC map-object families.
## Shared gameplay is per-family; camera_variants are presentation-only.

const PATH := "res://assets/data/map_asset_registry.json"
const CAMERA_KEYS: PackedStringArray = ["0", "90", "180", "270"]
const MapObjectRegistryClass := preload("res://scripts/map/map_object_registry.gd")
const MapObjectDefClass := preload("res://scripts/map/map_object_def.gd")
const MapObjectDefinitionClass := preload("res://scripts/map/map_object_definition.gd")

static var _root: Dictionary = {}
static var _loaded: bool = false


static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_root = {"version": 1, "families": {}}
	if not FileAccess.file_exists(PATH):
		push_warning("MapAssetRegistry: missing %s" % PATH)
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("MapAssetRegistry: could not read %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_warning("MapAssetRegistry: invalid JSON in %s" % PATH)
		return
	_root = parsed
	if not _root.has("families") or not _root["families"] is Dictionary:
		_root["families"] = {}


static func save() -> Error:
	ensure_loaded()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify(_root, "\t") + "\n")
	return OK


static func family_ids() -> PackedStringArray:
	ensure_loaded()
	var ids: Array = (_root.get("families", {}) as Dictionary).keys()
	ids.sort()
	var out := PackedStringArray()
	for id in ids:
		out.append(str(id).to_upper())
	return out


static func has_family(family: String) -> bool:
	ensure_loaded()
	var fam := family.to_upper()
	if fam.is_empty():
		return false
	return (_root.get("families", {}) as Dictionary).has(fam)


static func get_entry(family: String) -> Dictionary:
	ensure_loaded()
	var fam := family.to_upper()
	var families: Dictionary = _root.get("families", {})
	if not families.has(fam):
		return {}
	var entry: Variant = families[fam]
	return entry if entry is Dictionary else {}


static func gameplay_for(family: String) -> Dictionary:
	var entry := get_entry(family)
	if entry.is_empty():
		return {}
	var gp: Variant = entry.get("gameplay", {})
	return gp.duplicate(true) if gp is Dictionary else {}


static func camera_variant(family: String, camera_deg: int) -> Dictionary:
	var entry := get_entry(family)
	if entry.is_empty():
		return {}
	var variants: Variant = entry.get("camera_variants", {})
	if not variants is Dictionary:
		return {}
	var key := str(posmod(camera_deg, 360))
	if not CAMERA_KEYS.has(key):
		key = "0"
	var variant: Variant = variants.get(key, {})
	if not variant is Dictionary or (variant as Dictionary).is_empty():
		variant = variants.get("0", {})
	return variant.duplicate(true) if variant is Dictionary else {}


static func usage_count(family: String) -> int:
	return int(get_entry(family).get("usage_ff_farm", 0))


static func has_unresolved_variants(family: String) -> bool:
	var entry := get_entry(family)
	var variants: Variant = entry.get("camera_variants", {})
	if not variants is Dictionary:
		return true
	for key in CAMERA_KEYS:
		var v: Variant = variants.get(key, {})
		if not v is Dictionary:
			return true
		if bool((v as Dictionary).get("fallback", false)):
			return true
		if str((v as Dictionary).get("facet", "")).is_empty():
			return true
	return false


static func set_display_meta(
	family: String,
	display_name: String = "",
	category: String = "",
	material: String = "",
	height_band: String = "",
	notes: String = "",
) -> void:
	var entry := _mutable_entry(family)
	if not display_name.is_empty():
		entry["display_name"] = display_name
	if not category.is_empty():
		entry["category"] = category
	entry["material"] = material
	entry["height_band"] = height_band
	entry["notes"] = notes


static func set_gameplay(family: String, gameplay: Dictionary) -> void:
	var entry := _mutable_entry(family)
	var gp: Dictionary = entry.get("gameplay", {}).duplicate(true) if entry.get("gameplay", {}) is Dictionary else {}
	for key in gameplay.keys():
		gp[key] = gameplay[key]
	entry["gameplay"] = gp


static func set_camera_variant(family: String, camera_deg: int, variant: Dictionary) -> void:
	var entry := _mutable_entry(family)
	var variants: Dictionary = {}
	if entry.get("camera_variants", {}) is Dictionary:
		variants = (entry["camera_variants"] as Dictionary).duplicate(true)
	var key := str(posmod(camera_deg, 360))
	var current: Dictionary = variants.get(key, {}).duplicate(true) if variants.get(key, {}) is Dictionary else {}
	for k in variant.keys():
		current[k] = variant[k]
	current["fallback"] = false
	variants[key] = current
	entry["camera_variants"] = variants


static func ensure_family(family: String, seed_data: Dictionary = {}) -> void:
	var fam := family.to_upper()
	if fam.is_empty():
		return
	ensure_loaded()
	var families: Dictionary = _root.get("families", {})
	if families.has(fam):
		return
	var entry := seed_data.duplicate(true) if not seed_data.is_empty() else _blank_entry(fam)
	entry["family"] = fam
	families[fam] = entry
	_root["families"] = families


static func map_object_def_for(family: String, type_id: String = "") -> MapObjectDef:
	## Build a runtime MapObjectDef from registry gameplay (fallback-safe).
	var fam := family.to_upper()
	var tid := type_id
	if tid.is_empty():
		tid = MapObjectDefinitionClass.type_id_for_family(fam)
	var gp := gameplay_for(fam)
	var entry := get_entry(fam)
	var display := str(entry.get("display_name", fam))
	if gp.is_empty():
		return MapObjectRegistryClass.get_def(tid)
	return MapObjectDefClass.new(
		tid,
		display if not display.is_empty() else tid,
		bool(gp.get("blocks_movement", true)),
		bool(gp.get("blocks_los", true)),
		bool(gp.get("provides_cover", true)),
		int(gp.get("cover_type", 0)),
		"",
	)


static func audit_farm_fight(farm_path: String = "res://maps/ff_farm.json") -> Dictionary:
	ensure_loaded()
	var farm_families: Dictionary = {}
	if FileAccess.file_exists(farm_path):
		var file := FileAccess.open(farm_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				for o in (parsed as Dictionary).get("map_objects", []):
					if not o is Dictionary:
						continue
					var src: Variant = (o as Dictionary).get("source", {})
					if src is Dictionary:
						var fam := str(src.get("image", "")).to_upper()
						if not fam.is_empty():
							farm_families[fam] = int(farm_families.get(fam, 0)) + 1
				for o in (parsed as Dictionary).get("decoration", []):
					if not o is Dictionary:
						continue
					var fam2 := str((o as Dictionary).get("image", "")).to_upper()
					if not fam2.is_empty():
						farm_families[fam2] = int(farm_families.get(fam2, 0)) + 1
	var registered: PackedStringArray = family_ids()
	var missing: Array = []
	var incomplete: Array = []
	var fallback_gameplay: Array = []
	for fam in farm_families.keys():
		if not has_family(str(fam)):
			missing.append(str(fam))
		elif has_unresolved_variants(str(fam)):
			incomplete.append(str(fam))
	for fam in registered:
		var gp := gameplay_for(fam)
		if gp.is_empty():
			fallback_gameplay.append(fam)
	return {
		"farm_unique_families": farm_families.keys().size(),
		"farm_families": farm_families,
		"registered_families": registered.size(),
		"missing_families": missing,
		"incomplete_camera_variants": incomplete,
		"fallback_gameplay": fallback_gameplay,
	}


static func _mutable_entry(family: String) -> Dictionary:
	ensure_family(family)
	var fam := family.to_upper()
	var families: Dictionary = _root.get("families", {})
	var entry: Dictionary = (families[fam] as Dictionary).duplicate(true)
	families[fam] = entry
	_root["families"] = families
	return entry


static func _blank_entry(family: String) -> Dictionary:
	var variants := {}
	for key in CAMERA_KEYS:
		variants[key] = {
			"letter": "e",
			"facet": "%s_e" % family,
			"path": "sprites/coc_tiles/%s_e.png" % family,
			"hotspot": [-50, -73],
			"render_offset": [0, 0],
			"depth_offset": 0,
			"fallback": true,
		}
	return {
		"family": family,
		"display_name": family,
		"category": "prop",
		"material": "",
		"height_band": "",
		"notes": "",
		"usage_ff_farm": 0,
		"gameplay": {
			"terrain": "_HG_EVEN",
			"terrain_height": 0,
			"blocks_movement": false,
			"blocks_los": false,
			"blocks_bullets": false,
			"provides_cover": false,
			"cover_type": 0,
			"concealment": 0.0,
			"suppression_modifier": 0.0,
		},
		"camera_variants": variants,
	}
