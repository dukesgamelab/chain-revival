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
const FireControlStateClass := preload("res://scripts/fire_control_state.gd")
const LosVisualizerClass := preload("res://scripts/los_visualizer.gd")
const FireteamLoadoutClass := preload("res://scripts/fireteam_loadout.gd")
const LOSSystemClass := preload("res://scripts/los_system.gd")
const ConeOfFireClass := preload("res://scripts/cone_of_fire.gd")

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
	_update_command_bar_hit_columns()

	_auto_fire_timer += delta
	if _auto_fire_timer < CombatSystem.AUTO_FIRE_SCAN_INTERVAL:
		return
	_auto_fire_timer = 0.0
	_process_engaged_fire()
	_process_fire_at_will()


func _process_engaged_fire() -> void:
	var summary_lines: Array[String] = []
	var any_change := false

	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var shooter: SoldierState = state
			if not shooter.is_sustained_fire() and not shooter.is_engaged():
				continue
			var result: CombatShotResult = CombatSystem.try_engaged_fire(_game_state, shooter)
			if not result.fired:
				continue
			any_change = true
			var target: SoldierState = _game_state.get_soldier(result.target_team_id, result.target_id)
			summary_lines.append_array(_finalize_shot_result(result, shooter, target))

	if not any_change:
		return

	_ensure_active_selection_alive()
	_refresh_all_views()
	_sync_fire_at_ui_from_engagements()
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


func _clear_manual_fire_at_targets() -> void:
	for fireteam in _session.all_fireteams():
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			soldier_state.end_sustained_fire()


func _active_fireteam_has_engaged_soldier() -> bool:
	var fireteam: Fireteam = _session.get_active_fireteam()
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		if not _is_soldier_in_fire_at_scope(soldier_state):
			continue
		if soldier_state.is_sustained_fire():
			return true
	return false


func _sync_fire_at_ui_from_engagements() -> void:
	var has_engaged := _active_fireteam_has_engaged_soldier()
	_fire_at_engaged = has_engaged
	_command_bar.set_fire_at_engaged(has_engaged)
	if has_engaged and _fire_at_mode:
		_affirm_fire_at_ui()
	elif not has_engaged and _fire_at_mode:
		_command_bar.set_fire_at_engaged(false)


func _affirm_fire_at_ui() -> void:
	if not _fire_at_mode:
		return
	if _squad_fire_at_mode:
		_command_bar.affirm_fire_at_pressed(true, CommandBar.SQUAD_ID)
	else:
		_command_bar.affirm_fire_at_pressed(false, _fire_at_soldier_id)


func _exit_fire_at_mode(message: String = "") -> void:
	_clear_manual_fire_at_targets()
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
			if shooter.is_engaged() or shooter.is_sustained_fire():
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

	var weapon := shooter.get_weapon_data()
	var max_range := ConeOfFireClass.effective_range(weapon.range_tiles) if weapon != null else ConeOfFireClass.RANGE_BONUS
	var from_world := _get_soldier_tracer_point(shooter)
	var cone_world := ConeOfFireClass.cone_outline_world_toward(
		from_world,
		to_world,
		shooter.grid_position,
		max_range,
	)

	var los := LOSSystemClass.evaluate(shooter.grid_position, target_cell, _map_data)
	var aim_facing := FacingDirection.toward_cell(shooter.grid_position, target_cell)
	if not ConeOfFireClass.is_cell_in_cone(
		shooter.grid_position,
		aim_facing,
		target_cell,
		max_range,
	):
		los.status = LOSSystemClass.Status.BLOCKED
	var has_enemy := CombatSystem.aim_cone_has_visible_enemy(
		_game_state,
		shooter,
		from_world,
		to_world,
		max_range,
	)
	_los_visualizer.show_cone_preview(from_world, cone_world, to_world, los, has_enemy)


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
		blue_spawns = MapDataClass.default_usa_spawn_points()
	if red_spawns.is_empty():
		red_spawns = MapDataClass.default_germany_spawn_points()
	_session = GameSessionClass.new(blue_spawns, red_spawns)
	_apply_initial_fireteam_setup()
	_game_state = GameStateClass.new(_session, _map_data)


