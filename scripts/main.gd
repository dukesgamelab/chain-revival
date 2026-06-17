extends Node2D
## Root scene: connects map rendering, fireteam gameplay state, soldier views, and the command bar.

const SoldierScene := preload("res://scenes/soldier.tscn")
const FireteamClass := preload("res://scripts/fireteam.gd")
const GameSaveClass := preload("res://scripts/game_save.gd")

## Default spawn formation near map center (logical grid cells).
const DEFAULT_START_CELLS: Array[Vector2i] = [
	Vector2i(9, 10),
	Vector2i(10, 10),
	Vector2i(11, 10),
	Vector2i(12, 10),
]

@onready var _world: Node2D = $World
@onready var _iso_map: IsometricMap = $World/IsometricMap
@onready var _soldiers_root: Node2D = $World/Soldiers
@onready var _camera: Camera2D = $Camera2D
@onready var _command_bar: CommandBar = $UI/CommandBar

## Gameplay state (no rendering).
var _fireteam = FireteamClass.new(DEFAULT_START_CELLS)

## soldier_id -> Soldier view node.
var _soldier_views: Dictionary = {}

var _run_to_mode: bool = false


func _ready() -> void:
	_camera.make_current()
	_connect_command_bar()
	_center_camera_on_map()
	_spawn_fireteam_views()
	_refresh_all_views()
	_command_bar.set_selected_soldier(_fireteam.selected_soldier_id)


func _connect_command_bar() -> void:
	_command_bar.soldier_selected.connect(_on_soldier_selected)
	_command_bar.run_to_mode_changed.connect(_on_run_to_mode_changed)
	_command_bar.save_requested.connect(_on_save_requested)
	_command_bar.load_requested.connect(_on_load_requested)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _run_to_mode:
		return

	var world_click := _get_world_mouse_local()
	var target_cell := IsometricGrid.world_to_grid(world_click)
	_order_run_to_selected(target_cell)
	get_viewport().set_input_as_handled()


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
		var view: Soldier = _soldier_views[state.soldier_id]
		var is_selected := state.soldier_id == _fireteam.selected_soldier_id
		view.sync_from_state(state, is_selected)


func _get_view(soldier_id: int) -> Soldier:
	return _soldier_views.get(soldier_id) as Soldier


func _on_soldier_selected(soldier_id: int) -> void:
	_fireteam.select_soldier(soldier_id)
	_refresh_all_views()


func _order_run_to_selected(target_cell: Vector2i) -> void:
	var state := _fireteam.get_selected()
	if state == null:
		return

	var view := _get_view(state.soldier_id)
	if view != null and view.is_moving():
		_command_bar.show_status("Soldier %d is already moving." % state.soldier_id)
		return
	if target_cell == state.grid_position:
		return
	if not _iso_map.is_in_bounds(target_cell):
		_command_bar.show_status("That tile is outside the map.")
		return

	var path := _iso_map.find_path(state.grid_position, target_cell)
	if path.is_empty():
		_command_bar.show_status("No path to that tile.")
		return

	_fireteam.order_path(state.soldier_id, path)
	_iso_map.show_path(path, target_cell)
	view.follow_path(path)
	_command_bar.clear_run_to_mode()
	_command_bar.show_status("Soldier %d running to %s." % [state.soldier_id, target_cell])


func _on_soldier_step_reached(soldier_id: int, tile: Vector2i, step_delta: Vector2i) -> void:
	_fireteam.on_soldier_reached_tile(soldier_id, tile, step_delta)


func _on_soldier_movement_finished(soldier_id: int) -> void:
	_fireteam.on_soldier_finished_moving(soldier_id)
	_iso_map.clear_path()
	_refresh_all_views()
	_command_bar.show_status("Soldier %d move complete." % soldier_id)


func _on_run_to_mode_changed(is_active: bool, soldier_id: int) -> void:
	_run_to_mode = is_active
	if is_active:
		_fireteam.select_soldier(soldier_id)
		_refresh_all_views()


func _on_save_requested() -> void:
	if GameSaveClass.save_game(_fireteam, _iso_map):
		_command_bar.show_status("Game saved.")
	else:
		_command_bar.show_status("Save failed.")


func _on_load_requested() -> void:
	if not GameSaveClass.load_game(_fireteam, _iso_map):
		_command_bar.show_status("Load failed.")
		return

	for state in _fireteam.soldiers:
		var view := _get_view(state.soldier_id)
		if view == null:
			continue
		view.stop_movement()
		view.sync_from_state(state, state.soldier_id == _fireteam.selected_soldier_id)

	_iso_map.clear_path()
	_command_bar.clear_run_to_mode()
	_refresh_all_views()
	_command_bar.set_selected_soldier(_fireteam.selected_soldier_id)
	_command_bar.show_status("Game loaded.")


func _get_world_mouse_local() -> Vector2:
	return _world.to_local(get_global_mouse_position())


func _center_camera_on_map() -> void:
	var cx := floori(_iso_map.grid_width / 2.0)
	var cy := floori(_iso_map.grid_height / 2.0)
	var map_center_cell := Vector2i(cx, cy)
	_camera.position = IsometricGrid.grid_to_world(map_center_cell) + Vector2(0.0, -90.0)
