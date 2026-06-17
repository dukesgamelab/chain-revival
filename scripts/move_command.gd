class_name MoveCommand
extends RefCounted
## Multiplayer-ready move order issued by UI (Run To).

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_cell: Vector2i = Vector2i.ZERO
var scope: Scope = Scope.SINGLE
