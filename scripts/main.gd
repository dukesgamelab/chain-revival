extends Node2D
## Root scene: map data, two-team session, soldier views, and command bar.

const SoldierScene := preload("res://scenes/soldier.tscn")
const GameSessionClass := preload("res://scripts/game_session.gd")
const GameSaveClass := preload("res://scripts/game_save.gd")
const MapDataClass := preload("res://scripts/map_data.gd")

@onready var _world: Node2D = $World
@onready var _map_background: Node2D = $World/MapBackground
@onready var _iso_map: IsometricMap = $World/IsometricMap
@onready var _soldiers_root: Node2D = $World/Soldiers
@onready var _camera: MapCamera = $Camera2D
@onready var _command_bar: CommandBar = $UI/CommandBar

var _map_data = MapDataClass.create_default()
var _session: GameSession = GameSessionClass.new([], [])

var _soldier_views: Dictionary = {}
var _run_to_mode: bool = false
var _squad_run_to_mode: bool = false
var _fire_at_mode: bool = false
var _squad_fire_at_mode: bool = false
var _block_edit_mode: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.22, 0.38, 0.18, 1.0))
	_camera.make_current()
	_load_map_data()
	_init_session_from_spawns()
	_connect_command_bar()
	_iso_map.apply_map_data(_map_data)
	_center_camera_on_map()
	_spawn_all_soldier_views()
	_refresh_all_views()
	_command_bar.set_active_team(_session.active_team_id)
	_command_bar.set_selected_soldier(_session.get_active_fireteam().selected_soldier_id)
	_command_bar.show_status("Press 1 = Blue, 2 = Red. WASD pans. B = Block Edit.")


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


func _connect_command_bar() -> void:
	_command_bar.soldier_selected.connect(_on_soldier_selected)
	_command_bar.run_to_mode_changed.connect(_on_run_to_mode_changed)
	_command_bar.fire_at_mode_changed.connect(_on_fire_at_mode_changed)
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
			_switch_active_team(Team.BLUE)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_2:
			_switch_active_team(Team.RED)
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var target_cell := IsometricGrid.world_to_cell_at_point(_get_world_mouse_local())

	if _block_edit_mode:
		_toggle_blocked_tile(target_cell)
		get_viewport().set_input_as_handled()
		return

	if _fire_at_mode:
		var face_cmd := FaceCommand.new()
		face_cmd.team_id = _session.active_team_id
		face_cmd.target_cell = target_cell
		if _squad_fire_at_mode:
			face_cmd.scope = FaceCommand.Scope.SQUAD
		else:
			face_cmd.scope = FaceCommand.Scope.SINGLE
			face_cmd.soldier_id = _session.get_active_fireteam().selected_soldier_id
		_apply_face_command(face_cmd)
		get_viewport().set_input_as_handled()
		return

	if not _run_to_mode:
		return

	var move_cmd := MoveCommand.new()
	move_cmd.team_id = _session.active_team_id
	move_cmd.target_cell = target_cell
	if _squad_run_to_mode:
		move_cmd.scope = MoveCommand.Scope.SQUAD
	else:
		move_cmd.scope = MoveCommand.Scope.SINGLE
		move_cmd.soldier_id = _session.get_active_fireteam().selected_soldier_id
	_apply_move_command(move_cmd)
	get_viewport().set_input_as_handled()


func _switch_active_team(team_id: int) -> void:
	if team_id == _session.active_team_id:
		return
	_session.set_active_team(team_id)
	_run_to_mode = false
	_squad_run_to_mode = false
	_fire_at_mode = false
	_squad_fire_at_mode = false
	_command_bar.set_active_team(team_id)
	_command_bar.set_selected_soldier(_session.get_active_fireteam().selected_soldier_id)
	_refresh_all_views()
	_command_bar.show_status("Controlling %s team. Press 1/2 to switch." % Team.display_name(team_id))


func _toggle_block_edit_mode() -> void:
	_block_edit_mode = not _block_edit_mode
	if _block_edit_mode:
		_command_bar.clear_run_to_mode()
		_command_bar.clear_fire_at_mode()
		_run_to_mode = false
		_squad_run_to_mode = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
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

	var fireteam := _get_fireteam(cmd.team_id)
	if cmd.scope == MoveCommand.Scope.SQUAD:
		var ordered_count := 0
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if not _execute_move_for_soldier(fireteam, soldier_state, cmd.target_cell).is_empty():
				ordered_count += 1
		if ordered_count == 0:
			_command_bar.show_status("No soldiers could run to that tile.")
			return
		_iso_map.show_path([], cmd.target_cell)
		_command_bar.show_status(
			"%s fireteam running to %s — click another tile to redirect."
			% [Team.display_name(cmd.team_id), cmd.target_cell],
		)
		return

	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	if soldier_state == null:
		return

	var path: Array[Vector2i] = _execute_move_for_soldier(fireteam, soldier_state, cmd.target_cell)
	if path.is_empty():
		if cmd.target_cell == soldier_state.grid_position:
			return
		_command_bar.show_status("No path to that tile.")
		return

	_iso_map.show_path(path, cmd.target_cell)
	_command_bar.show_status(
		"%s Soldier %d running to %s — click another tile to redirect."
		% [Team.display_name(cmd.team_id), cmd.soldier_id, cmd.target_cell],
	)


