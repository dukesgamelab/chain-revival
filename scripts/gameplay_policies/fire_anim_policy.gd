class_name FireAnimPolicy
extends RefCounted
## Presentation-only rifle firing animation config.
## Does not affect hit chance, cadence, ammo, LOS, or damage.

## 0-based frame index into A–C (or A–B for ASFIA NW). Frame B = 1.
const DEFAULT_VISUAL_SHOT_FRAME := 1
const DEFAULT_FIRE_ANIM_FPS := 8.0
## Approximate late lean-out / muzzle-clear frame for ALPK/ARPK 12-frame fire arcs (E–P).
const DEFAULT_CORNER_PEEK_SHOT_FRAME := 8
## Approximate muzzle-clear frame for APKN/GPKN 6-frame fire arcs (C–H).
const DEFAULT_CORNER_KNEEL_SHOT_FRAME := 5

## Per-family visual shot markers (presentation sync only; gameplay shots stay authoritative).
var visual_shot_frame_asfia: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_aprfa: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_gsfia: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_gprfa: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_alpka: int = DEFAULT_CORNER_PEEK_SHOT_FRAME
var visual_shot_frame_arpka: int = DEFAULT_CORNER_PEEK_SHOT_FRAME
var visual_shot_frame_glpka: int = DEFAULT_CORNER_PEEK_SHOT_FRAME
var visual_shot_frame_grpka: int = DEFAULT_CORNER_PEEK_SHOT_FRAME
var visual_shot_frame_apkna: int = DEFAULT_CORNER_KNEEL_SHOT_FRAME
var visual_shot_frame_gpkna: int = DEFAULT_CORNER_KNEEL_SHOT_FRAME
var fire_anim_fps: float = DEFAULT_FIRE_ANIM_FPS

## Dev counters: authoritative shot events vs visual fire triggers.
var authoritative_shot_event_count: int = 0
var visual_firing_trigger_count: int = 0


func reset_to_defaults() -> void:
	visual_shot_frame_asfia = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_aprfa = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_gsfia = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_gprfa = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_alpka = DEFAULT_CORNER_PEEK_SHOT_FRAME
	visual_shot_frame_arpka = DEFAULT_CORNER_PEEK_SHOT_FRAME
	visual_shot_frame_glpka = DEFAULT_CORNER_PEEK_SHOT_FRAME
	visual_shot_frame_grpka = DEFAULT_CORNER_PEEK_SHOT_FRAME
	visual_shot_frame_apkna = DEFAULT_CORNER_KNEEL_SHOT_FRAME
	visual_shot_frame_gpkna = DEFAULT_CORNER_KNEEL_SHOT_FRAME
	fire_anim_fps = DEFAULT_FIRE_ANIM_FPS
	authoritative_shot_event_count = 0
	visual_firing_trigger_count = 0


func source_family_for(
	team_id: int,
	position_state: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
) -> String:
	var prone := position_state == PositionState.DOWN
	if peek_side != CoverSystem.PeekSide.NONE and prone:
		return "GPKNA" if team_id == Team.GERMANY else "APKNA"
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "GLPKA" if team_id == Team.GERMANY else "ALPKA"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "GRPKA" if team_id == Team.GERMANY else "ARPKA"
	if team_id == Team.GERMANY:
		return "GPRFA" if prone else "GSFIA"
	return "APRFA" if prone else "ASFIA"


func semantic_for(
	position_state: int,
	peek_side: int = CoverSystem.PeekSide.NONE,
) -> String:
	var prone := position_state == PositionState.DOWN
	if peek_side != CoverSystem.PeekSide.NONE and prone:
		return "corner_fire_kneel"
	if peek_side == CoverSystem.PeekSide.LEFT:
		return "corner_fire_left"
	if peek_side == CoverSystem.PeekSide.RIGHT:
		return "corner_fire_right"
	return "fire_prone" if prone else "fire_standing"


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
		"ALPKA":
			return visual_shot_frame_alpka
		"ARPKA":
			return visual_shot_frame_arpka
		"GLPKA":
			return visual_shot_frame_glpka
		"GRPKA":
			return visual_shot_frame_grpka
		"APKNA":
			return visual_shot_frame_apkna
		"GPKNA":
			return visual_shot_frame_gpkna
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
