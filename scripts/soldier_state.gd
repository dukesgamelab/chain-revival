class_name SoldierState
extends RefCounted
## Pure gameplay data for one soldier. No rendering references.
##
## Mutations happen only through ActionResolver (via Fireteam helpers or CombatSystem).

const MovementModeClass := preload("res://scripts/movement_mode.gd")
const PositionStateClass := preload("res://scripts/position_state.gd")
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const WeaponRegistryClass := preload("res://scripts/weapon_registry.gd")
const WeaponDataClass := preload("res://scripts/weapon_data.gd")
const WeaponTypeClass := preload("res://scripts/weapon_type.gd")
const FireteamLoadoutClass := preload("res://scripts/fireteam_loadout.gd")

var soldier_id: int = 1
var team_id: int = Team.USA
var weapon_id: String = ""
var weapon_type: int = WeaponTypeClass.RIFLE
var weapon_name: String = ""
var grid_position: Vector2i = Vector2i.ZERO
var facing_direction: Vector2i = FacingDirection.NORTH
var current_path: Array[Vector2i] = []
var is_moving: bool = false
var ammo_current: int = 0
var ammo_max: int = 0
var is_dead: bool = false
var position_state: int = PositionStateClass.UP
var movement_mode: int = MovementModeClass.RUN
var fire_control_state: int = FireControlStateClass.HOLD_FIRE
var stress: float = 0.0
## Set when suppressed this combat tick; skips stress recovery until next tick.
var received_suppression_this_tick: bool = false
## Timestamp of last fired burst; repeat cadence = last_shot_msec + weapon.fire_interval_sec.
var last_shot_msec: int = 0
## Aiming deadline (weapon.aim_delay_sec); while in the future, activity_status_label() shows "Aiming".
var fire_ready_after_msec: int = 0
var engaged_target_team_id: int = -1
var engaged_target_soldier_id: int = -1
## Manual Fire At order active — keep firing at priority target until cleared.
var sustained_fire: bool = false


func _init(id: int = 1, start_cell: Vector2i = Vector2i.ZERO, team: int = Team.USA) -> void:
	soldier_id = id
	team_id = team
	grid_position = start_cell
	_apply_default_loadout()


func _apply_default_loadout() -> void:
	var loadout_weapon_id := FireteamLoadoutClass.weapon_id_for_soldier(team_id, soldier_id)
	if loadout_weapon_id.is_empty():
		return
	assign_weapon(loadout_weapon_id, true)


## Bind soldier to a weapon definition (stats come from WeaponRegistry, not duplicated here).
func assign_weapon(weapon_id_value: String, refill_ammo: bool = false) -> void:
	var weapon := WeaponRegistryClass.get_weapon(weapon_id_value)
	if weapon == null:
		return
	weapon_id = weapon_id_value
	weapon_type = weapon.weapon_type
	weapon_name = weapon.weapon_name
	ammo_max = weapon.ammo_capacity
	if refill_ammo or ammo_current <= 0 or ammo_current > ammo_max:
		ammo_current = ammo_max


func get_weapon_data() -> WeaponDataClass:
	return WeaponRegistryClass.get_weapon(weapon_id)


func is_alive() -> bool:
	return not is_dead


func activity_status_label() -> String:
	if is_dead:
		return "Dead"
	if is_moving:
		return MovementModeClass.status_name(movement_mode)
	if fire_ready_after_msec > Time.get_ticks_msec():
		return "Aiming"
	if stress >= 10.0:
		return CombatSystem.get_stress_state_label(stress)
	if position_state == PositionStateClass.DOWN:
		return "Prone"
	return "Idle"


func set_engaged_target(target_team_id: int, target_soldier_id: int) -> bool:
	## Returns true when the target changed. Target changes restart aiming; repeat shots use fire_interval_sec.
	var unchanged := (
		engaged_target_team_id == target_team_id
		and engaged_target_soldier_id == target_soldier_id
	)
	engaged_target_team_id = target_team_id
	engaged_target_soldier_id = target_soldier_id
	if unchanged:
		return false
	fire_ready_after_msec = 0
	last_shot_msec = 0
	return true


func clear_engaged_target() -> void:
	engaged_target_team_id = -1
	engaged_target_soldier_id = -1


func is_engaged() -> bool:
	return engaged_target_team_id >= 0 and engaged_target_soldier_id > 0


func is_sustained_fire() -> bool:
	return sustained_fire


func begin_sustained_fire() -> void:
	sustained_fire = true


func end_sustained_fire() -> void:
	sustained_fire = false
	clear_engaged_target()
	reset_fire_prep()


func clear_engagement() -> void:
	clear_engaged_target()
	reset_fire_prep()


func reset_fire_prep() -> void:
	fire_ready_after_msec = 0


func clear_path() -> void:
	current_path.clear()
	is_moving = false


func assign_path(path: Array[Vector2i]) -> void:
	if is_dead:
		return
	current_path = path.duplicate()
	is_moving = current_path.size() > 1
	if is_moving:
		# Movement cancels fire orders; Fire At Will may reacquire after stopping.
		clear_engagement()
		end_sustained_fire()


func to_dict() -> Dictionary:
	return {
		"soldier_id": soldier_id,
		"team_id": team_id,
		"weapon_id": weapon_id,
		"weapon_type": weapon_type,
		"weapon_name": weapon_name,
		"grid_x": grid_position.x,
		"grid_y": grid_position.y,
		"facing_x": facing_direction.x,
		"facing_y": facing_direction.y,
		"ammo_current": ammo_current,
		"ammo_max": ammo_max,
		"is_dead": is_dead,
		"position_state": position_state,
		"movement_mode": movement_mode,
		"fire_control_state": fire_control_state,
		"stress": stress,
	}


static func from_dict(data: Dictionary) -> SoldierState:
	var state := SoldierState.new(
		int(data.get("soldier_id", 1)),
		Vector2i(int(data.get("grid_x", 0)), int(data.get("grid_y", 0))),
		int(data.get("team_id", Team.USA)),
	)
	state.facing_direction = FacingDirection.normalize(
		Vector2i(int(data.get("facing_x", 0)), int(data.get("facing_y", -1))),
	)
	var saved_weapon_id := str(data.get("weapon_id", ""))
	if saved_weapon_id.is_empty():
		state._apply_default_loadout()
	else:
		state.assign_weapon(saved_weapon_id, false)
	state.ammo_current = int(data.get("ammo_current", state.ammo_max))
	state.ammo_max = int(data.get("ammo_max", state.ammo_max))
	state.is_dead = bool(data.get("is_dead", false))
	state.position_state = int(data.get("position_state", PositionStateClass.UP))
	state.movement_mode = int(data.get("movement_mode", MovementModeClass.RUN))
	state.fire_control_state = int(data.get("fire_control_state", FireControlStateClass.HOLD_FIRE))
	state.stress = float(data.get("stress", 0.0))
	return state
