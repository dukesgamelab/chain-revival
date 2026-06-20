class_name GrenadeCommand
extends RefCounted
## Plain data: grenade throw order issued by UI. Validated and applied by ActionResolver.

var team_id: int = Team.BLUE
var soldier_id: int = 1
var target_cell: Vector2i = Vector2i.ZERO
