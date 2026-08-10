class_name UsSoldierSpriteFrames
extends RefCounted
## Proven OG soldier sprite families (US + German mirrors).
##
##   Walk:              ASMOA / GSMOA  (A–G; H exists on disk but is outside the loop)
##   Hit standing (US): AHTFA          (A–S)  → hit_standing_*
##   Hit prone (US):    AHTLA          (A–W)  → hit_prone_*
##   Hit (German):      GHTLA          (A–W)  → hit_*
##   Throw grenade:     ASTGA / GSPRA  (A–X)  → throw_grenade_*
##   Fire standing:     ASFIA / GSFIA  (play A–B–C; ASFIA NW A–B) → fire_standing_*
##   Fire corner L/R:   ALCFA·ARCFA / GLCFA·GRCFA (A–C) → corner_fire_left_* / corner_fire_right_*
##   Fire prone:        APRFA / GPRFA  (play A–B–C) → fire_prone_*
##   Idle standing:     ABRLA / GBRLA frame A (held) → idle_standing_*
##   Idle crouch:       ADHPA / GDHPA A–B loop → idle_crouch_* (kneel aim)
##   Idle fidgets:      ABRLA / GBRLA explicit oneshots → idle_fidget_1..4_*
##   Idle corner L/R:   ALCIS·ARCIS / GLCIS·GRCIS (A) → corner_idle_left_* / corner_idle_right_*
##   Aim corner L/R:    ALCAS·ARCAS / GLCAS·GRCAS (A) → corner_aim_left_* / corner_aim_right_*
##   Peek corner L/R:   ALPKA·ARPKA / GLPKA·GRPKA (A–P, one-shot) → corner_peek_left_* / corner_peek_right_*
##   Peek enter/exit:   ALCPA·ARCPA / GLCPA·GRCPA (enter C-A-B, exit B-A-C) → corner_peek_enter_* / corner_peek_exit_*
##   Idle prone:        APIDS / GPIDS  (A)    → idle_prone_*
##   Stand↔prone:       APRNA / GPRNA  (E-A-B-C-D up; D-C-B-A-E down) → transition_*
##   Crawl:             APMOA / GPMOA  (A–V)  → crawl_*
##   (ASUPA/GSUPA were previously mis-mapped as stand→prone; packs retained, unused here.)
##   Fall/death:        AFALA / GFALA  (A–W) — also stun_knockdown uses A–Q (non-fatal)
##   Stun hold/recover: prone idle (APIDS/GPIDS) hold · transition_prone_to_standing get-up
##                      (not AHTBA — that reads as hit/death)
##   Corpse (US):       ADDSS / ADOAS / ADFUS / ADLYS  (A) → dead_<family>_*
##   Corpse (German):   GDLYS / GDFUS                   (A) → dead_<family>_*
##
## Direction digits (soldier BMP convention — NOT ASAX tile digits):
## 1=W, 2=SW, 3=S, 4=SE, 5=E, 6=NE, 7=N, 8=NW.
## Verified vs ASMOA1/3/5/7 idle frames (upper-left / lower-left / lower-right / upper-right).

const WALK_SPRITES_DIR_USA := "res://assets/sprites/us_soldier/walk"
const HIT_SPRITES_DIR_USA := "res://assets/sprites/us_soldier/hit_reaction"
const FALL_SPRITES_DIR_USA := "res://assets/sprites/us_soldier/fall_or_death"
const DEAD_SPRITES_DIR_USA := "res://assets/sprites/us_soldier/dead_fallen"

const WALK_SPRITES_DIR_GER := "res://assets/sprites/german_soldier/walk"
const HIT_SPRITES_DIR_GER := "res://assets/sprites/german_soldier/hit_reaction"
const FALL_SPRITES_DIR_GER := "res://assets/sprites/german_soldier/fall_or_death"
const DEAD_SPRITES_DIR_GER := "res://assets/sprites/german_soldier/dead_fallen"

const WALK_PREFIX_USA := "ASMOA"
const HIT_PREFIX_USA := "AHTLA"
const FALL_PREFIX_USA := "AFALA"
const DEAD_PREFIX_USA := "ADDSS"

const WALK_PREFIX_GER := "GSMOA"
const HIT_PREFIX_GER := "GHTLA"
const FALL_PREFIX_GER := "GFALA"
const DEAD_PREFIX_GER := "GDFUS"

## Emergency fallbacks only — walk letter range is derived from AnimationDatabase.
## Must match the empirical 7-frame loop (A–G); do not set LAST to H.
const WALK_FRAME_FIRST := "A"
const WALK_FRAME_LAST := "G"
const HIT_FRAME_FIRST := "A"
const HIT_FRAME_LAST := "W"
const FALL_FRAME_FIRST := "A"
const FALL_FRAME_LAST := "W"
const DEAD_FRAME := "A"

const WALK_FPS := 12.0
const HIT_FPS := 14.0
const FALL_FPS := 12.0

