class_name IdleAnimPolicy
extends RefCounted
## Presentation-only standing idle family selection (open / corner wall-end).


func source_family_for(
	team_id: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
) -> String:
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "GLCAS" if team_id == Team.GERMANY else "ALCAS"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "GRCAS" if team_id == Team.GERMANY else "ARCAS"
	return "GBRLA" if team_id == Team.GERMANY else "ABRLA"


func semantic_for(peek_side: int = CoverSystem.PeekSide.NONE) -> String:
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "idle_corner_left"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "idle_corner_right"
	return "idle_standing"


func reset_to_defaults() -> void:
	pass
