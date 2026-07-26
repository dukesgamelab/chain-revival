class_name IdleAnimPolicy
extends RefCounted
## Presentation-only standing idle family selection (open / corner CIS)
## and standing fidget timing (OG: mostly static pose, rare oneshot fidgets).

## Independent per-soldier wait before a fidget roll (seconds).
## TEMP debug tuning: fixed 7s / 50%. Restore OG 7–18s / 20% later.
const FIDGET_DELAY_MIN_SEC := 7.0
const FIDGET_DELAY_MAX_SEC := 7.0
## Chance to actually play a fidget when the wait expires.
const FIDGET_PLAY_CHANCE := 0.50
const FIDGET_FPS := 8.0

const FIDGET_SEMANTICS: PackedStringArray = [
	"idle_fidget_1",
	"idle_fidget_2",
	"idle_fidget_3",
	"idle_fidget_4",
]


func source_family_for(
	team_id: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
	_position_state: int = PositionState.UP,
) -> String:
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "GLCIS" if team_id == Team.GERMANY else "ALCIS"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "GRCIS" if team_id == Team.GERMANY else "ARCIS"
	return "GBRLA" if team_id == Team.GERMANY else "ABRLA"


func semantic_for(
	peek_side: int = CoverSystem.PeekSide.NONE,
	_position_state: int = PositionState.UP,
) -> String:
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "corner_idle_left"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "corner_idle_right"
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
	pass
