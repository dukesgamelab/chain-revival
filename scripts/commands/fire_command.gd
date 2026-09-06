class_name FireCommand
extends RefCounted
## Plain data: manual Fire At order (priority target assignment).
##
## aim_world aims the cone; optional target_team_id/target_soldier_id pin a clicked enemy.
## LOS does not gate assignment — CombatSystem decides when shots actually fire.

enum Scope { SINGLE, SQUAD }

var team_id: int = Team.BLUE
var soldier_id: int = 1
## Set when the player clicks directly on an enemy (-1 / 0 = derive from aim_world).
var target_team_id: int = -1
var target_soldier_id: int = -1
var scope: Scope = Scope.SINGLE
var aim_world: Vector2 = Vector2.ZERO
var target_cell: Vector2i = Vector2i(-999, -999)