func _apply_initial_fireteam_setup() -> void:
	var usa_team: Fireteam = _session.blue_team
	var germany_team: Fireteam = _session.red_team
	for i in range(mini(usa_team.soldiers.size(), germany_team.soldiers.size())):
		var usa_soldier: SoldierState = usa_team.soldiers[i]
		var germany_soldier: SoldierState = germany_team.soldiers[i]
		usa_soldier.facing_direction = FacingDirection.toward_cell(
			usa_soldier.grid_position,
			germany_soldier.grid_position,
		)
		germany_soldier.facing_direction = FacingDirection.toward_cell(
			germany_soldier.grid_position,
			usa_soldier.grid_position,
		)
		usa_soldier.fire_control_state = FireControlStateClass.HOLD_FIRE
		germany_soldier.fire_control_state = FireControlStateClass.HOLD_FIRE


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
	_command_bar.center_camera_requested.connect(_on_center_camera_requested)


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
		if _face_mode:
			_face_mode = false
			_command_bar.clear_face_mode()
			_command_bar.show_status("Facing cancelled.")
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
		var clicked_soldier: SoldierState = _find_living_soldier_at_mouse()
		if clicked_soldier != null and clicked_soldier.team_id == _session.active_team_id:
			_command_bar.show_status("Cannot shoot friendlies.")
			get_viewport().set_input_as_handled()
			return

		var aim_world: Vector2
		if clicked_soldier != null:
			aim_world = _get_soldier_tracer_point(clicked_soldier)
		else:
			aim_world = IsometricGrid.grid_to_world(target_cell) + Vector2(0, -16)
		_apply_fire_at_aim(aim_world)
		get_viewport().set_input_as_handled()
		return

	if _face_mode:
		var face_target_cell := target_cell
		var face_target_soldier: SoldierState = _find_living_soldier_at_mouse()
		if face_target_soldier != null:
			face_target_cell = face_target_soldier.grid_position
		var face_cmd := FaceCommand.new()
		face_cmd.team_id = _session.active_team_id
		face_cmd.soldier_id = _face_soldier_id
		face_cmd.target_cell = face_target_cell
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
			var is_selected: bool = (
				soldier_state.team_id == active_team
				and soldier_state.soldier_id == active_fireteam.selected_soldier_id
			)
			_sync_soldier_view(soldier_state.team_id, soldier_state.soldier_id, is_selected)

	_ensure_active_selection_alive()
	_refresh_command_bar()


func _refresh_selection_marks() -> void:
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
			view.set_selected(is_selected)


func _sync_soldier_view(team_id: int, soldier_id: int, is_selected: bool = false) -> void:
	var soldier_state: SoldierState = _get_fireteam(team_id).get_soldier(soldier_id)
	if soldier_state == null:
		return
	var view: Soldier = _get_view(team_id, soldier_id)
	if view == null:
		return
	view.sync_from_state(soldier_state, is_selected)


func _refresh_armed_movement_views(soldier_id: int) -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	var active_team: int = _session.active_team_id
	if soldier_id == CommandBar.SQUAD_ID:
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if not soldier_state.is_alive():
				continue
			var is_selected := soldier_state.soldier_id == fireteam.selected_soldier_id
			_sync_soldier_view(active_team, soldier_state.soldier_id, is_selected)
		_refresh_command_bar()
	elif soldier_id > 0:
		var is_selected := soldier_id == fireteam.selected_soldier_id
		_sync_soldier_view(active_team, soldier_id, is_selected)
		_refresh_command_bar()


func _refresh_command_bar() -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	for i in range(fireteam.soldiers.size()):
		var soldier_state: SoldierState = fireteam.soldiers[i]
		var hit_pct := _hit_pct_for_command_row(soldier_state)
		_command_bar.sync_soldier_row(i, soldier_state, hit_pct)


func _update_command_bar_hit_columns() -> void:
	if not _should_update_hit_columns():
		return
	var fireteam: Fireteam = _session.get_active_fireteam()
	var hit_pcts: Array = []
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		hit_pcts.append(_hit_pct_for_command_row(soldier_state))
	_command_bar.update_hit_columns(hit_pcts)


func _should_update_hit_columns() -> bool:
	if _fire_at_mode:
		return true
	for state in _session.get_active_fireteam().soldiers:
		var soldier_state: SoldierState = state
		if soldier_state.is_alive() and soldier_state.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
			return true
	return false


func _hit_pct_for_command_row(soldier_state: SoldierState) -> float:
	if not _should_show_hit_pct(soldier_state):
		return -1.0
	return CombatSystem.hit_pct_vs_faced_enemy(_game_state, soldier_state)


func _should_show_hit_pct(soldier_state: SoldierState) -> bool:
	if soldier_state.is_dead:
		return false
	if soldier_state.fire_control_state == FireControlStateClass.FIRE_AT_WILL:
		return true
	return _is_soldier_in_fire_at_scope(soldier_state)


func _is_soldier_in_fire_at_scope(soldier_state: SoldierState) -> bool:
	if not _fire_at_mode or soldier_state.team_id != _session.active_team_id:
		return false
	if _squad_fire_at_mode:
		return true
	return soldier_state.soldier_id == _fire_at_soldier_id


func _on_center_camera_requested() -> void:
	_center_camera_on_active_fireteam()


