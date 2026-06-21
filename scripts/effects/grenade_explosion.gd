class_name GrenadeExplosion
extends RefCounted
## OG grenade puff animation (EXP2A3A..EXP2A3W). Presentation only.

const OgFrameSequenceClass := preload("res://scripts/effects/og_frame_sequence.gd")
const OgSpriteAnimationClass := preload("res://scripts/effects/og_sprite_animation.gd")

const GRENADE_FRAMES_DIR := "res://assets/sprites/grenades"
const GRENADE_FRAME_PREFIX := "EXP2A3"
const GRENADE_FIRST_LETTER := "A"
const GRENADE_LAST_LETTER := "W"
## Total playback time for the full grenade sequence (tune to match OG feel).
const GRENADE_EXPLOSION_ANIMATION_DURATION := 0.75
## 100×100 OG canvas — scale the visible puff without editing PNGs.
const OG_GRENADE_SPRITE_SCALE := Vector2(1.6, 1.6)

static var _cached_frames: Array[Texture2D] = []
static var _frames_loaded: bool = false


static func spawn(parent: Node2D, world_pos: Vector2) -> OgSpriteAnimationClass:
	var frames := _get_frames()
	if frames.is_empty():
		push_warning(
			"GrenadeExplosion: no grenade frames loaded from %s" % GRENADE_FRAMES_DIR
		)
		return null

	return OgSpriteAnimationClass.play(
		parent,
		world_pos,
		frames,
		GRENADE_EXPLOSION_ANIMATION_DURATION,
		OG_GRENADE_SPRITE_SCALE,
		7,
	)


static func _get_frames() -> Array[Texture2D]:
	if not _frames_loaded:
		_cached_frames = OgFrameSequenceClass.load_letter_range(
			GRENADE_FRAMES_DIR,
			GRENADE_FRAME_PREFIX,
			GRENADE_FIRST_LETTER,
			GRENADE_LAST_LETTER,
		)
		_frames_loaded = true
	return _cached_frames
