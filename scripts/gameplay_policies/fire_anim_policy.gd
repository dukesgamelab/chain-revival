class_name FireAnimPolicy
extends RefCounted
## Presentation-only rifle firing animation config.
## Does not affect hit chance, cadence, ammo, LOS, or damage.

## 0-based frame index into A–C (or A–B for ASFIA NW). Frame B = 1.
const DEFAULT_VISUAL_SHOT_FRAME := 1
const DEFAULT_FIRE_ANIM_FPS := 8.0

## Per-family visual shot markers (presentation sync only; gameplay shots stay authoritative).
var visual_shot_frame_asfia: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_aprfa: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_glcfa: int = DEFAULT_VISUAL_SHOT_FRAME
var visual_shot_frame_gprfa: int = DEFAULT_VISUAL_SHOT_FRAME
var fire_anim_fps: float = DEFAULT_FIRE_ANIM_FPS

## Dev counters: authoritative shot events vs visual fire triggers.
var authoritative_shot_event_count: int = 0
var visual_firing_trigger_count: int = 0


func reset_to_defaults() -> void:
	visual_shot_frame_asfia = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_aprfa = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_glcfa = DEFAULT_VISUAL_SHOT_FRAME
	visual_shot_frame_gprfa = DEFAULT_VISUAL_SHOT_FRAME
	fire_anim_fps = DEFAULT_FIRE_ANIM_FPS
	authoritative_shot_event_count = 0
	visual_firing_trigger_count = 0


func source_family_for(team_id: int, position_state: int) -> String:
	var prone := position_state == PositionState.DOWN
	if team_id == Team.GERMANY:
		return "GPRFA" if prone else "GLCFA"
	return "APRFA" if prone else "ASFIA"


func semantic_for(position_state: int) -> String:
	return "fire_prone" if position_state == PositionState.DOWN else "fire_standing"


func visual_shot_frame_for_family(source_family: String) -> int:
	match source_family:
		"ASFIA":
			return visual_shot_frame_asfia
		"APRFA":
			return visual_shot_frame_aprfa
		"GLCFA":
			return visual_shot_frame_glcfa
		"GPRFA":
			return visual_shot_frame_gprfa
		_:
			return DEFAULT_VISUAL_SHOT_FRAME


func visual_shot_frame_for(team_id: int, position_state: int) -> int:
	return visual_shot_frame_for_family(source_family_for(team_id, position_state))


func note_authoritative_shot() -> void:
	authoritative_shot_event_count += 1


func note_visual_firing_trigger() -> void:
	visual_firing_trigger_count += 1
