class_name FireControlCommand
extends RefCounted
## Set a soldier's Hold Fire / Fire At Will mode (issued by command bar).

const FireControlStateClass := preload("res://scripts/fire_control_state.gd")

var team_id: int = Team.BLUE
var soldier_id: int = 1
var fire_control_state: int = FireControlStateClass.FIRE_AT_WILL
