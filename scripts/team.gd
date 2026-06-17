class_name Team
extends RefCounted
## Team ids and display colors for local two-team dev mode (USA vs Germany).

const USA := 1
const GERMANY := 2

## Legacy ids kept for save compatibility.
const BLUE := USA
const RED := GERMANY

const COLOR_USA := Color(0.35, 0.72, 0.38, 1.0)
const COLOR_GERMANY := Color(0.58, 0.58, 0.62, 1.0)
const COLOR_USA_SELECTED := Color(0.50, 0.88, 0.52, 1.0)
const COLOR_GERMANY_SELECTED := Color(0.72, 0.72, 0.76, 1.0)

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
