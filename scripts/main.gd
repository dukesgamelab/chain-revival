extends Node2D
## Root scene: map data, fireteam state, soldier views, and command bar.

const SoldierScene := preload("res://scenes/soldier.tscn")
const FireteamClass := preload("res://scripts/fireteam.gd")
const GameSaveClass := preload("res://scripts/game_save.gd")
const MapDataClass := preload("res://scripts/map_data.gd")

@onready var _world: Node2D = $World
@onready var _iso_map: IsometricMap = $World/IsometricMap
@onready var _soldiers_root: Node2D = $World/Soldiers
@onready var _camera: Camera2D = $Camera2D
@onready var _command_bar: CommandBar = $UI/CommandBar

## Authoritative map gameplay data (reloaded from JSON in _load_map_data).
var _map_data = MapDataClass.create_default()

## Authoritative soldier gameplay data (rebuilt from spawn points on start).
var _fireteam = FireteamClass.new([])

var _soldier_views: Dictionary = {}
var _run_to_mode: bool = false
var _squad_run_to_mode: bool = false
var _fire_at_mode: bool = false
var _squad_fire_at_mode: bool = false
var _block_edit_mode: bool = false


func _ready() -> void:
	_camera.make_current()
	_load_map_data()
	_init_fireteam_from_spawns()
	_connect_command_bar()
	_iso_map.apply_map_data(_map_data)
	_center_camera_on_map()
	_spawn_fireteam_views()
	_refresh_all_views()
	_command_bar.set_selected_soldier(_fireteam.selected_soldier_id)
	_command_bar.show_status("Press B for Block Edit. Use Fire At or Run To on any row.")


func _load_map_data() -> void:
	_map_data = MapDataClass.load_from_file()


func _init_fireteam_from_spawns() -> void:
	var spawn_cells: Array[Vector2i] = _map_data.team_1_spawn_points
	if spawn_cells.is_empty():
		spawn_cells = [
			Vector2i(9, 10),
			Vector2i(10, 10),
			Vector2i(11, 10),
			Vector2i(12, 10),
		]
	_fireteam = FireteamClass.new(spawn_cells)


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

	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var world_click := _get_world_mouse_local()
	var target_cell := IsometricGrid.world_to_grid(world_click)

	if _block_edit_mode:
		_toggle_blocked_tile(target_cell)
		get_viewport().set_input_as_handled()
		return

	if _fire_at_mode:
		if _squad_fire_at_mode:
			_order_fire_at_all(target_cell)
		else:
			_order_fire_at_selected(target_cell)
		get_viewport().set_input_as_handled()
		return

	if not _run_to_mode:
		return

	if _squad_run_to_mode:
		_order_run_to_all(target_cell)
	else:
		_order_run_to_selected(target_cell)
	get_viewport().set_input_as_handled()


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


func _spawn_fireteam_views() -> void:
	for state in _fireteam.soldiers:
		var view: Soldier = SoldierScene.instantiate()
		view.soldier_id = state.soldier_id
		view.movement_step_reached.connect(_on_soldier_step_reached)
		view.movement_finished.connect(_on_soldier_movement_finished)
		_soldiers_root.add_child(view)
		_soldier_views[state.soldier_id] = view


func _refresh_all_views() -> void:
	for state in _fireteam.soldiers:
		var soldier_state: SoldierState = state
		var view: Soldier = _soldier_views[soldier_state.soldier_id]
		var is_selected: bool = soldier_state.soldier_id == _fireteam.selected_soldier_id
		view.sync_from_state(soldier_state, is_selected)


func _get_view(soldier_id: int) -> Soldier:
	return _soldier_views.get(soldier_id) as Soldier


func _any_soldier_moving() -> bool:
	for state in _fireteam.soldiers:
		var view: Soldier = _get_view(state.soldier_id)
		if view != null and view.is_moving():
			return true
	return false


func _on_soldier_selected(soldier_id: int) -> void:
	_fireteam.select_soldier(soldier_id)
	_refresh_all_views()


func _order_run_to_soldier(state: SoldierState, target_cell: Vector2i) -> Array[Vector2i]:
	var view: Soldier = _get_view(state.soldier_id)
	if view != null and view.is_moving():
		return []
	if target_cell == state.grid_position:
		return []
	if not _map_data.is_walkable(target_cell):
		return []

	var path: Array[Vector2i] = _iso_map.find_path(state.grid_position, target_cell)
	if path.is_empty():
		return []

	_fireteam.order_path(state.soldier_id, path)
	view.follow_path(path)
	return path


func _order_run_to_selected(target_cell: Vector2i) -> void:
	var state: SoldierState = _fireteam.get_selected()
	if state == null:
		return

	if not _map_data.is_walkable(target_cell):
		if _map_data.is_blocked(target_cell):
			_command_bar.show_status("That tile is blocked.")
		else:
			_command_bar.show_status("That tile is outside the map.")
		return

	var path: Array[Vector2i] = _order_run_to_soldier(state, target_cell)
	if path.is_empty():
		if target_cell == state.grid_position:
			return
		if _get_view(state.soldier_id) != null and _get_view(state.soldier_id).is_moving():
			_command_bar.show_status("Soldier %d is already moving." % state.soldier_id)
		else:
			_command_bar.show_status("No path to that tile.")
		return

	_iso_map.show_path(path, target_cell)
	_command_bar.clear_run_to_mode()
	_command_bar.show_status("Soldier %d running to %s." % [state.soldier_id, target_cell])