func _center_camera_on_active_fireteam() -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	var sum := Vector2i.ZERO
	var count := 0
	for state in fireteam.soldiers:
		var soldier_state: SoldierState = state
		if not soldier_state.is_alive():
			continue
		sum += soldier_state.grid_position
		count += 1
	if count == 0:
		_command_bar.show_status("No living soldiers to center on.")
		return
	var center_cell := Vector2i(floori(float(sum.x) / count), floori(float(sum.y) / count))
	_map_background.set_center_cell(center_cell)
	_camera.reset_to_default_view(IsometricGrid.grid_to_world(center_cell))
	_command_bar.show_status("Camera centered on %s fireteam." % Team.display_name(_session.active_team_id))


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

	_log_move_order(cmd.target_cell, path, soldier_state)
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
	if not fireteam.face_toward_tile(cmd.soldier_id, cmd.target_cell):
		_command_bar.show_status("Pick a different tile to face.")
		return

	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	if soldier_state != null and soldier_state.is_sustained_fire():
		var cone_target := CombatSystem.find_best_cone_target(_game_state, soldier_state)
		if cone_target == null or not CombatSystem.is_facing_target(soldier_state, cone_target):
			soldier_state.end_sustained_fire()
			_sync_fire_at_ui_from_engagements()
			_command_bar.show_status(
				"%s Soldier %d ceased fire — facing %s."
				% [
					Team.display_name(cmd.team_id),
					cmd.soldier_id,
					FacingDirection.direction_name(soldier_state.facing_direction),
				],
			)
			_refresh_all_views()
			return
	elif soldier_state != null and soldier_state.is_engaged():
		var engaged_target: SoldierState = _game_state.get_soldier(
			soldier_state.engaged_target_team_id,
			soldier_state.engaged_target_soldier_id,
		)
		if engaged_target != null and not CombatSystem.is_facing_target(soldier_state, engaged_target):
			soldier_state.clear_engagement()
			_sync_fire_at_ui_from_engagements()
			_command_bar.show_status(
				"%s Soldier %d ceased fire — facing %s."
				% [
					Team.display_name(cmd.team_id),
					cmd.soldier_id,
					FacingDirection.direction_name(soldier_state.facing_direction),
				],
			)
			_refresh_all_views()
			return

	_refresh_all_views()
	_command_bar.show_status(
		"%s Soldier %d facing %s."
		% [
			Team.display_name(cmd.team_id),
			cmd.soldier_id,
			FacingDirection.direction_name(soldier_state.facing_direction),
		],
	)


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
	if fire_control_state == FireControlStateClass.HOLD_FIRE:
		var soldier_state: SoldierState = _session.get_active_fireteam().get_soldier(soldier_id)
		if soldier_state != null and soldier_state.is_sustained_fire():
			soldier_state.end_sustained_fire()
			_sync_fire_at_ui_from_engagements()
			message = "Soldier %d set to Hold Fire — ceased fire." % soldier_id
		elif soldier_state != null and soldier_state.is_engaged():
			soldier_state.clear_engagement()
			_sync_fire_at_ui_from_engagements()
			message = "Soldier %d set to Hold Fire — ceased fire." % soldier_id
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


## Begin sustained fire at the closest visible enemy in the mouse-aimed cone.
func _apply_fire_at_aim(aim_world: Vector2) -> void:
	var fireteam: Fireteam = _session.get_active_fireteam()
	var shooters: Array[SoldierState] = _get_manual_fire_at_shooters()
	if shooters.is_empty():
		_command_bar.show_status("No available soldiers to fire.")
		return

	var halted_any := false
	var engaged_count := 0
	var first_target: SoldierState = null

	for shooter in shooters:
		var weapon := shooter.get_weapon_data()
		var max_range := (
			ConeOfFireClass.effective_range(weapon.range_tiles)
			if weapon != null
			else ConeOfFireClass.RANGE_BONUS
		)
		var from_world := _get_soldier_tracer_point(shooter)
		var target: SoldierState = CombatSystem.find_best_aim_cone_target(
			_game_state,
			shooter,
			from_world,
			aim_world,
			max_range,
		)
		if target == null:
			if shooter.is_sustained_fire():
				shooter.end_sustained_fire()
			continue

		if _halt_soldier_for_combat(shooter):
			halted_any = true
		shooter.begin_sustained_fire()
		shooter.set_engaged_target(target.team_id, target.soldier_id)
		CombatSystem.begin_fire_prep(shooter)
		fireteam.face_toward_tile(shooter.soldier_id, target.grid_position)
		engaged_count += 1
		if first_target == null:
			first_target = target

	if engaged_count == 0:
		_refresh_all_views()
		_sync_fire_at_ui_from_engagements()
		_command_bar.show_status("No enemies in aim cone — ceased fire.")
		return

	if halted_any:
		_iso_map.clear_path()
		_command_bar.clear_move_targeting()
		_move_targeting = false
		_squad_move_targeting = false

	for shooter in shooters:
		var is_selected := (
			shooter.team_id == _session.active_team_id
			and shooter.soldier_id == _session.get_active_fireteam().selected_soldier_id
		)
		_sync_soldier_view(shooter.team_id, shooter.soldier_id, is_selected)

	_refresh_command_bar()
	_begin_fire_at_engagement()
	_sync_fire_at_ui_from_engagements()
	if engaged_count == 1 and first_target != null:
		_command_bar.show_status(
			"Taking aim at %s Soldier %d — firing in %.0fs."
			% [
				Team.display_name(first_target.team_id),
				first_target.soldier_id,
				CombatSystem.FIRE_PREP_DELAY_SEC,
			],
		)
	else:
		_command_bar.show_status(
			"%d soldiers engaging enemies in cone — firing in %.0fs."
			% [engaged_count, CombatSystem.FIRE_PREP_DELAY_SEC],
		)


