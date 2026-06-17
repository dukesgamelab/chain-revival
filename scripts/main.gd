extends Node2D
## Root scene: map data, two-team session, soldier views, and command bar.

const SoldierScene := preload("res://scenes/soldier.tscn")
const GameSessionClass := preload("res://scripts/game_session.gd")
const GameStateClass := preload("res://scripts/game_state.gd")
const GameSaveClass := preload("res://scripts/game_save.gd")
const MapDataClass := preload("res://scripts/map_data.gd")
const MovementModeClass := preload("res://scripts/movement_mode.gd")
const PositionStateClass := preload("res://scripts/position_state.gd")
const FireControlCommandClass := preload("res://scripts/fire_control_command.gd")
const LosVisualizerClass := preload("res://scripts/los_visualizer.gd")
const FireteamLoadoutClass := preload("res://scripts/fireteam_loadout.gd")
const LOSSystemClass := preload("res://scripts/los_system.gd")

@onready var _world: Node2D = $World
@onready var _map_background: Node2D = $World/MapBackground
@onready var _iso_map: IsometricMap = $World/IsometricMap
@onready var _soldiers_root: Node2D = $World/Soldiers
@onready var _tracers_root: Node2D = $World/Tracers
@onready var _los_visualizer: LosVisualizerClass = $World/LosVisualizer
@onready var _camera: MapCamera = $Camera2D
@onready var _command_bar: CommandBar = $UI/CommandBar

var _map_data = MapDataClass.create_default()
var _session: GameSession = GameSessionClass.new([], [])
var _game_state: GameStateClass

var _soldier_views: Dictionary = {}
var _move_targeting: bool = false
var _squad_move_targeting: bool = false
var _active_movement_mode: int = MovementModeClass.RUN
var _move_soldier_id: int = 1
var _fire_at_mode: bool = false
var _squad_fire_at_mode: bool = false
var _fire_at_soldier_id: int = 1
var _fire_at_engaged: bool = false
var _face_mode: bool = false
var _face_soldier_id: int = 1
var _block_edit_mode: bool = false
var _auto_fire_timer: float = 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.22, 0.38, 0.18, 1.0))
	_camera.make_current()
	_load_map_data()
	_init_session_from_spawns()
	_connect_command_bar()
	_iso_map.apply_map_data(_map_data)
	_center_camera_on_map()
	_spawn_all_soldier_views()
	_log_fireteam_loadouts()
	_command_bar.set_active_team(_session.active_team_id)
	_refresh_all_views()
	_command_bar.show_status("Press 1 = USA, 2 = Germany. Fire At: click an enemy to open fire. Right-click cancels.")


func _log_fireteam_loadouts() -> void:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var message := FireteamLoadoutClass.assignment_message(
				soldier_state.team_id,
				soldier_state.soldier_id,
				soldier_state.weapon_name,
			)
			GameLog.log_system(message)


func _process(delta: float) -> void:
	_update_los_preview()

	_auto_fire_timer += delta
	if _auto_fire_timer < CombatSystem.AUTO_FIRE_SCAN_INTERVAL:
		return
	_auto_fire_timer = 0.0
	if _fire_at_mode and _fire_at_engaged:
		_process_fire_at_mode()
	_process_fire_at_will()


func _process_fire_at_mode() -> void:
	var shooters: Array[SoldierState] = _get_manual_fire_at_shooters()
	if shooters.is_empty():
		_exit_fire_at_mode("Fire At ended — no available shooters.")
		return

	var summary_lines: Array[String] = []
	var any_change := false

	for shooter in shooters:
		var result: CombatShotResult = CombatSystem.try_auto_engagement(_game_state, shooter, true)
		if not result.fired:
			continue
		any_change = true
		var target: SoldierState = _game_state.get_soldier(result.target_team_id, result.target_id)
		summary_lines.append_array(_finalize_shot_result(result, shooter, target))

	if not any_change:
		return

	_ensure_active_selection_alive()
	_refresh_all_views()
	_affirm_fire_at_ui()
	if not summary_lines.is_empty():
		_command_bar.show_status("\n".join(summary_lines.slice(-3)))


