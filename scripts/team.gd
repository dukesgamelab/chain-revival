class_name Team
extends RefCounted
## Team ids and display colors for local two-team dev mode.

const BLUE := 1
const RED := 2

const COLOR_BLUE := Color(0.35, 0.55, 1.0, 1.0)
const COLOR_RED := Color(1.0, 0.35, 0.30, 1.0)
const COLOR_BLUE_SELECTED := Color(0.55, 0.75, 1.0, 1.0)
const COLOR_RED_SELECTED := Color(1.0, 0.55, 0.45, 1.0)


static func display_name(team_id: int) -> String:
	if team_id == RED:
		return "Red"
	return "Blue"


static func soldier_color(team_id: int, is_selected: bool) -> Color:
	if team_id == RED:
		return COLOR_RED_SELECTED if is_selected else COLOR_RED
	return COLOR_BLUE_SELECTED if is_selected else COLOR_BLUE


static func soldier_key(team_id: int, soldier_id: int) -> String:
	return "%d_%d" % [team_id, soldier_id]