const _DIRECTION_SUFFIXES: Array[String] = ["w", "sw", "s", "se", "e", "ne", "n", "nw"]
const _DIRECTION_DIGITS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]

static var _usa_frames: SpriteFrames
static var _germany_frames: SpriteFrames
static var _missing_warned: Dictionary = {}
## When true (default), prefer AnimationDatabase families us_rifle / german_rifle.
## Falls back to hardcoded ASMOA packs if DB entries are missing/empty.
const USE_ANIMATION_DATABASE := true
const DB_FAMILY_USA := "us_rifle"
const DB_FAMILY_GERMANY := "german_rifle"


static func get_usa_sprite_frames() -> SpriteFrames:
	if _usa_frames == null:
		_usa_frames = _load_faction_frames(true)
	return _usa_frames


static func get_germany_sprite_frames() -> SpriteFrames:
	if _germany_frames == null:
		_germany_frames = _load_faction_frames(false)
	return _germany_frames


static func reload_cached_frames() -> void:
	_usa_frames = null
	_germany_frames = null
	AnimationDatabase.reload()


static func _load_faction_frames(is_usa: bool) -> SpriteFrames:
	## Single source of truth: AnimationDatabase. Legacy pack builder is emergency-only
	## and derives walk A–G from the DB so constants cannot silently disagree.
	if USE_ANIMATION_DATABASE:
		var family_id := DB_FAMILY_USA if is_usa else DB_FAMILY_GERMANY
		AnimationDatabase.ensure_loaded()
		var fam := AnimationDatabase.get_family(family_id)
		var walk := AnimationDatabase.get_direction_frames(family_id, "walk", "n")
		if not fam.is_empty() and walk.size() > 0:
			return AnimationDatabase.build_soldier_compatible_sprite_frames(family_id)
	if is_usa:
		return _build_sprite_frames(
			WALK_SPRITES_DIR_USA,
			WALK_PREFIX_USA,
			HIT_SPRITES_DIR_USA,
			HIT_PREFIX_USA,
			FALL_SPRITES_DIR_USA,
			FALL_PREFIX_USA,
			DEAD_SPRITES_DIR_USA,
			DEAD_PREFIX_USA,
			"USA",
			true,
		)
	return _build_sprite_frames(
		WALK_SPRITES_DIR_GER,
		WALK_PREFIX_GER,
		HIT_SPRITES_DIR_GER,
		HIT_PREFIX_GER,
		FALL_SPRITES_DIR_GER,
		FALL_PREFIX_GER,
		DEAD_SPRITES_DIR_GER,
		DEAD_PREFIX_GER,
		"Germany",
		false,
	)


## Walk letter range from DB walk frames (direction e). Falls back to WALK_FRAME_* constants.
static func _walk_letter_range_from_db(is_usa: bool) -> PackedStringArray:
	var family_id := DB_FAMILY_USA if is_usa else DB_FAMILY_GERMANY
	AnimationDatabase.ensure_loaded()
	var frames := AnimationDatabase.get_direction_frames(family_id, "walk", "e")
	if frames.size() >= 1:
		var first_path := str(frames[0])
		var last_path := str(frames[frames.size() - 1])
		var first_base := first_path.get_file().get_basename()
		var last_base := last_path.get_file().get_basename()
		if first_base.length() >= 1 and last_base.length() >= 1:
			return PackedStringArray([
				first_base.substr(first_base.length() - 1, 1),
				last_base.substr(last_base.length() - 1, 1),
			])
	return PackedStringArray([WALK_FRAME_FIRST, WALK_FRAME_LAST])


## Map a grid step or 8-way facing vector to an OG direction suffix (w, sw, …).
## Under CoC X-flip, logical ±X steps reverse on screen — pick the letter from the
## visual step so bodies match aim lines / movement on the flipped map.
static func direction_from_step(step: Vector2i) -> String:
	var snapped := snap_step_to_eight_way(step)
	if MapCoordinateTransform.uses_coc_x_flip():
		## visual_delta = (-logical_dx, logical_dy) for the authoritative X-flip.
		snapped = Vector2i(-snapped.x, snapped.y)
	return _letter_from_visual_step(snapped)


## Threat step points from victim toward attacker / blast. Fall direction is away from threat.
static func direction_from_threat(threat_step: Vector2i) -> String:
	var snapped := snap_step_to_eight_way(threat_step)
	if snapped == Vector2i.ZERO:
		return direction_from_step(FacingDirection.NORTH)
	return direction_from_step(-snapped)


static func snap_step_to_eight_way(step: Vector2i) -> Vector2i:
	## Sign-normalize without the ZERO→NORTH fallback used by FacingDirection.from_step.
	if step == Vector2i.ZERO:
		return Vector2i.ZERO
	return Vector2i(clampi(step.x, -1, 1), clampi(step.y, -1, 1))