func _get_manual_fire_at_shooters() -> Array[SoldierState]:
	var shooters: Array[SoldierState] = []
	var fireteam: Fireteam = _session.get_active_fireteam()
	if _squad_fire_at_mode:
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_alive():
				shooters.append(soldier_state)
	else:
		var shooter: SoldierState = fireteam.get_soldier(_fire_at_soldier_id)
		if shooter != null and shooter.is_alive():
			shooters.append(shooter)
	return shooters


func _is_soldier_in_manual_fire_at(shooter: SoldierState) -> bool:
	if not _fire_at_mode or not _fire_at_engaged or shooter.team_id != _session.active_team_id:
		return false
	if _squad_fire_at_mode:
		return true
	return shooter.soldier_id == _fire_at_soldier_id


func _affirm_fire_at_ui() -> void:
	if not _fire_at_mode:
		return
	if _squad_fire_at_mode:
		_command_bar.affirm_fire_at_pressed(true, CommandBar.SQUAD_ID)
	else:
		_command_bar.affirm_fire_at_pressed(false, _fire_at_soldier_id)


func _exit_fire_at_mode(message: String = "") -> void:
	_fire_at_mode = false
	_squad_fire_at_mode = false
	_fire_at_engaged = false
	_los_visualizer.hide_preview()
	_command_bar.set_fire_at_engaged(false)
	_command_bar.clear_fire_at_mode()
	if not message.is_empty():
		_command_bar.show_status(message)


func _process_fire_at_will() -> void:
	var summary_lines: Array[String] = []
	var any_change := false

	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var shooter: SoldierState = state
			if _is_soldier_in_manual_fire_at(shooter):
				continue
			var result: CombatShotResult = CombatSystem.try_auto_engagement(_game_state, shooter)
			if not result.fired:
				continue
			any_change = true
			var target: SoldierState = _game_state.get_soldier(result.target_team_id, result.target_id)
			summary_lines.append_array(_finalize_shot_result(result, shooter, target))

	if not any_change:
		return

	_ensure_active_selection_alive()
	_refresh_all_views()
	if not summary_lines.is_empty():
		_command_bar.show_status("\n".join(summary_lines.slice(-3)))


func _update_los_preview() -> void:
	if not _fire_at_mode:
		_los_visualizer.hide_preview()
		return

	var shooter: SoldierState = _get_fire_at_preview_shooter()
	if shooter == null or shooter.is_dead:
		_los_visualizer.hide_preview()
		return

	var hover_soldier: SoldierState = _find_living_soldier_at_mouse()
	var target_cell: Vector2i
	var to_world: Vector2

	if hover_soldier != null:
		target_cell = hover_soldier.grid_position
		to_world = _get_soldier_tracer_point(hover_soldier)
	else:
		target_cell = IsometricGrid.world_to_cell_at_point(_get_world_mouse_local())
		to_world = IsometricGrid.grid_to_world(target_cell) + Vector2(0, -16)

	var los := LOSSystemClass.evaluate(shooter.grid_position, target_cell, _map_data)
	if not CombatSystem.is_in_weapon_range(shooter, target_cell):
		los.status = LOSSystemClass.Status.BLOCKED
	var from_world := _get_soldier_tracer_point(shooter)
	_los_visualizer.show_preview(from_world, to_world, los)


func _get_fire_at_preview_shooter() -> SoldierState:
	var fireteam: Fireteam = _session.get_active_fireteam()
	if _squad_fire_at_mode:
		var selected: SoldierState = fireteam.get_selected()
		if selected != null and selected.is_alive():
			return selected
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_alive():
				return soldier_state
		return null
	return fireteam.get_soldier(_fire_at_soldier_id)


func _load_map_data() -> void:
	_map_data = MapDataClass.load_from_file()


func _init_session_from_spawns() -> void:
	var blue_spawns: Array[Vector2i] = _map_data.team_1_spawn_points
	var red_spawns: Array[Vector2i] = _map_data.team_2_spawn_points
	if blue_spawns.is_empty():
		blue_spawns = [Vector2i(28, 30), Vector2i(29, 30), Vector2i(30, 30), Vector2i(31, 30)]
	if red_spawns.is_empty():
		red_spawns = [Vector2i(33, 32), Vector2i(34, 32), Vector2i(35, 32), Vector2i(36, 32)]
	_session = GameSessionClass.new(blue_spawns, red_spawns)
	_game_state = GameStateClass.new(_session, _map_data)


