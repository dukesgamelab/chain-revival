class_name FaceCommand
extends RefCounted
## Plain data: facing order issued by UI. Validated and applied by ActionResolver.

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_cell: Vector2i = Vector2i.ZERO
var scope: Scope = Scope.SINGLE
