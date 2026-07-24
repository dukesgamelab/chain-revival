class_name CocTileCatalog
extends RefCounted
## Metadata-driven CoC tile catalog from the Fortress handoff package.

const MANIFEST_PATH := "res://assets/sprites/coc_tiles/manifest.json"
const FACETS_PATH := "res://assets/data/facets_by_family.json"
const FALLBACKS_PATH := "res://assets/data/irregular_fallbacks.json"
const SPRITE_ROOT := "res://assets/sprites/coc_tiles"
const DEFAULT_HOTSPOT := Vector2(-50, -73)
## Reference renderer GRS filter: drop color outliers (e.g. neon 8GRS9_8A).
const GRS_COLOR_TARGET := Vector3(143.0, 143.0, 108.0)
const GRS_COLOR_MAX_DIST := 40.0

static var _loaded: bool = false
## "FAMILY|letter|anim" -> { path, hotspot, size }
static var _sprite_index: Dictionary = {}
## "FAMILY" -> facet count (int); irregular families still report 4 for quantizer
static var _facet_counts: Dictionary = {}
## "FAMILY" -> PackedStringArray of authored letters
static var _family_letters: Dictionary = {}
## "FAMILY" -> { missing_letter, replacement_letter }
static var _fallbacks: Dictionary = {}
static var _ground_paths: Array[String] = []
static var _ground_hotspots: Array[Vector2] = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	reload()


static func reload() -> void:
	_loaded = true
	_sprite_index.clear()
	_facet_counts.clear()
	_family_letters.clear()
	_fallbacks.clear()
	_ground_paths.clear()
	_ground_hotspots.clear()
	_load_manifest()
	_load_facets()
	_load_fallbacks()


static func resolve(
	family: String,
	letter: String,
	anim_frame: int = 0,
) -> Dictionary:
	ensure_loaded()
	var fam := family.to_upper()
	var let := letter.to_lower()
	let = apply_irregular_fallback(fam, let)
	var key := _key(fam, let, anim_frame)
	if _sprite_index.has(key):
		return (_sprite_index[key] as Dictionary).duplicate()
	## Prefer anim_frame 0 if a specific frame is missing.
	if anim_frame != 0:
		key = _key(fam, let, 0)
		if _sprite_index.has(key):
			return (_sprite_index[key] as Dictionary).duplicate()
	return {}


static func facet_count(family: String) -> int:
	ensure_loaded()
	var fam := family.to_upper()
	if _facet_counts.has(fam):
		return int(_facet_counts[fam])
	## Infer from authored letters when facets file has no entry.
	if _family_letters.has(fam):
		var letters: PackedStringArray = _family_letters[fam]
		var n := letters.size()
		if n >= 8:
			return 8
		if n >= 4:
			return 4
		if n == 2:
			return 2
		return 1
	return 1


static func apply_irregular_fallback(family: String, letter: String) -> String:
	ensure_loaded()
	var fam := family.to_upper()
	var let := letter.to_lower()
	if not _fallbacks.has(fam):
		return let
	var rule: Dictionary = _fallbacks[fam]
	if let == str(rule.get("missing_letter", "")).to_lower():
		return str(rule.get("replacement_letter", let)).to_lower()
	return let


static func ground_variant_count() -> int:
	ensure_loaded()
	return _ground_paths.size()


static func ground_sprite(index: int) -> Dictionary:
	ensure_loaded()
	if _ground_paths.is_empty():
		return {}
	var i := posmod(index, _ground_paths.size())
	return {
		"path": _ground_paths[i],
		"hotspot": _ground_hotspots[i] if i < _ground_hotspots.size() else DEFAULT_HOTSPOT,
	}


static func exists(path: String) -> bool:
	if path.is_empty():
		return false
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


static func letters_for_family(family: String) -> PackedStringArray:
	ensure_loaded()
	var fam := family.to_upper()
	if not _family_letters.has(fam):
		return PackedStringArray()
	return (_family_letters[fam] as PackedStringArray).duplicate()


static func family_ids() -> PackedStringArray:
	ensure_loaded()
	var ids: Array = _family_letters.keys()
	ids.sort()
	var out := PackedStringArray()
	for id in ids:
		out.append(str(id))
	return out


## Unique static facets (anim_frame 0). Optional family filter.
static func list_sprites(family_filter: String = "") -> Array:
	ensure_loaded()
	var fam_f := family_filter.to_upper()
	var seen: Dictionary = {}
	var out: Array = []
	for key in _sprite_index.keys():
		var rec: Variant = _sprite_index[key]
		if not rec is Dictionary:
			continue
		var entry: Dictionary = rec
		if int(entry.get("anim_frame", 0)) != 0:
			continue
		var fam := str(entry.get("family", "")).to_upper()
		if fam.is_empty():
			continue
		if not fam_f.is_empty() and fam != fam_f:
			continue
		var letter := str(entry.get("letter", "e")).to_lower()
		var id := "%s_%s" % [fam, letter]
		if seen.has(id):
			continue
		seen[id] = true
		var path := str(entry.get("path", ""))
		var hotspot: Vector2 = entry.get("hotspot", DEFAULT_HOTSPOT)
		out.append(
			{
				"family": fam,
				"letter": letter,
				"facet": id,
				"path": path,
				"rel_path": path.trim_prefix("res://assets/"),
				"hotspot": [int(hotspot.x), int(hotspot.y)],
			}
		)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := "%s_%s" % [a.get("family", ""), a.get("letter", "")]
		var kb := "%s_%s" % [b.get("family", ""), b.get("letter", "")]
		return ka < kb
	)
	return out


