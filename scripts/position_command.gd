class_name PositionCommand
extends RefCounted
## Set a soldier's UP/DOWN posture (issued by command bar).

const PositionStateClass := preload("res://scripts/position_state.gd")

var team_id: int = Team.BLUE
var soldier_id: int = 1
var position_state: int = PositionStateClass.UP