static func _letter_from_visual_step(step: Vector2i) -> String:
	match step:
		Vector2i(-1, 0):
			return "w"
		Vector2i(-1, 1):
			return "sw"
		Vector2i(0, 1):
			return "s"
		Vector2i(1, 1):
			return "se"
		Vector2i(1, 0):
			return "e"
		Vector2i(1, -1):
			return "ne"
		Vector2i(0, -1):
			return "n"
		Vector2i(-1, -1):
			return "nw"
		_:
			return "n"


static func _build_sprite_frames(
	walk_dir: String,
	walk_prefix: String,
	hit_dir: String,
	hit_prefix: String,
	fall_dir: String,
	fall_prefix: String,
	dead_dir: String,
	dead_prefix: String,
	faction_label: String,
	is_usa: bool = true,
) -> SpriteFrames:
	var sprite_frames := SpriteFrames.new()
	var missing_total := 0
	var walk_letters := _walk_letter_range_from_db(is_usa)
	var walk_first := str(walk_letters[0])
	var walk_last := str(walk_letters[1])

	for i in _DIRECTION_SUFFIXES.size():
		var suffix: String = _DIRECTION_SUFFIXES[i]
		var digit: int = _DIRECTION_DIGITS[i]

		missing_total += _add_loop_animation(
			sprite_frames,
			"walk_%s" % suffix,
			walk_dir,
			"%s%d" % [walk_prefix, digit],
			walk_first,
			walk_last,
			WALK_FPS,
		)
		missing_total += _add_oneshot_animation(
			sprite_frames,
			"hit_%s" % suffix,
			hit_dir,
			"%s%d" % [hit_prefix, digit],
			HIT_FRAME_FIRST,
			HIT_FRAME_LAST,
			HIT_FPS,
		)
		missing_total += _add_oneshot_animation(
			sprite_frames,
			"fall_%s" % suffix,
			fall_dir,
			"%s%d" % [fall_prefix, digit],
			FALL_FRAME_FIRST,
			FALL_FRAME_LAST,
			FALL_FPS,
		)
		missing_total += _add_static_animation(
			sprite_frames,
			"dead_%s" % suffix,
			dead_dir,
			"%s%d" % [dead_prefix, digit],
			DEAD_FRAME,
		)

	if missing_total > 0:
		_warn_once(
			"missing_%s" % faction_label,
			"UsSoldierSpriteFrames: %s missing %d frame file(s) under %s / %s / %s / %s"
			% [faction_label, missing_total, walk_dir, hit_dir, fall_dir, dead_dir],
		)
	return sprite_frames


static func _add_loop_animation(
	sprite_frames: SpriteFrames,
	anim_name: String,
	dir: String,
	prefix: String,
	first_letter: String,
	last_letter: String,
	fps: float,
) -> int:
	var result := _load_textures(dir, prefix, first_letter, last_letter)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, true)
	for texture in result.textures:
		sprite_frames.add_frame(anim_name, texture, 1.0)
	sprite_frames.set_animation_speed(anim_name, fps)
	return int(result.missing)


static func _add_oneshot_animation(
	sprite_frames: SpriteFrames,
	anim_name: String,
	dir: String,
	prefix: String,
	first_letter: String,
	last_letter: String,
	fps: float,
) -> int:
	var result := _load_textures(dir, prefix, first_letter, last_letter)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, false)
	for texture in result.textures:
		sprite_frames.add_frame(anim_name, texture, 1.0)
	sprite_frames.set_animation_speed(anim_name, fps)
	return int(result.missing)


static func _add_static_animation(
	sprite_frames: SpriteFrames,
	anim_name: String,
	dir: String,
	prefix: String,
	frame_letter: String,
) -> int:
	var result := _load_textures(dir, prefix, frame_letter, frame_letter)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, true)
	if not result.textures.is_empty():
		sprite_frames.add_frame(anim_name, result.textures[0], 1.0)
	sprite_frames.set_animation_speed(anim_name, 1.0)
	return int(result.missing)


static func _load_textures(
	dir: String,
	prefix: String,
	first_letter: String,
	last_letter: String,
) -> Dictionary:
	## Match OgFrameSequence.load_letter_range but count missing without per-frame spam.
	var textures: Array[Texture2D] = []
	var missing := 0
	var first_code := first_letter.to_upper().unicode_at(0)
	var last_code := last_letter.to_upper().unicode_at(0)
	if last_code < first_code:
		return {"textures": textures, "missing": 1}
	for code in range(first_code, last_code + 1):
		var letter := String.chr(code)
		var frame_path := "%s/%s%s.png" % [dir, prefix, letter]
		if not ResourceLoader.exists(frame_path) and not FileAccess.file_exists(frame_path):
			missing += 1
			continue
		var texture: Texture2D = load(frame_path) as Texture2D
		if texture == null:
			missing += 1
			continue
		textures.append(texture)
	return {"textures": textures, "missing": missing}


static func _warn_once(key: String, message: String) -> void:
	if _missing_warned.has(key):
		return
	_missing_warned[key] = true
	push_warning(message)