func _connect_command_bar() -> void:
	_command_bar.soldier_selected.connect(_on_soldier_selected)
	_command_bar.move_targeting_changed.connect(_on_move_targeting_changed)
	_command_bar.fire_at_mode_changed.connect(_on_fire_at_mode_changed)
	_command_bar.face_mode_changed.connect(_on_face_mode_changed)
	_command_bar.position_change_requested.connect(_on_position_change_requested)
	_command_bar.fire_control_change_requested.connect(_on_fire_control_change_requested)
	_command_bar.save_requested.connect(_on_save_requested)
	_command_bar.load_requested.connect(_on_load_requested)
	_command_bar.map_save_requested.connect(_on_map_save_requested)
	_command_bar.map_load_requested.connect(_on_map_load_requested)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			_toggle_block_edit_mode()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_1:
			_switch_active_team(Team.USA)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_2:
			_switch_active_team(Team.GERMANY)
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if _fire_at_mode:
			_exit_fire_at_mode("Targeting cancelled.")
			get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var target_cell := IsometricGrid.world_to_cell_at_point(_get_world_mouse_local())

	if _block_edit_mode:
		_toggle_blocked_tile(target_cell)
		get_viewport().set_input_as_handled()
		return

	if _fire_at_mode:
		var target_soldier: SoldierState = _find_living_soldier_at_mouse()
		if target_soldier == null:
			_command_bar.show_status("No enemy soldier there — still targeting.")
			get_viewport().set_input_as_handled()
			return
		if target_soldier.team_id == _session.active_team_id:
			_command_bar.show_status("Cannot shoot friendlies.")
			get_viewport().set_input_as_handled()
			return

		var fire_cmd := FireCommand.new()
		fire_cmd.team_id = _session.active_team_id
		fire_cmd.target_team_id = target_soldier.team_id
		fire_cmd.target_soldier_id = target_soldier.soldier_id
		if _squad_fire_at_mode:
			fire_cmd.scope = FireCommand.Scope.SQUAD
		else:
			fire_cmd.scope = FireCommand.Scope.SINGLE
			fire_cmd.soldier_id = _fire_at_soldier_id
		_apply_fire_command(fire_cmd)
		_begin_fire_at_engagement()
		get_viewport().set_input_as_handled()
		return

	if _face_mode:
		var face_cmd := FaceCommand.new()
		face_cmd.team_id = _session.active_team_id
		face_cmd.soldier_id = _face_soldier_id
		face_cmd.target_cell = target_cell
		_apply_face_command(face_cmd)
		get_viewport().set_input_as_handled()
		return

	if not _move_targeting:
		return

	var move_cmd := MoveCommand.new()
	move_cmd.team_id = _session.active_team_id
	move_cmd.target_cell = target_cell
	move_cmd.movement_mode = _active_movement_mode
	if _squad_move_targeting:
		move_cmd.scope = MoveCommand.Scope.SQUAD
	else:
		move_cmd.scope = MoveCommand.Scope.SINGLE
		move_cmd.soldier_id = _move_soldier_id
	_apply_move_command(move_cmd)
	get_viewport().set_input_as_handled()


func _switch_active_team(team_id: int) -> void:
	if team_id == _session.active_team_id:
		return
	_session.set_active_team(team_id)
	_move_targeting = false
	_squad_move_targeting = false
	_fire_at_mode = false
	_squad_fire_at_mode = false
	_fire_at_engaged = false
	_face_mode = false
	_command_bar.set_active_team(team_id)
	var fireteam: Fireteam = _session.get_active_fireteam()
	_repair_fireteam_selection(fireteam)
	_command_bar.sync_selected_soldier(fireteam.selected_soldier_id)
	_refresh_all_views()
	_command_bar.show_status("Controlling %s team. Press 1/2 to switch." % Team.display_name(team_id))


func _toggle_block_edit_mode() -> void:
	_block_edit_mode = not _block_edit_mode
	if _block_edit_mode:
		_command_bar.clear_move_targeting()
		_command_bar.clear_fire_at_mode()
		_command_bar.clear_face_mode()
		_move_targeting = false
		_squad_move_targeting = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		_fire_at_engaged = false
		_face_mode = false
		_command_bar.show_status("Block Edit ON — click tiles to toggle walls. Press B to exit.")
	else:
		_command_bar.show_status("Block Edit OFF.")


