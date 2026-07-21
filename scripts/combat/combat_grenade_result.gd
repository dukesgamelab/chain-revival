class_name CombatGrenadeResult
extends RefCounted
## Outcome of a resolved grenade explosion (authoritative; presentation reads this).

const GrenadePolicyClass := preload("res://scripts/gameplay_policies/grenade_policy.gd")

var thrower_team_id: int = -1
var thrower_id: int = -1
var explosion_cell: Vector2i = Vector2i.ZERO
var blast_radius: int = GrenadePolicyClass.DEFAULT_BLAST_RADIUS
var killed: Array[Dictionary] = []
var stunned: Array[Dictionary] = []
var messages: Array[String] = []
