class_name IdleAnimPolicy
extends RefCounted
## Presentation-only standing idle family selection (open / corner peek).


func source_family_for(
	team_id: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
	position_state: int = PositionState.UP,
) -> String:
	var crouched := position_state == PositionState.DOWN
	if peek_side != CoverSystem.PeekSide.NONE and crouched:
		return "GPKNA" if team_id == Team.GERMANY else "APKNA"
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "GLPKA" if team_id == Team.GERMANY else "ALPKA"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "GRPKA" if team_id == Team.GERMANY else "ARPKA"
	return "GBRLA" if team_id == Team.GERMANY else "ABRLA"


func semantic_for(
	peek_side: int = CoverSystem.PeekSide.NONE,
	position_state: int = PositionState.UP,
) -> String:
	var crouched := position_state == PositionState.DOWN
	if peek_side != CoverSystem.PeekSide.NONE and crouched:
		return "corner_idle_kneel"
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "corner_idle_left"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "corner_idle_right"
	return "idle_standing"


func reset_to_defaults() -> void:
	pass
