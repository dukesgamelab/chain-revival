class_name ActionResult
extends RefCounted
## Outcome returned by ActionResolver. Presentation reads this; it never mutates GameState.

var success: bool = true
var status_message: String = ""

## Per-soldier path orders for the view layer: {team_id, soldier_id, path, speed_mult}
var move_orders: Array[Dictionary] = []

## Authoritative movement steps this sim tick: {team_id, soldier_id, tile, step_delta}
var movement_steps: Array[Dictionary] = []

## Authoritative movement completions this sim tick: {team_id, soldier_id}
var movement_completions: Array[Dictionary] = []

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

## Presentation throw anims: {team_id, soldier_id, world_facing_dir optional}
var throw_orders: Array[Dictionary] = []

## Stance transition anims: {team_id, soldier_id, target_position_state}
## Gameplay position_state is already applied; this is presentation-only.
var stance_transition_orders: Array[Dictionary] = []

## Authoritative facing from the match server: {team_id, soldier_id, facing}
var face_updates: Array[Dictionary] = []

## Authoritative stance / movementMode from the match server.
## {team_id, soldier_id, facing, position_state, movement_mode}
var soldier_updates: Array[Dictionary] = []

## Authoritative fire-control / priority-target state from the match server.
## {team_id, soldier_id, fire_control_state, engaged_target_team_id,
##  engaged_target_soldier_id, sustained_fire}
var target_updates: Array[Dictionary] = []


static func fail(message: String) -> ActionResult:
	var result := ActionResult.new()
	result.success = false
	result.status_message = message
	result.refresh_views = false
	return result


func set_status(message: String) -> ActionResult:
	status_message = message
	return self
