class_name FireAnimPolicy
extends RefCounted
## Presentation-only rifle firing animation config.
## Does not affect hit chance, cadence, ammo, LOS, or damage.

## Standing/prone fire clip order is B → C → C → A (aim, still, muzzle).
## visual_shot_frame points at muzzle A (last index). ASFIA NW is B → B → A (muzzle=2).
const DEFAULT_VISUAL_SHOT_FRAME := 3
const DEFAULT_FIRE_ANIM_FPS := 8.0
## CFA muzzle flash is source letter A (index 0) — verified vs corner-firing video.
const DEFAULT_CORNER_FIRE_SHOT_FRAME := 0

## Per-family visual shot markers (presentation sync only; gameplay shots stay authoritative).
var visual_shot_frame_asfia: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_aprfa: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_gsfia: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_gprfa: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_alcfa: int = DEFAULT_CORNER_FIRE_SHOT_FRAME
var visual_shot_frame_arcfa: int = DEFAULT_CORNER_FIRE_SHOT_FRAME
var visual_shot_frame_glcfa: int = DEFAULT_CORNER_FIRE_SHOT_FRAME
var visual_shot_frame_grcfa: int = DEFAULT_CORNER_FIRE_SHOT_FRAME
var fire_anim_fps: float = DEFAULT_FIRE_ANIM_FPS

## Dev counters: authoritative shot events vs visual fire triggers.
var authoritative_shot_event_count: int = 0
var visual_firing_trigger_count: int = 0


func reset_to_defaults() -> void:
	visual_shot_frame_asfia = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_aprfa = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_gsfia = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_gprfa = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_alcfa = DEFAULT_CORNER_FIRE_SHOT_FRAME
	visual_shot_frame_arcfa = DEFAULT_CORNER_FIRE_SHOT_FRAME
	visual_shot_frame_glcfa = DEFAULT_CORNER_FIRE_SHOT_FRAME
	visual_shot_frame_grcfa = DEFAULT_CORNER_FIRE_SHOT_FRAME
	fire_anim_fps = DEFAULT_FIRE_ANIM_FPS
	authoritative_shot_event_count = 0
	visual_firing_trigger_count = 0


func source_family_for(
	team_id: int,
	position_state: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
) -> String:
	var prone := position_state == PositionState.DOWN
	## Standing corner-peek fire only; prone peeks keep prone fire art.
	if not prone:
		if peek_side == CoverSystem.PeekSide.LEFT:
			return "GLCFA" if team_id == Team.GERMANY else "ALCFA"
		if peek_side == CoverSystem.PeekSide.RIGHT:
			return "GRCFA" if team_id == Team.GERMANY else "ARCFA"
	if team_id == Team.GERMANY:
		return "GPRFA" if prone else "GSFIA"
	return "APRFA" if prone else "ASFIA"


func semantic_for(
	position_state: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
) -> String:
	if position_state != PositionState.DOWN:
		if peek_side == CoverSystem.PeekSide.LEFT:
			return "corner_fire_left"
		if peek_side == CoverSystem.PeekSide.RIGHT:
			return "corner_fire_right"
	return "fire_prone" if position_state == PositionState.DOWN else "fire_standing"


func visual_shot_frame_for_family(source_family: String) -> int:
	match source_family:
		"ASFIA":
			return visual_shot_frame_asfia
		"APRFA":
			return visual_shot_frame_aprfa
		"GSFIA":
			return visual_shot_frame_gsfia
		"GPRFA":
			return visual_shot_frame_gprfa
		"ALCFA":
			return visual_shot_frame_alcfa
		"ARCFA":
			return visual_shot_frame_arcfa
		"GLCFA":
			return visual_shot_frame_glcfa
		"GRCFA":
			return visual_shot_frame_grcfa
		_:
			return DEFAULT_VISUAL_SHOT_FRAME


func visual_shot_frame_for(
	team_id: int,
	position_state: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
) -> int:
	return visual_shot_frame_for_family(source_family_for(team_id, position_state, peek_side))


func note_authoritative_shot() -> void:
	authoritative_shot_event_count += 1


func note_visual_firing_trigger() -> void:
	visual_firing_trigger_count += 1
