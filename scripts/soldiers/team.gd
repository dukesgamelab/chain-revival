class_name Team
extends RefCounted
## Team ids and display colors for local two-team dev mode (USA vs Germany).

const USA := 1
const GERMANY := 2

## Legacy ids kept for save compatibility.
const BLUE := USA
const RED := GERMANY

const COLOR_USA := Color(0.24, 0.55, 0.25, 1.0)
const COLOR_GERMANY := Color(0.43, 0.43, 0.47, 1.0)
const COLOR_USA_SELECTED := Color(0.32, 0.68, 0.34, 1.0)
const COLOR_GERMANY_SELECTED := Color(0.58, 0.58, 0.62, 1.0)

const COLOR_BLUE := COLOR_USA
const COLOR_RED := COLOR_GERMANY
const COLOR_BLUE_SELECTED := COLOR_USA_SELECTED
const COLOR_RED_SELECTED := COLOR_GERMANY_SELECTED


static func display_name(team_id: int) -> String:
	if team_id == GERMANY:
		return "Germany"
	return "USA"


static func soldier_color(team_id: int, is_selected: bool) -> Color:
	if team_id == GERMANY:
		return COLOR_GERMANY_SELECTED if is_selected else COLOR_GERMANY
	return COLOR_USA_SELECTED if is_selected else COLOR_USA


static func soldier_key(team_id: int, soldier_id: int) -> String:
	return "%d_%d" % [team_id, soldier_id]
