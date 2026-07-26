class_name IdleAnimPolicy
extends RefCounted
## Presentation-only standing idle family selection (open / corner CIS).


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


func reset_to_defaults() -> void:
	pass
