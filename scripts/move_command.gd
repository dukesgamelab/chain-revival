class_name MoveCommand
extends RefCounted
## Plain data: move order issued by UI. Validated and applied by ActionResolver.

const MovementModeClass := preload("res://scripts/movement_mode.gd")

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_cell: Vector2i = Vector2i.ZERO
var scope: Scope = Scope.SINGLE
var movement_mode: int = MovementModeClass.RUN
