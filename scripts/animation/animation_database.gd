class_name AnimationDatabase
extends RefCounted
## Data-driven animation source of truth (assets/data/animation_database.json).
##
## Gameplay asks: family + animation + world facing + camera rotation → frame paths.
## Does not replace UsSoldierSpriteFrames yet; that loader can prefer this DB with fallback.

const DB_PATH := "res://assets/data/animation_database.json"
const DIRECTIONS: PackedStringArray = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]

static var _root: Dictionary = {}
static var _loaded: bool = false
static var _json_load_msec: float = 0.0


static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	var t0 := Time.get_ticks_usec()
	var json_bytes := _json_file_byte_size(DB_PATH)
	_root = _read_json(DB_PATH)
	_json_load_msec = float(Time.get_ticks_usec() - t0) / 1000.0
	_loaded = true
	if _root.is_empty():
		_root = {
			"version": 1,
			"directions_order": Array(DIRECTIONS),
			"camera_rotation_maps": _default_camera_maps(),
			"families": {},
		}
	GameLog.log_system(
		"[Load] animation_database.json parse %.1fms (%d bytes)"
		% [_json_load_msec, json_bytes]
	)


static func save() -> bool:
	ensure_loaded()
	var path := ProjectSettings.globalize_path(DB_PATH)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		## Fallback for editor when res:// write is blocked.
		file = FileAccess.open(DB_PATH, FileAccess.WRITE)
	if file == null:
		push_error("AnimationDatabase: could not write %s" % DB_PATH)
		return false
	file.store_string(JSON.stringify(_root, "\t"))
	file.close()
	return true


static func get_root() -> Dictionary:
	ensure_loaded()
	return _root


static func family_ids() -> PackedStringArray:
	ensure_loaded()
	var families: Dictionary = _root.get("families", {})
	var ids: PackedStringArray = PackedStringArray()
	var keys: Array = families.keys()
	keys.sort()
	for k in keys:
		ids.append(str(k))
	return ids


static func get_family(family_id: String) -> Dictionary:
	ensure_loaded()
	var families: Dictionary = _root.get("families", {})
	var fam: Variant = families.get(family_id, {})
	return fam if fam is Dictionary else {}


static func upsert_family(family: Dictionary) -> void:
	ensure_loaded()
	var families: Dictionary = _root.get("families", {})
	var fid := str(family.get("id", "")).strip_edges()
	if fid.is_empty():
		return
	families[fid] = family
	_root["families"] = families


static func remove_family(family_id: String) -> void:
	ensure_loaded()
	var families: Dictionary = _root.get("families", {})
	families.erase(family_id)
	_root["families"] = families


static func get_animation(family_id: String, anim_id: String) -> Dictionary:
	var fam := get_family(family_id)
	var anims: Dictionary = fam.get("animations", {})
	var anim: Variant = anims.get(anim_id, {})
	return anim if anim is Dictionary else {}


static func set_animation(family_id: String, anim_id: String, anim: Dictionary) -> void:
	var fam := get_family(family_id)
	if fam.is_empty():
		return
	var anims: Dictionary = fam.get("animations", {})
	anims[anim_id] = anim
	fam["animations"] = anims
	upsert_family(fam)


static func get_direction_frames(family_id: String, anim_id: String, direction: String) -> PackedStringArray:
	var anim := get_animation(family_id, anim_id)
	var dirs: Dictionary = anim.get("directions", {})
	var entry: Variant = dirs.get(direction.to_lower(), {})
	var packed := PackedStringArray()
	if entry is Dictionary:
		var frames: Variant = entry.get("frames", [])
		if frames is Array:
			for f in frames:
				packed.append(str(f))
	return packed


static func set_direction_frames(
	family_id: String,
	anim_id: String,
	direction: String,
	frames: PackedStringArray,
) -> void:
	var anim := get_animation(family_id, anim_id)
	if anim.is_empty():
		return
	var dirs: Dictionary = anim.get("directions", {})
	dirs[direction.to_lower()] = {"frames": Array(frames)}
	anim["directions"] = dirs
	set_animation(family_id, anim_id, anim)


