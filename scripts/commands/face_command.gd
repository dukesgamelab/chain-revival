class_name FaceCommand
extends RefCounted
## Plain data: facing order issued by UI. Validated and applied by ActionResolver.

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_cell: Vector2i = Vector2i.ZERO
var scope: Scope = Scope.SINGLE
## Optional world aim point when target_cell equals the soldier cell (click on self).
var aim_world: Vector2 = Vector2(-99999, -99999)
