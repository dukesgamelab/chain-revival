class_name FaceCommand
extends RefCounted
## Multiplayer-ready facing order issued by UI (Face button).

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_cell: Vector2i = Vector2i.ZERO
var scope: Scope = Scope.SINGLE
