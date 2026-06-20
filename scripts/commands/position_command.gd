class_name PositionCommand
extends RefCounted
## Plain data: UP/DOWN posture order. Validated and applied by ActionResolver.

const PositionStateClass := preload("res://scripts/enums/position_state.gd")

var team_id: int = Team.BLUE
var soldier_id: int = 1
var position_state: int = PositionStateClass.UP