static func _load_manifest() -> void:
	var root := _read_json_dict(MANIFEST_PATH)
	var sprites: Variant = root.get("sprites", [])
	if not sprites is Array:
		return
	for entry in sprites:
		if not entry is Dictionary:
			continue
		var fam := str(entry.get("family", "")).to_upper()
		var letter := str(entry.get("letter", "e")).to_lower()
		var anim := int(entry.get("anim_frame", 0))
		var rel := str(entry.get("path", ""))
		var path := _to_res_path(rel)
		var hotspot := _hotspot_from(entry.get("hotspot", [-50, -73]))
		var size_raw: Variant = entry.get("size", [100, 100])
		var size := Vector2(100, 100)
		if size_raw is Array and size_raw.size() >= 2:
			size = Vector2(float(size_raw[0]), float(size_raw[1]))
		var record := {
			"family": fam,
			"letter": letter,
			"anim_frame": anim,
			"path": path,
			"hotspot": hotspot,
			"size": size,
		}
		_sprite_index[_key(fam, letter, anim)] = record
		if not _family_letters.has(fam):
			_family_letters[fam] = PackedStringArray()
		var letters: PackedStringArray = _family_letters[fam]
		if not letters.has(letter):
			letters.append(letter)
			_family_letters[fam] = letters
		if fam == "GRS" and not _is_grs_color_outlier(path):
			_ground_paths.append(path)
			_ground_hotspots.append(hotspot)


static func _load_facets() -> void:
	var root := _read_json_dict(FACETS_PATH)
	var families: Variant = root.get("families", {})
	if not families is Dictionary:
		return
	for key in families.keys():
		var entry: Variant = families[key]
		if not entry is Dictionary:
			continue
		var fam := str(key).split(":")[0].to_upper()
		var facets_raw: Variant = entry.get("facets", 1)
		var count := 1
		if facets_raw is float or facets_raw is int:
			count = int(facets_raw)
		elif str(facets_raw).begins_with("IRREGULAR"):
			## Quantize as 4-facing; missing letters handled by irregular_fallbacks.
			count = 4
		_facet_counts[fam] = count
		var letters_raw: Variant = entry.get("letters", [])
		if letters_raw is Array:
			var packed := PackedStringArray()
			for letter in letters_raw:
				packed.append(str(letter).to_lower())
			_family_letters[fam] = packed


static func _load_fallbacks() -> void:
	var root := _read_json_dict(FALLBACKS_PATH)
	for fam_key in root.keys():
		var entry: Variant = root[fam_key]
		if not entry is Dictionary:
			continue
		var fam := str(fam_key).to_upper()
		var missing := str(entry.get("missing_letter", "")).to_lower()
		var replacement := missing
		## Parse compatibility_rule text for the documented replacement letter.
		var rule := str(entry.get("compatibility_rule", "")).to_lower()
		if fam == "LIHW" and missing == "e":
			replacement = "w"
		elif fam == "ASID" and missing == "s":
			replacement = "se"
		elif rule.find("use the ") >= 0:
			## Best-effort parse: "use the w frame" / "use se"
			pass
		_fallbacks[fam] = {
			"missing_letter": missing,
			"replacement_letter": replacement,
		}


static func _key(family: String, letter: String, anim_frame: int) -> String:
	return "%s|%s|%d" % [family.to_upper(), letter.to_lower(), anim_frame]


static func _to_res_path(rel: String) -> String:
	if rel.is_empty():
		return ""
	if rel.begins_with("res://"):
		return rel
	var name := rel.replace("\\", "/").get_file()
	return "%s/%s" % [SPRITE_ROOT, name]


static func _hotspot_from(raw: Variant) -> Vector2:
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return DEFAULT_HOTSPOT


## Match reference_renderer.py: keep GRS whose mean opaque RGB is near olive grass.
static func _is_grs_color_outlier(path: String) -> bool:
	if path.is_empty() or not exists(path):
		return true
	var texture := load(path) as Texture2D
	if texture == null:
		return true
	var image := texture.get_image()
	if image == null:
		return true
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)
	var sum_r := 0.0
	var sum_g := 0.0
	var sum_b := 0.0
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			sum_r += c.r * 255.0
			sum_g += c.g * 255.0
			sum_b += c.b * 255.0
			count += 1
	if count <= 0:
		return true
	var mean := Vector3(sum_r / count, sum_g / count, sum_b / count)
	var dist := absf(mean.x - GRS_COLOR_TARGET.x) + absf(mean.y - GRS_COLOR_TARGET.y) + absf(mean.z - GRS_COLOR_TARGET.z)
	return dist >= GRS_COLOR_MAX_DIST


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CocTileCatalog: missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}
