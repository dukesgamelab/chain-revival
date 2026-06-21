class_name UsSoldierSpriteFrames
extends RefCounted
## OG upright US soldier walk sprites (ASMOA1–8, A–H).
##
## Direction digits: 1=W, 2=SW, 3=S, 4=SE, 5=E, 6=NE, 7=N, 8=NW.
## When not moving, soldiers hold walk frame A (paused).

const WALK_SPRITES_DIR := "res://assets/sprites/us_soldier/walk"
const WALK_FRAME_PREFIX := "ASMOA"
const WALK_FRAME_FIRST := "A"
const WALK_FRAME_LAST := "H"

## Tune walk cycle playback speed (frames per second).
const WALK_FPS := 12.0

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


static func _build_usa_sprite_frames() -> SpriteFrames:
	var sprite_frames := SpriteFrames.new()

	for i in _DIRECTION_SUFFIXES.size():
		var suffix: String = _DIRECTION_SUFFIXES[i]
		var digit: int = _DIRECTION_DIGITS[i]
		var walk_prefix := "%s%d" % [WALK_FRAME_PREFIX, digit]
		var walk_frames := OgFrameSequence.load_letter_range(
			WALK_SPRITES_DIR, walk_prefix, WALK_FRAME_FIRST, WALK_FRAME_LAST
		)

		var walk_name := "walk_%s" % suffix
		sprite_frames.add_animation(walk_name)
		sprite_frames.set_animation_loop(walk_name, true)
		for texture in walk_frames:
			sprite_frames.add_frame(walk_name, texture, 1.0)
		sprite_frames.set_animation_speed(walk_name, WALK_FPS)

	return sprite_frames