## Resolve display direction after camera rotation (configurable lookup, not hardcoded swaps).
static func display_direction(world_facing: String, camera_degrees: int) -> String:
	ensure_loaded()
	var world := world_facing.to_lower()
	var cam_key := str(posmod(camera_degrees, 360))
	## Snap to nearest 90°.
	var snapped := int(round(float(posmod(camera_degrees, 360)) / 90.0) * 90) % 360
	cam_key = str(snapped)
	var maps: Dictionary = _root.get("camera_rotation_maps", {})
	var table: Variant = maps.get(cam_key, {})
	if table is Dictionary and table.has(world):
		return str(table[world]).to_lower()
	return world


## Primary gameplay API: which frames to draw.
static func resolve_frames(
	family_id: String,
	anim_id: String,
	world_facing: String,
	camera_degrees: int = 0,
) -> PackedStringArray:
	var display := display_direction(world_facing, camera_degrees)
	return get_direction_frames(family_id, anim_id, display)


static func resolve_anim_meta(family_id: String, anim_id: String) -> Dictionary:
	var anim := get_animation(family_id, anim_id)
	return {
		"loop": bool(anim.get("loop", true)),
		"fps": float(anim.get("fps", 12.0)),
		"metadata": anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {},
	}


## Faction pools for authoritative dead_static corpse-family selection.
const USA_DEAD_STATIC_VARIANTS: PackedStringArray = ["ADDSS", "ADOAS", "ADFUS", "ADLYS"]
const GERMANY_DEAD_STATIC_VARIANTS: PackedStringArray = ["GDLYS", "GDFUS"]


static func dead_static_variants_for_team(team_id: int) -> PackedStringArray:
	ensure_loaded()
	var family_id := "germany" if team_id == 2 else "usa"
	var fam := get_family(family_id)
	var meta: Variant = fam.get("metadata", {})
	if meta is Dictionary:
		var raw: Variant = meta.get("dead_static_variants", [])
		if raw is Array and not raw.is_empty():
			var out := PackedStringArray()
			for v in raw:
				var code := str(v).strip_edges().to_upper()
				if not code.is_empty():
					out.append(code)
			if not out.is_empty():
				return out
	if team_id == 2:
		return GERMANY_DEAD_STATIC_VARIANTS.duplicate()
	return USA_DEAD_STATIC_VARIANTS.duplicate()


static func dead_static_anim_id(family_code: String) -> String:
	return "dead_static_%s" % family_code.strip_edges().to_upper()


static func source_direction_digit(direction: String) -> int:
	match direction.to_lower():
		"w":
			return 1
		"sw":
			return 2
		"s":
			return 3
		"se":
			return 4
		"e":
			return 5
		"ne":
			return 6
		"n":
			return 7
		"nw":
			return 8
		_:
			return 7