func _order_run_to_all(target_cell: Vector2i) -> void:
	if not _map_data.is_walkable(target_cell):
		if _map_data.is_blocked(target_cell):
			_command_bar.show_status("That tile is blocked.")
		else:
			_command_bar.show_status("That tile is outside the map.")
		return

	var ordered_count := 0
	for state in _fireteam.soldiers:
		var soldier_state: SoldierState = state
		if not _order_run_to_soldier(soldier_state, target_cell).is_empty():
			ordered_count += 1

	if ordered_count == 0:
		_command_bar.show_status("No soldiers could run to that tile.")
		return

	_iso_map.show_path([], target_cell)
	_command_bar.clear_run_to_mode()
	_command_bar.show_status("Fireteam running to %s (%d soldiers)." % [target_cell, ordered_count])


func _order_fire_at_selected(target_cell: Vector2i) -> void:
	var state: SoldierState = _fireteam.get_selected()
	if state == null:
		return

	if target_cell == state.grid_position:
		_command_bar.show_status("Click a different tile to choose facing.")
		return

	if not _fireteam.face_toward_tile(state.soldier_id, target_cell):
		_command_bar.show_status("Could not face that direction.")
		return

	_refresh_all_views()
	_command_bar.clear_fire_at_mode()
	_command_bar.show_status(
		"Soldier %d facing %s." % [state.soldier_id, FacingDirection.direction_name(state.facing_direction)],
	)


func _order_fire_at_all(target_cell: Vector2i) -> void:
	var faced_count := 0
	for state in _fireteam.soldiers:
		var soldier_state: SoldierState = state
		if soldier_state.grid_position == target_cell:
			continue
		if _fireteam.face_toward_tile(soldier_state.soldier_id, target_cell):
			faced_count += 1

	if faced_count == 0:
		_command_bar.show_status("Click a different tile to choose facing.")
		return

	_refresh_all_views()
	_command_bar.clear_fire_at_mode()
	_command_bar.show_status("Fireteam facing toward %s." % target_cell)


func _on_soldier_step_reached(soldier_id: int, tile: Vector2i, step_delta: Vector2i) -> void:
	_fireteam.on_soldier_reached_tile(soldier_id, tile, step_delta)


func _on_soldier_movement_finished(soldier_id: int) -> void:
	_fireteam.on_soldier_finished_moving(soldier_id)
	if not _any_soldier_moving():
		_iso_map.clear_path()
	_refresh_all_views()
	_command_bar.show_status("Soldier %d move complete." % soldier_id)


func _on_run_to_mode_changed(is_active: bool, soldier_id: int) -> void:
	_run_to_mode = is_active
	_squad_run_to_mode = is_active and soldier_id == CommandBar.SQUAD_ID
	if is_active:
		_block_edit_mode = false
		_fire_at_mode = false
		_squad_fire_at_mode = false
		if soldier_id > 0:
			_fireteam.select_soldier(soldier_id)
			_refresh_all_views()


func _on_fire_at_mode_changed(is_active: bool, soldier_id: int) -> void:
	_fire_at_mode = is_active
	_squad_fire_at_mode = is_active and soldier_id == CommandBar.SQUAD_ID
	if is_active:
		_block_edit_mode = false
		_run_to_mode = false
		_squad_run_to_mode = false
		if soldier_id > 0:
			_fireteam.select_soldier(soldier_id)
			_refresh_all_views()


func _on_save_requested() -> void:
	if GameSaveClass.save_game(_fireteam, _map_data):
		_command_bar.show_status("Game saved.")
	else:
		_command_bar.show_status("Save failed.")


func _on_load_requested() -> void:
	if not GameSaveClass.load_game(_fireteam):
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
	_center_camera_on_map()
	_sync_views_after_load()
	_command_bar.show_status("Map loaded from res://maps/test_map.json")


func _sync_views_after_load() -> void:
	for state in _fireteam.soldiers:
		var soldier_state: SoldierState = state
		var view: Soldier = _get_view(soldier_state.soldier_id)
		if view == null:
			continue
		view.stop_movement()
		var is_selected: bool = soldier_state.soldier_id == _fireteam.selected_soldier_id
		view.sync_from_state(soldier_state, is_selected)

	_iso_map.clear_path()
	_command_bar.clear_run_to_mode()
	_command_bar.clear_fire_at_mode()
	_refresh_all_views()
	_command_bar.set_selected_soldier(_fireteam.selected_soldier_id)


func _get_world_mouse_local() -> Vector2:
	return _world.to_local(get_global_mouse_position())


func _center_camera_on_map() -> void:
	if _map_data == null:
		return
	var cx := floori(_map_data.width / 2.0)
	var cy := floori(_map_data.height / 2.0)
	var map_center_cell := Vector2i(cx, cy)
	_camera.position = IsometricGrid.grid_to_world(map_center_cell) + Vector2(0.0, -90.0)
