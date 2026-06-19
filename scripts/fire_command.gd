class_name FireCommand
extends RefCounted
## Plain data: Fire At order issued by UI. Validated and applied by ActionResolver.
##
## aim_world points the fire cone; the resolver picks the best visible target inside it.

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_team_id: int = Team.RED
var target_soldier_id: int = 1
var scope: Scope = Scope.SINGLE
var aim_world: Vector2 = Vector2.ZERO