## Soldier runtime expects walk_/hit_/hit_standing_/hit_prone_/fall_/dead_ prefixes.
static func build_soldier_compatible_sprite_frames(family_id: String) -> SpriteFrames:
	ensure_loaded()
	var t0 := Time.get_ticks_usec()
	var exists_usec := 0
	var load_usec := 0
	var textures_loaded := 0
	var textures_missing := 0
	var animations_built := 0
	var sf := SpriteFrames.new()
	var fam := get_family(family_id)
	if fam.is_empty():
		return sf
	var alias := {
		"walk": "walk",
		"hit": "hit",
		"hit_standing": "hit_standing",
		"hit_prone": "hit_prone",
		"throw_grenade": "throw_grenade",
		"fire_standing": "fire_standing",
		"fire_prone": "fire_prone",
		"corner_fire_left": "corner_fire_left",
		"corner_fire_right": "corner_fire_right",
		"corner_aim_left": "corner_aim_left",
		"corner_aim_right": "corner_aim_right",
		"corner_peek_left": "corner_peek_left",
		"corner_peek_right": "corner_peek_right",
		"corner_peek_enter_left": "corner_peek_enter_left",
		"corner_peek_enter_right": "corner_peek_enter_right",
		"corner_peek_exit_left": "corner_peek_exit_left",
		"corner_peek_exit_right": "corner_peek_exit_right",
		"idle_standing": "idle_standing",
		"idle_crouch": "idle_crouch",
		"corner_idle_left": "corner_idle_left",
		"corner_idle_right": "corner_idle_right",
		"idle_prone": "idle_prone",
		"transition_standing_to_prone": "transition_standing_to_prone",
		"transition_prone_to_standing": "transition_prone_to_standing",
		"stun_knockdown": "stun_knockdown",
		"stun_idle": "stun_idle",
		"stun_recover": "stun_recover",
		"aim_standing": "aim_standing",
		"aim_standing_hold": "aim_standing_hold",
		"aim_prone_hold": "aim_prone_hold",
		"death": "fall",
		"corpse": "dead",
		"idle": "idle",
	}
	var anims: Dictionary = fam.get("animations", {})
	for anim_id_v in anims.keys():
		var anim_id := str(anim_id_v)
		var runtime_prefix := str(alias.get(anim_id, anim_id))
		## dead_static_ADFUS → dead_ADFUS_* (static corpse variant families).
		if anim_id.begins_with("dead_static_"):
			var code := anim_id.substr("dead_static_".length()).strip_edges().to_upper()
			if not code.is_empty():
				runtime_prefix = "dead_%s" % code
		var anim: Dictionary = anims[anim_id]
		var loop := bool(anim.get("loop", true))
		var fps := float(anim.get("fps", 12.0))
		var dirs: Dictionary = anim.get("directions", {})
		for direction in DIRECTIONS:
			var anim_name := "%s_%s" % [runtime_prefix, direction]
			var entry: Variant = dirs.get(direction, {})
			var frame_paths: Array = []
			if entry is Dictionary:
				var raw: Variant = entry.get("frames", [])
				if raw is Array:
					frame_paths = raw
			if sf.has_animation(anim_name):
				sf.remove_animation(anim_name)
			sf.add_animation(anim_name)
			sf.set_animation_loop(anim_name, loop)
			sf.set_animation_speed(anim_name, fps if fps > 0.0 else 1.0)
			animations_built += 1
			for path_v in frame_paths:
				var path := str(path_v)
				if path.is_empty():
					continue
				var exists_t := Time.get_ticks_usec()
				var path_ok := ResourceLoader.exists(path) or FileAccess.file_exists(path)
				exists_usec += Time.get_ticks_usec() - exists_t
				if not path_ok:
					push_error(
						"AnimationDatabase: missing frame path %s (%s/%s/%s) — not substituted"
						% [path, family_id, anim_id, direction]
					)
					textures_missing += 1
					continue
				var load_t := Time.get_ticks_usec()
				var tex: Texture2D = load(path) as Texture2D
				load_usec += Time.get_ticks_usec() - load_t
				if tex != null:
					sf.add_frame(anim_name, tex, 1.0)
					textures_loaded += 1
				else:
					push_error(
						"AnimationDatabase: failed to load texture %s (%s/%s/%s)"
						% [path, family_id, anim_id, direction]
					)
					textures_missing += 1
	var total_msec := float(Time.get_ticks_usec() - t0) / 1000.0
	GameLog.log_system(
		"[Load] sprite_frames %s: %d anims, %d textures (missing %d), exists %.0fms load %.0fms total %.0fms"
		% [
			family_id,
			animations_built,
			textures_loaded,
			textures_missing,
			float(exists_usec) / 1000.0,
			float(load_usec) / 1000.0,
			total_msec,
		]
	)
	return sf


## Build SpriteFrames for a family from the DB (generic anim_id_direction names).
static func build_sprite_frames(family_id: String) -> SpriteFrames:
	ensure_loaded()
	var sf := SpriteFrames.new()
	var fam := get_family(family_id)
	var anims: Dictionary = fam.get("animations", {})
	for anim_id in anims.keys():
		var anim: Dictionary = anims[anim_id]
		var loop := bool(anim.get("loop", true))
		var fps := float(anim.get("fps", 12.0))
		var dirs: Dictionary = anim.get("directions", {})
		for direction in DIRECTIONS:
			var anim_name := "%s_%s" % [anim_id, direction]
			var entry: Variant = dirs.get(direction, {})
			var frame_paths: Array = []
			if entry is Dictionary:
				var raw: Variant = entry.get("frames", [])
				if raw is Array:
					frame_paths = raw
			sf.add_animation(anim_name)
			sf.set_animation_loop(anim_name, loop)
			sf.set_animation_speed(anim_name, fps)
			for path_v in frame_paths:
				var path := str(path_v)
				if path.is_empty():
					continue
				if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
					push_error(
						"AnimationDatabase: missing frame path %s (%s/%s/%s) — not substituted"
						% [path, family_id, anim_id, direction]
					)
					continue
				var tex: Texture2D = load(path) as Texture2D
				if tex != null:
					sf.add_frame(anim_name, tex, 1.0)
				else:
					push_error(
						"AnimationDatabase: failed to load texture %s (%s/%s/%s)"
						% [path, family_id, anim_id, direction]
					)
	return sf


