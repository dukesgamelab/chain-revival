class_name ActionResult
extends RefCounted
## Outcome returned by ActionResolver. Presentation reads this; it never mutates GameState.

var success: bool = true
var status_message: String = ""

## Per-soldier path orders for the view layer: {team_id, soldier_id, path, speed_mult}
var move_orders: Array[Dictionary] = []

## Soldiers halted mid-move before a combat order: {team_id, soldier_id, snap_cell}
var movement_halts: Array[Dictionary] = []

## Path overlay hint: {cells: Array[Vector2i], target: Vector2i}. Empty = unchanged.
var path_overlay: Dictionary = {}

var clear_path_overlay: bool = false
var clear_move_targeting: bool = false
var sync_fire_at_ui: bool = false
var begin_fire_engagement: bool = false
var refresh_views: bool = true
var refresh_map_data: bool = false

## Combat tick outcomes (shots fired this frame).
var combat_shots: Array = []

## Grenade explosions resolved this frame: CombatGrenadeResult entries.
var grenade_explosions: Array = []


static func fail(message: String) -> ActionResult:
	var result := ActionResult.new()
	result.success = false
	result.status_message = message
	result.refresh_views = false
	return result


func set_status(message: String) -> ActionResult:
	status_message = message
	return self