func _toggle_blocked_tile(cell: Vector2i) -> void:
	if not _map_data.is_in_bounds(cell):
		_command_bar.show_status("That tile is outside the map.")
		return

	var is_now_blocked: bool = _map_data.toggle_blocked(cell)
	_iso_map.apply_map_data(_map_data)

	if is_now_blocked:
		_command_bar.show_status("Blocked tile %s." % cell)
	else:
		_command_bar.show_status("Unblocked tile %s." % cell)


func _spawn_all_soldier_views() -> void:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var view: Soldier = SoldierScene.instantiate()
			view.soldier_id = soldier_state.soldier_id
			view.team_id = soldier_state.team_id
			view.movement_step_reached.connect(_on_soldier_step_reached)
			view.movement_finished.connect(_on_soldier_movement_finished)
			_soldiers_root.add_child(view)
			_soldier_views[_view_key(soldier_state.team_id, soldier_state.soldier_id)] = view


func _refresh_all_views() -> void:
	var active_team: int = _session.active_team_id
	var active_fireteam: Fireteam = _session.get_active_fireteam()
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
			if view == null:
				continue
			var is_selected: bool = (
				soldier_state.team_id == active_team
				and soldier_state.soldier_id == active_fireteam.selected_soldier_id
			)
			view.sync_from_state(soldier_state, is_selected)

	_ensure_active_selection_alive()
	_refresh_command_bar()


func _refresh_command_bar() -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	for i in range(fireteam.soldiers.size()):
		var soldier_state: SoldierState = fireteam.soldiers[i]
		_command_bar.sync_soldier_row(i, soldier_state)


func _repair_fireteam_selection(fireteam: Fireteam) -> bool:
	var selected: SoldierState = fireteam.get_selected()
	if selected != null and selected.is_alive():
		return false
	var previous_id := fireteam.selected_soldier_id
	fireteam.select_first_alive()
	return fireteam.selected_soldier_id != previous_id


func _ensure_active_selection_alive() -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	if _repair_fireteam_selection(fireteam):
		_command_bar.sync_selected_soldier(fireteam.selected_soldier_id)


func _view_key(team_id: int, soldier_id: int) -> String:
	return Team.soldier_key(team_id, soldier_id)


func _get_view(team_id: int, soldier_id: int) -> Soldier:
	return _soldier_views.get(_view_key(team_id, soldier_id)) as Soldier


func _get_fireteam(team_id: int) -> Fireteam:
	return _session.get_fireteam(team_id)


func _any_active_team_soldier_moving() -> bool:
	for state in _session.get_active_fireteam().soldiers:
		var soldier_state: SoldierState = state
		var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
		if view != null and view.is_moving():
			return true
	return false


func _on_soldier_selected(soldier_id: int) -> void:
	_session.get_active_fireteam().select_soldier(soldier_id)
	_refresh_all_views()


## Apply a MoveCommand to the active team's soldier(s).
func _apply_move_command(cmd: MoveCommand) -> void:
	if not _map_data.is_walkable(cmd.target_cell):
		if _map_data.is_blocked(cmd.target_cell):
			_command_bar.show_status("That tile is blocked.")
		else:
			_command_bar.show_status("That tile is outside the map.")
		return

	var mode_label := MovementModeClass.display_name(cmd.movement_mode).to_lower()
	var fireteam := _get_fireteam(cmd.team_id)
	if cmd.scope == MoveCommand.Scope.SQUAD:
		var ordered_count := 0
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if not _execute_move_for_soldier(fireteam, soldier_state, cmd.target_cell, cmd.movement_mode).is_empty():
				ordered_count += 1
		if ordered_count == 0:
			_command_bar.show_status("No soldiers could %s to that tile." % mode_label)
			return
		_iso_map.show_path([], cmd.target_cell)
		_command_bar.show_status(
			"%s fireteam %s to %s — click another tile to redirect."
			% [Team.display_name(cmd.team_id), mode_label, cmd.target_cell],
		)
		return

	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	if soldier_state == null:
		return

	var validation := SoldierActions.validate_move(soldier_state, cmd.movement_mode)
	if not validation.is_empty():
		_command_bar.show_status(validation)
		return

	var path: Array[Vector2i] = _execute_move_for_soldier(
		fireteam,
		soldier_state,
		cmd.target_cell,
		cmd.movement_mode,
	)
	if path.is_empty():
		if cmd.target_cell == soldier_state.grid_position:
			return
		_command_bar.show_status("No path to that tile.")
		return

	_iso_map.show_path(path, cmd.target_cell)
	_command_bar.show_status(
		"%s Soldier %d %s to %s — click another tile to redirect."
		% [Team.display_name(cmd.team_id), cmd.soldier_id, mode_label, cmd.target_cell],
	)