## Auto-detect CoC-style packs: PREFIX + digit(1-8) + frame letter.
static func auto_detect_from_folder(
	folder_res_path: String,
	prefix_filter: String = "",
) -> Dictionary:
	## Returns { prefix: { direction: PackedStringArray paths } }
	var result: Dictionary = {}
	var abs_path := ProjectSettings.globalize_path(folder_res_path)
	var dir := DirAccess.open(abs_path)
	if dir == null:
		dir = DirAccess.open(folder_res_path)
	if dir == null:
		return result
	var digit_map: Dictionary = _root.get("soldier_digit_to_direction", {}) if _loaded else {}
	if digit_map.is_empty():
		digit_map = {"1": "w", "2": "sw", "3": "s", "4": "se", "5": "e", "6": "ne", "7": "n", "8": "nw"}
	var regex := RegEx.new()
	regex.compile("^([A-Za-z]+)([1-8])([A-Za-z])\\.png$")
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var m := regex.search(file_name)
			if m != null:
				var prefix := m.get_string(1).to_upper()
				if prefix_filter.is_empty() or prefix == prefix_filter.to_upper():
					var digit := m.get_string(2)
					var direction := str(digit_map.get(digit, "n")).to_lower()
					var frame_letter := m.get_string(3).to_upper()
					if not result.has(prefix):
						result[prefix] = {}
					var by_dir: Dictionary = result[prefix]
					if not by_dir.has(direction):
						by_dir[direction] = []
					var list: Array = by_dir[direction]
					var res_path := folder_res_path.rstrip("/") + "/" + file_name
					list.append({"frame": frame_letter, "path": res_path})
					by_dir[direction] = list
					result[prefix] = by_dir
		file_name = dir.get_next()
	dir.list_dir_end()
	## Sort each direction by frame letter.
	for prefix in result.keys():
		var by_dir: Dictionary = result[prefix]
		for direction in by_dir.keys():
			var list: Array = by_dir[direction]
			list.sort_custom(func(a: Variant, b: Variant) -> bool:
				return str(a.get("frame", "")) < str(b.get("frame", ""))
			)
			var paths: Array = []
			for item in list:
				paths.append(str(item.get("path", "")))
			by_dir[direction] = paths
		result[prefix] = by_dir
	return result


static func make_empty_animation(loop: bool = true, fps: float = 12.0) -> Dictionary:
	var dirs: Dictionary = {}
	for d in DIRECTIONS:
		dirs[d] = {"frames": []}
	return {
		"loop": loop,
		"fps": fps,
		"metadata": {
			"movement_per_cycle": 0.0,
			"sound_effect": "",
			"muzzle_flash_frame": -1,
			"footstep_frame": -1,
			"notes": "",
		},
		"directions": dirs,
	}


static func make_empty_family(family_id: String, category: String = "soldiers") -> Dictionary:
	return {
		"id": family_id,
		"category": category,
		"faction": "",
		"animations": {},
	}


static func get_camera_rotation_maps() -> Dictionary:
	ensure_loaded()
	var maps: Variant = _root.get("camera_rotation_maps", {})
	return maps if maps is Dictionary else _default_camera_maps()


static func set_camera_rotation_maps(maps: Dictionary) -> void:
	ensure_loaded()
	_root["camera_rotation_maps"] = maps


static func _default_camera_maps() -> Dictionary:
	return {
		"0": {"n": "n", "ne": "ne", "e": "e", "se": "se", "s": "s", "sw": "sw", "w": "w", "nw": "nw"},
		"90": {"n": "e", "ne": "se", "e": "s", "se": "sw", "s": "w", "sw": "nw", "w": "n", "nw": "ne"},
		"180": {"n": "s", "ne": "sw", "e": "w", "se": "nw", "s": "n", "sw": "ne", "w": "e", "nw": "se"},
		"270": {"n": "w", "ne": "nw", "e": "n", "se": "ne", "s": "e", "sw": "se", "w": "s", "nw": "sw"},
	}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func _json_file_byte_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size
