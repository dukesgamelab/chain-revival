class_name FireControlCommand
extends RefCounted
## Plain data: Hold Fire / Fire At Will order. Validated and applied by ActionResolver.

const FireControlStateClass := preload("res://scripts/fire_control_state.gd")

var team_id: int = Team.BLUE
var soldier_id: int = 1
var fire_control_state: int = FireControlStateClass.FIRE_AT_WILL