func _execute_move_for_soldier(
	fireteam: Fireteam,
	state: SoldierState,
	target_cell: Vector2i,
	movement_mode: int,
) -> Array[Vector2i]:
	if state.is_dead:
		return []

	if not SoldierActions.validate_move(state, movement_mode).is_empty():
		return []

	var view: Soldier = _get_view(state.team_id, state.soldier_id)
	var start_cell: Vector2i = state.grid_position

	if view != null and view.is_moving():
		view.stop_movement()
		start_cell = IsometricGrid.world_to_cell_at_point(view.position)
		state.grid_position = start_cell
		state.clear_path()

	if target_cell == start_cell:
		return []
	if not _map_data.is_walkable(target_cell):
		return []

	var path: Array[Vector2i] = _iso_map.find_path(start_cell, target_cell)
	if path.is_empty():
		return []

	state.movement_mode = movement_mode
	fireteam.order_path(state.soldier_id, path)
	if view != null:
		view.follow_path(path, MovementModeClass.speed_multiplier(movement_mode))
	return path


func _apply_face_command(cmd: FaceCommand) -> void:
	var fireteam: Fireteam = _get_fireteam(cmd.team_id)
	if fireteam.face_toward_tile(cmd.soldier_id, cmd.target_cell):
		_refresh_all_views()
		_command_bar.show_status(
			"%s Soldier %d facing %s."
			% [
				Team.display_name(cmd.team_id),
				cmd.soldier_id,
				FacingDirection.direction_name(fireteam.get_soldier(cmd.soldier_id).facing_direction),
			],
		)
	else:
		_command_bar.show_status("Pick a different tile to face.")


func _apply_position_command(cmd: PositionCommand) -> void:
	var message := SoldierActions.apply_position(_game_state, cmd)
	if message.is_empty():
		return
	_refresh_all_views()
	if (
		cmd.position_state == PositionStateClass.DOWN
		and _move_targeting
		and not MovementModeClass.is_allowed(PositionStateClass.DOWN, _active_movement_mode)
	):
		if _squad_move_targeting or _move_soldier_id == cmd.soldier_id:
			_command_bar.clear_move_targeting()
			_move_targeting = false
			_squad_move_targeting = false
	_command_bar.show_status(message)


func _on_fire_control_change_requested(soldier_id: int, fire_control_state: int) -> void:
	var cmd := FireControlCommandClass.new()
	cmd.team_id = _session.active_team_id
	cmd.soldier_id = soldier_id
	cmd.fire_control_state = fire_control_state
	var message := SoldierActions.apply_fire_control(_game_state, cmd)
	if message.is_empty():
		return
	_refresh_all_views()
	_command_bar.show_status(message)


func _on_position_change_requested(soldier_id: int, position_state: int) -> void:
	var cmd := PositionCommand.new()
	cmd.team_id = _session.active_team_id
	cmd.soldier_id = soldier_id
	cmd.position_state = position_state
	_apply_position_command(cmd)


func _arm_movement_mode(soldier_id: int, movement_mode: int) -> String:
	var fireteam: Fireteam = _session.get_active_fireteam()
	if soldier_id == CommandBar.SQUAD_ID:
		var last_message := ""
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_alive():
				last_message = SoldierActions.arm_movement_mode(soldier_state, movement_mode)
		return last_message

	var soldier: SoldierState = fireteam.get_soldier(soldier_id)
	return SoldierActions.arm_movement_mode(soldier, movement_mode)


