class_name CombatGrenadeResult
extends RefCounted
## Outcome of a resolved grenade explosion (authoritative; presentation reads this).

var thrower_team_id: int = -1
var thrower_id: int = -1
var explosion_cell: Vector2i = Vector2i.ZERO
var blast_radius: int = 3
var killed: Array[Dictionary] = []
var stunned: Array[Dictionary] = []
var messages: Array[String] = []
