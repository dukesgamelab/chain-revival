class_name UsSoldierSpriteFrames
extends RefCounted
## OG US soldier sprite families (see coc_sprite_browser/family_labels.json).
##
##   ASMOA  — walk (A–H)
##   AHTLA  — hit reaction (A–W)
##   AFALA  — fall / dying (A–W)
##   ADFUS  — dead fallen corpse (A)
##
## Direction digits: 1=W, 2=SW, 3=S, 4=SE, 5=E, 6=NE, 7=N, 8=NW.

const WALK_SPRITES_DIR := "res://assets/sprites/us_soldier/walk"
const HIT_SPRITES_DIR := "res://assets/sprites/us_soldier/hit_reaction"
const FALL_SPRITES_DIR := "res://assets/sprites/us_soldier/fall_or_death"
const DEAD_SPRITES_DIR := "res://assets/sprites/us_soldier/dead_fallen"

const WALK_PREFIX := "ASMOA"
const HIT_PREFIX := "AHTLA"
const FALL_PREFIX := "AFALA"
const DEAD_PREFIX := "ADFUS"

const WALK_FRAME_FIRST := "A"
const WALK_FRAME_LAST := "H"
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


static func get_usa_sprite_frames() -> SpriteFrames:
	if _usa_frames == null:
		_usa_frames = _build_usa_sprite_frames()
	return _usa_frames


static func get_germany_placeholder_frames(texture: Texture2D) -> SpriteFrames:
	if _germany_frames == null:
		_germany_frames = SpriteFrames.new()
		_germany_frames.add_animation("placeholder")
		_germany_frames.set_animation_loop("placeholder", true)
		_germany_frames.add_frame("placeholder", texture, 1.0)
		_germany_frames.set_animation_speed("placeholder", 1.0)
	return _germany_frames


## Map a grid step or cardinal facing vector to an OG direction suffix (w, sw, …).
static func direction_from_step(step: Vector2i) -> String:
	match snap_step_to_eight_way(step):
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


## Threat step points from victim toward attacker / blast. Fall direction is away from threat.
static func direction_from_threat(threat_step: Vector2i) -> String:
	var snapped := snap_step_to_eight_way(threat_step)
	if snapped == Vector2i.ZERO:
		return "n"
	return direction_from_step(-snapped)


static func snap_step_to_eight_way(step: Vector2i) -> Vector2i:
	if step == Vector2i.ZERO:
		return Vector2i.ZERO
	return Vector2i(clampi(step.x, -1, 1), clampi(step.y, -1, 1))


static func _build_usa_sprite_frames() -> SpriteFrames:
	var sprite_frames := SpriteFrames.new()

	for i in _DIRECTION_SUFFIXES.size():
		var suffix: String = _DIRECTION_SUFFIXES[i]
		var digit: int = _DIRECTION_DIGITS[i]

		_add_loop_animation(
			sprite_frames,
			"walk_%s" % suffix,
			WALK_SPRITES_DIR,
			"%s%d" % [WALK_PREFIX, digit],
			WALK_FRAME_FIRST,
			WALK_FRAME_LAST,
			WALK_FPS,
		)
		_add_oneshot_animation(
			sprite_frames,
			"hit_%s" % suffix,
			HIT_SPRITES_DIR,
			"%s%d" % [HIT_PREFIX, digit],
			HIT_FRAME_FIRST,
			HIT_FRAME_LAST,
			HIT_FPS,
		)
		_add_oneshot_animation(
			sprite_frames,
			"fall_%s" % suffix,
			FALL_SPRITES_DIR,
			"%s%d" % [FALL_PREFIX, digit],
			FALL_FRAME_FIRST,
			FALL_FRAME_LAST,
			FALL_FPS,
		)
		_add_static_animation(
			sprite_frames,
			"dead_%s" % suffix,
			DEAD_SPRITES_DIR,
			"%s%d" % [DEAD_PREFIX, digit],
			DEAD_FRAME,
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
) -> void:
	var textures := OgFrameSequence.load_letter_range(dir, prefix, first_letter, last_letter)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, true)
	for texture in textures:
		sprite_frames.add_frame(anim_name, texture, 1.0)
	sprite_frames.set_animation_speed(anim_name, fps)


static func _add_oneshot_animation(
	sprite_frames: SpriteFrames,
	anim_name: String,
	dir: String,
	prefix: String,
	first_letter: String,
	last_letter: String,
	fps: float,
) -> void:
	var textures := OgFrameSequence.load_letter_range(dir, prefix, first_letter, last_letter)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, false)
	for texture in textures:
		sprite_frames.add_frame(anim_name, texture, 1.0)
	sprite_frames.set_animation_speed(anim_name, fps)


static func _add_static_animation(
	sprite_frames: SpriteFrames,
	anim_name: String,
	dir: String,
	prefix: String,
	frame_letter: String,
) -> void:
	var textures := OgFrameSequence.load_letter_range(dir, prefix, frame_letter, frame_letter)
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, true)
	if not textures.is_empty():
		sprite_frames.add_frame(anim_name, textures[0], 1.0)
	sprite_frames.set_animation_speed(anim_name, 1.0)