## Apply a FireCommand through CombatSystem (UI issues command, system resolves outcome).
func _apply_fire_command(cmd: FireCommand) -> void:
	var target: SoldierState = _game_state.get_soldier(cmd.target_team_id, cmd.target_soldier_id)
	if target == null or target.is_dead:
		_command_bar.show_status("Invalid target.")
		return

	var fireteam: Fireteam = _get_fireteam(cmd.team_id)
	var shooters: Array[SoldierState] = []
	if cmd.scope == FireCommand.Scope.SQUAD:
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_alive():
				shooters.append(soldier_state)
	else:
		var shooter: SoldierState = fireteam.get_soldier(cmd.soldier_id)
		if shooter != null and shooter.is_alive():
			shooters.append(shooter)

	if shooters.is_empty():
		_command_bar.show_status("No available soldiers to fire.")
		return

	var summary_lines: Array[String] = []
	for shooter in shooters:
		var result: CombatShotResult = CombatSystem.resolve_shot(_game_state, shooter, target)
		summary_lines.append_array(_finalize_shot_result(result, shooter, target))

	_ensure_active_selection_alive()
	_refresh_all_views()
	_affirm_fire_at_ui()

	if summary_lines.is_empty():
		_command_bar.show_status("Could not fire.")
	else:
		_command_bar.show_status("\n".join(summary_lines.slice(-3)))


func _finalize_shot_result(
	result: CombatShotResult,
	shooter: SoldierState,
	target: SoldierState,
) -> Array[String]:
	if result.fired and target != null:
		_spawn_shot_tracers(shooter, target, maxi(result.tracer_count, 1))
		result.messages.append("Tracer created")

	var lines: Array[String] = []
	for line in result.messages:
		GameLog.log_combat(line)
		lines.append(line)
	return lines


func _spawn_shot_tracers(shooter: SoldierState, target: SoldierState, count: int) -> void:
	var from_world := _get_soldier_tracer_point(shooter)
	var to_world := _get_soldier_tracer_point(target)
	for i in range(count):
		var jitter := Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		ShotTracer.spawn(_tracers_root, from_world + jitter, to_world + jitter)


func _get_soldier_tracer_point(soldier_state: SoldierState) -> Vector2:
	var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
	if view != null:
		return view.position + Vector2(0, -16)
	return IsometricGrid.grid_to_world(soldier_state.grid_position) + Vector2(0, -16)


func _on_soldier_step_reached(team_id: int, soldier_id: int, tile: Vector2i, step_delta: Vector2i) -> void:
	_get_fireteam(team_id).on_soldier_reached_tile(soldier_id, tile, step_delta)


func _on_soldier_movement_finished(team_id: int, soldier_id: int) -> void:
	_get_fireteam(team_id).on_soldier_finished_moving(soldier_id)
	if team_id == _session.active_team_id and not _any_active_team_soldier_moving():
		_iso_map.clear_path()
	_refresh_all_views()
	_command_bar.show_status("%s Soldier %d move complete." % [Team.display_name(team_id), soldier_id])


func _on_move_targeting_changed(is_active: bool, soldier_id: int, movement_mode: int) -> void:
	_move_targeting = is_active
	_squad_move_targeting = is_active and soldier_id == CommandBar.SQUAD_ID
	_active_movement_mode = movement_mode
	_move_soldier_id = soldier_id if soldier_id > 0 else _session.get_active_fireteam().selected_soldier_id
	if is_active:
		_block_edit_mode = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		_fire_at_engaged = false
		_face_mode = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
		var arm_message := _arm_movement_mode(soldier_id, movement_mode)
		_refresh_all_views()
		if not arm_message.is_empty():
			_command_bar.show_status(arm_message)


func _begin_fire_at_engagement() -> void:
	if _fire_at_engaged:
		return
	_fire_at_engaged = true
	_auto_fire_timer = CombatSystem.AUTO_FIRE_SCAN_INTERVAL
	_command_bar.set_fire_at_engaged(true)
	_affirm_fire_at_ui()


func _on_fire_at_mode_changed(is_active: bool, soldier_id: int) -> void:
	_fire_at_mode = is_active
	_squad_fire_at_mode = is_active and soldier_id == CommandBar.SQUAD_ID
	_fire_at_soldier_id = soldier_id if is_active else 1
	if is_active:
		_fire_at_engaged = false
		_command_bar.set_fire_at_engaged(false)
		_block_edit_mode = false
		_move_targeting = false
		_squad_move_targeting = false
		_face_mode = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
			_refresh_all_views()
	else:
		_fire_at_engaged = false
		_command_bar.set_fire_at_engaged(false)
		_los_visualizer.hide_preview()