func _execute_move_for_soldier(
	fireteam: Fireteam,
	state: SoldierState,
	target_cell: Vector2i,
) -> Array[Vector2i]:
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

	fireteam.order_path(state.soldier_id, path)
	if view != null:
		view.follow_path(path)
	return path


## Apply a FaceCommand to the active team's soldier(s).
func _apply_face_command(cmd: FaceCommand) -> void:
	var fireteam := _get_fireteam(cmd.team_id)

	if cmd.scope == FaceCommand.Scope.SQUAD:
		var faced_count := 0
		for state in fireteam.soldiers:
			var soldier_state: SoldierState = state
			if soldier_state.grid_position == cmd.target_cell:
				continue
			if fireteam.face_toward_tile(soldier_state.soldier_id, cmd.target_cell):
				faced_count += 1
		if faced_count == 0:
			_command_bar.show_status("Click a different tile to choose facing.")
			return
		_refresh_all_views()
		var selected_state: SoldierState = fireteam.get_selected()
		if selected_state != null:
			_log_facing_debug(selected_state, cmd.target_cell)
		_command_bar.show_status(
			"%s fireteam facing toward %s — click another tile to re-aim." % [Team.display_name(cmd.team_id), cmd.target_cell],
		)
		return

	var soldier_state: SoldierState = fireteam.get_soldier(cmd.soldier_id)
	if soldier_state == null:
		return
	if cmd.target_cell == soldier_state.grid_position:
		_command_bar.show_status("Click a different tile to choose facing.")
		return
	if not fireteam.face_toward_tile(cmd.soldier_id, cmd.target_cell):
		_command_bar.show_status("Could not face that direction.")
		return

	_refresh_all_views()
	_log_facing_debug(soldier_state, cmd.target_cell)
	_command_bar.show_status(
		"%s Soldier %d facing %s — click another tile to re-aim."
		% [Team.display_name(cmd.team_id), cmd.soldier_id, FacingDirection.direction_name(soldier_state.facing_direction)],
	)


func _log_facing_debug(soldier_state: SoldierState, target_cell: Vector2i) -> void:
	var grid_facing: Vector2i = soldier_state.facing_direction
	var visual_dir: Vector2 = IsometricGrid.grid_facing_to_screen(grid_facing)
	var debug_text := (
		"Facing debug | pos=%s target=%s grid=%s visual=%s (%.0f°)"
		% [
			soldier_state.grid_position,
			target_cell,
			FacingDirection.direction_name(grid_facing),
			visual_dir,
			IsometricGrid.grid_facing_to_degrees(grid_facing),
		]
	)
	print(debug_text)


func _on_soldier_step_reached(team_id: int, soldier_id: int, tile: Vector2i, step_delta: Vector2i) -> void:
	_get_fireteam(team_id).on_soldier_reached_tile(soldier_id, tile, step_delta)


func _on_soldier_movement_finished(team_id: int, soldier_id: int) -> void:
	_get_fireteam(team_id).on_soldier_finished_moving(soldier_id)
	if team_id == _session.active_team_id and not _any_active_team_soldier_moving():
		_iso_map.clear_path()
	_refresh_all_views()
	_command_bar.show_status("%s Soldier %d move complete." % [Team.display_name(team_id), soldier_id])


func _on_run_to_mode_changed(is_active: bool, soldier_id: int) -> void:
	_run_to_mode = is_active
	_squad_run_to_mode = is_active and soldier_id == CommandBar.SQUAD_ID
	if is_active:
		_block_edit_mode = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		if soldier_id > 0:
			_session.get_active_fireteam().select_soldier(soldier_id)
			_refresh_all_views()


func _on_fire_at_mode_changed(is_active: bool, soldier_id: int) -> void:
	_fire_at_mode = is_active
	_squad_fire_at_mode = is_active and soldier_id == CommandBar.SQUAD_ID
	if is_active:
		_block_edit_mode = false
		_run_to_mode = false
		_squad_run_to_mode = false
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
	_command_bar.clear_run_to_mode()
	_command_bar.clear_fire_at_mode()
	_command_bar.set_active_team(_session.active_team_id)
	_refresh_all_views()
	_command_bar.set_selected_soldier(_session.get_active_fireteam().selected_soldier_id)


func _get_world_mouse_local() -> Vector2:
	return _world.to_local(get_global_mouse_position())


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
