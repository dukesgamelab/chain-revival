class_name IdleAnimPolicy
extends RefCounted
## Presentation-only standing idle family selection (open / corner CIS / crouch)
## and standing fidget timing (OG: mostly static pose, rare oneshot fidgets).

const FireControlStateClass := preload("res://scripts/enums/fire_control_state.gd")

## Independent per-soldier wait before a fidget roll (seconds).
const FIDGET_DELAY_MIN_SEC := 7.0
const FIDGET_DELAY_MAX_SEC := 18.0
## Chance to actually play a fidget when the wait expires.
const FIDGET_PLAY_CHANCE := 0.20
const FIDGET_FPS := 8.0

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

var crouch_stress_threshold: float = DEFAULT_CROUCH_STRESS_THRESHOLD
var post_shot_crouch_sec: float = DEFAULT_POST_SHOT_CROUCH_SEC


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
	return rng.randf_range(FIDGET_DELAY_MIN_SEC, FIDGET_DELAY_MAX_SEC)


func should_play_fidget(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < FIDGET_PLAY_CHANCE


func pick_fidget_semantic(rng: RandomNumberGenerator) -> String:
	var idx := rng.randi_range(0, FIDGET_SEMANTICS.size() - 1)
	return str(FIDGET_SEMANTICS[idx])


func is_fidget_semantic(semantic: String) -> bool:
	return FIDGET_SEMANTICS.has(semantic)


func reset_to_defaults() -> void:
	crouch_stress_threshold = DEFAULT_CROUCH_STRESS_THRESHOLD
	post_shot_crouch_sec = DEFAULT_POST_SHOT_CROUCH_SEC


func apply_config(section: Dictionary) -> void:
	if section.has("crouch_stress_threshold"):
		crouch_stress_threshold = float(section.crouch_stress_threshold)
	if section.has("post_shot_crouch_sec"):
		post_shot_crouch_sec = float(section.post_shot_crouch_sec)