func _on_face_mode_changed(is_active: bool, soldier_id: int) -> void:
	_face_mode = is_active
	_face_soldier_id = soldier_id if is_active else 1
	if is_active:
		_block_edit_mode = false
		_move_targeting = false
		_squad_move_targeting = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		_fire_at_engaged = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
			_refresh_all_views()


func _on_save_requested() -> void:
	if GameSaveClass.save_game(_session, _map_data):
		_command_bar.show_status("Game saved.")
	else:
		_command_bar.show_status("Save failed.")


func _on_load_requested() -> void:
	if not GameSaveClass.load_game(_session):
		_command_bar.show_status("Load failed.")
		return

	_sync_views_after_load()
	_command_bar.show_status("Game loaded.")


func _on_map_save_requested() -> void:
	if MapDataClass.save_to_file(_map_data):
		_command_bar.show_status("Map saved to res://maps/test_map.json")
	else:
		_command_bar.show_status("Map save failed.")


func _on_map_load_requested() -> void:
	_map_data = MapDataClass.load_from_file()
	_game_state.map_data = _map_data
	_iso_map.apply_map_data(_map_data)
	_camera.set_map_size(_map_data.width, _map_data.height)
	_center_camera_on_map()
	_sync_views_after_load()
	_command_bar.show_status("Map loaded from res://maps/test_map.json")


func _sync_views_after_load() -> void:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
			if view == null:
				continue
			view.stop_movement()
			var is_selected: bool = (
				soldier_state.team_id == _session.active_team_id
				and soldier_state.soldier_id == _session.get_active_fireteam().selected_soldier_id
			)
			view.sync_from_state(soldier_state, is_selected)

	_iso_map.clear_path()
	_command_bar.clear_move_targeting()
	_command_bar.clear_fire_at_mode()
	_command_bar.clear_face_mode()
	_command_bar.set_active_team(_session.active_team_id)
	_refresh_all_views()
	_command_bar.sync_selected_soldier(_session.get_active_fireteam().selected_soldier_id)


func _get_world_mouse_local() -> Vector2:
	return _world.to_local(get_global_mouse_position())


## Resolve a soldier under the cursor (grid cell + sprite proximity for isometric picking).
func _find_living_soldier_at_mouse() -> SoldierState:
	var world := _get_world_mouse_local()
	var clicked_cell := IsometricGrid.world_to_cell_at_point(world)

	var exact: SoldierState = _game_state.find_living_soldier_at_cell(clicked_cell)
	if exact != null:
		return exact

	const PICK_RADIUS := 44.0
	const PICK_RADIUS_SQ := PICK_RADIUS * PICK_RADIUS
	var best: SoldierState = null
	var best_dist := PICK_RADIUS_SQ

	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.is_dead:
				continue
			var view: Soldier = _get_view(soldier_state.team_id, soldier_state.soldier_id)
			var pick_center := IsometricGrid.grid_to_world(soldier_state.grid_position) + Vector2(0, -16)
			if view != null:
				pick_center = view.position + Vector2(0, -16)
			var dist_sq := world.distance_squared_to(pick_center)
			if dist_sq < best_dist:
				best_dist = dist_sq
				best = soldier_state

	return best


func _center_camera_on_map() -> void:
	if _map_data == null:
		return
	_camera.set_map_size(_map_data.width, _map_data.height)
	var focus_cell: Vector2i = _get_camera_focus_cell()
	_map_background.set_center_cell(focus_cell)
	_camera.reset_to_default_view(IsometricGrid.grid_to_world(focus_cell))


func _get_camera_focus_cell() -> Vector2i:
	var spawns: Array[Vector2i] = _map_data.team_1_spawn_points
	if spawns.is_empty():
		return Vector2i(floori(_map_data.width / 2.0), floori(_map_data.height / 2.0))
	var sum := Vector2i.ZERO
	for cell in spawns:
		sum += cell
	return Vector2i(floori(float(sum.x) / spawns.size()), floori(float(sum.y) / spawns.size()))
