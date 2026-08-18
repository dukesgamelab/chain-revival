class_name IdleAnimPolicy
extends RefCounted
## Presentation-only standing idle family selection (open / corner CIS / crouch)
## and standing fidget timing (OG: mostly static pose, rare oneshot fidgets).

const FireControlStateClass := preload("res://scripts/enums/fire_control_state.gd")

## RECOVERED — original rolls on a fixed ~5.5s tick, not a random delay.
## Measured standing-idle.mp4: all inter-animation gaps are multiples of 5.5s.
const DEFAULT_FIDGET_DELAY_MIN_SEC := 5.5
const DEFAULT_FIDGET_DELAY_MAX_SEC := 5.5
## RECOVERED — one animation per ~10.9 soldier-seconds ≈ 50% per tick.
const DEFAULT_FIDGET_PLAY_CHANCE := 0.5
## RECOVERED — measured durations match clip lengths at ~8 fps (DB clips are 8 fps).
const DEFAULT_FIDGET_FPS := 8.0

## TUNED — crouch when stress reaches suppressed band (matches Stage 3 testing needs).
const DEFAULT_CROUCH_STRESS_THRESHOLD := 25.0
## TUNED — brief ADHPA/GDHPA kneel-aim hold after an open standing shot before returning to fire pose.
const DEFAULT_POST_SHOT_CROUCH_SEC := 0.85

const FIDGET_SEMANTICS: PackedStringArray = [
	"idle_breathing",
	"idle_rest_1",
	"idle_rest_2",
	"idle_rest_3",
]

## TUNED — measured split short : medium : long ≈ 11 : 7 : 2 (ASFB most common).
const DEFAULT_FIDGET_WEIGHTS: Dictionary = {
	"idle_breathing": 0.1,
	"idle_rest_1": 0.2,
	"idle_rest_2": 0.2,
	"idle_rest_3": 0.5,
}

var crouch_stress_threshold: float = DEFAULT_CROUCH_STRESS_THRESHOLD
var post_shot_crouch_sec: float = DEFAULT_POST_SHOT_CROUCH_SEC
var fidget_delay_min_sec: float = DEFAULT_FIDGET_DELAY_MIN_SEC
var fidget_delay_max_sec: float = DEFAULT_FIDGET_DELAY_MAX_SEC
var fidget_play_chance: float = DEFAULT_FIDGET_PLAY_CHANCE
var fidget_fps: float = DEFAULT_FIDGET_FPS
var fidget_weights: Dictionary = DEFAULT_FIDGET_WEIGHTS.duplicate()


func source_family_for(
	team_id: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
	_position_state: int = PositionState.UP,
	want_crouch: bool = false,
) -> String:
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "GLCIS" if team_id == Team.GERMANY else "ALCIS"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "GRCIS" if team_id == Team.GERMANY else "ARCIS"
	if want_crouch:
		return "GDHPA" if team_id == Team.GERMANY else "ADHPA"
	return "GBRLA" if team_id == Team.GERMANY else "ABRLA"


func should_use_crouch(
	position_state: int = PositionState.UP,
	peek_side: int = CoverSystem.PeekSide.NONE,
	stress: float = 0.0,
	fire_control_state: int = FireControlStateClass.FIRE_AT_WILL,
	post_shot_crouch: bool = false,
) -> bool:
	## Prone and corner CIS own their poses — crouch is open standing only.
	if position_state == PositionState.DOWN:
		return false
	if peek_side != CoverSystem.PeekSide.NONE:
		return false
	if post_shot_crouch:
		return true
	if fire_control_state == FireControlStateClass.HOLD_FIRE:
		return true
	return stress >= crouch_stress_threshold


func semantic_for(
	peek_side: int = CoverSystem.PeekSide.NONE,
	position_state: int = PositionState.UP,
	stress: float = 0.0,
	fire_control_state: int = FireControlStateClass.FIRE_AT_WILL,
	post_shot_crouch: bool = false,
) -> String:
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "corner_idle_left"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "corner_idle_right"
	if should_use_crouch(
		position_state, peek_side, stress, fire_control_state, post_shot_crouch
	):
		return "idle_crouch"
	return "idle_standing"


func random_fidget_delay_sec(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(fidget_delay_min_sec, fidget_delay_max_sec)


func should_play_fidget(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < fidget_play_chance


func pick_fidget_semantic(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var cumulative := 0.0
	for semantic in FIDGET_SEMANTICS:
		cumulative += float(fidget_weights.get(semantic, 0.0))
		if roll < cumulative:
			return semantic
	return str(FIDGET_SEMANTICS[FIDGET_SEMANTICS.size() - 1])


func is_fidget_semantic(semantic: String) -> bool:
	return FIDGET_SEMANTICS.has(semantic)


func reset_to_defaults() -> void:
	crouch_stress_threshold = DEFAULT_CROUCH_STRESS_THRESHOLD
	post_shot_crouch_sec = DEFAULT_POST_SHOT_CROUCH_SEC
	fidget_delay_min_sec = DEFAULT_FIDGET_DELAY_MIN_SEC
	fidget_delay_max_sec = DEFAULT_FIDGET_DELAY_MAX_SEC
	fidget_play_chance = DEFAULT_FIDGET_PLAY_CHANCE
	fidget_fps = DEFAULT_FIDGET_FPS
	fidget_weights = DEFAULT_FIDGET_WEIGHTS.duplicate()


func apply_config(section: Dictionary) -> void:
	if section.has("crouch_stress_threshold"):
		crouch_stress_threshold = float(section.crouch_stress_threshold)
	if section.has("post_shot_crouch_sec"):
		post_shot_crouch_sec = float(section.post_shot_crouch_sec)
	if section.has("fidget_delay_min_sec"):
		fidget_delay_min_sec = float(section.fidget_delay_min_sec)
	if section.has("fidget_delay_max_sec"):
		fidget_delay_max_sec = float(section.fidget_delay_max_sec)
	if section.has("fidget_play_chance"):
		fidget_play_chance = float(section.fidget_play_chance)
	if section.has("fidget_fps"):
		fidget_fps = float(section.fidget_fps)
	if section.has("fidget_weights") and section.fidget_weights is Dictionary:
		for key in section.fidget_weights.keys():
			var semantic := str(key)
			if FIDGET_SEMANTICS.has(semantic):
				fidget_weights[semantic] = float(section.fidget_weights[key])