func _halt_soldier_for_combat(state: SoldierState) -> bool:
	var view: Soldier = _get_view(state.team_id, state.soldier_id)
	var was_moving := state.is_moving or (view != null and view.is_moving())
	if view != null and view.is_moving():
		view.stop_movement()
		state.grid_position = IsometricGrid.world_to_cell_at_point(view.position)
	state.clear_path()
	return was_moving


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
	var state: SoldierState = _get_fireteam(team_id).get_soldier(soldier_id)
	var view: Soldier = _get_view(team_id, soldier_id)
	_log_move_complete(soldier_id, state, view)
	if team_id == _session.active_team_id and not _any_active_team_soldier_moving():
		_iso_map.clear_path()
	var is_selected := (
		team_id == _session.active_team_id
		and soldier_id == _session.get_active_fireteam().selected_soldier_id
	)
	_sync_soldier_view(team_id, soldier_id, is_selected)
	_ensure_active_selection_alive()
	_refresh_command_bar()
	_command_bar.show_status("%s Soldier %d move complete." % [Team.display_name(team_id), soldier_id])


func _log_move_order(clicked_tile: Vector2i, path: Array[Vector2i], state: SoldierState) -> void:
	var path_final := path[path.size() - 1] if not path.is_empty() else Vector2i(-1, -1)
	call_deferred(
		"_emit_move_order_log",
		clicked_tile,
		path_final,
		state.grid_position,
		_soldier_world_pos(state),
	)


func _emit_move_order_log(
	clicked_tile: Vector2i,
	path_final: Vector2i,
	soldier_grid: Vector2i,
	soldier_world: Vector2,
) -> void:
	GameLog.log_system(
		"Move order: clicked=%s path_final=%s soldier_grid=%s soldier_world=%s"
		% [clicked_tile, path_final, soldier_grid, soldier_world],
	)


func _log_move_complete(soldier_id: int, state: SoldierState, view: Soldier) -> void:
	if state == null:
		return
	var world_pos := view.position if view != null else _soldier_world_pos(state)
	call_deferred(
		"_emit_move_complete_log",
		soldier_id,
		state.grid_position,
		world_pos,
	)


func _emit_move_complete_log(soldier_id: int, grid_pos: Vector2i, world_pos: Vector2) -> void:
	GameLog.log_system(
		"Move complete: soldier=%d grid=%s world=%s cell_at_world=%s"
		% [
			soldier_id,
			grid_pos,
			world_pos,
			IsometricGrid.world_to_cell_at_point(world_pos),
		],
	)


func _soldier_world_pos(state: SoldierState) -> Vector2:
	var view: Soldier = _get_view(state.team_id, state.soldier_id)
	if view != null:
		return view.position
	return IsometricGrid.grid_to_world(state.grid_position)


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
		_refresh_selection_marks()
		_refresh_armed_movement_views(soldier_id)
		if not arm_message.is_empty():
			_command_bar.show_status(arm_message)


func _begin_fire_at_engagement() -> void:
	_auto_fire_timer = CombatSystem.AUTO_FIRE_SCAN_INTERVAL
	_sync_fire_at_ui_from_engagements()


func _on_fire_at_mode_changed(is_active: bool, soldier_id: int) -> void:
	_fire_at_mode = is_active
	_squad_fire_at_mode = is_active and soldier_id == CommandBar.SQUAD_ID
	_fire_at_soldier_id = soldier_id if is_active else 1
	if is_active:
		_block_edit_mode = false
		_move_targeting = false
		_squad_move_targeting = false
		_face_mode = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
			_refresh_all_views()
	else:
		_los_visualizer.hide_preview()
		_sync_fire_at_ui_from_engagements()


func _on_face_mode_changed(is_active: bool, soldier_id: int) -> void:
	_face_mode = is_active
	_face_soldier_id = soldier_id if is_active else 1
	if is_active:
		_block_edit_mode = false
		_move_targeting = false
		_squad_move_targeting = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
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
