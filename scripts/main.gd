extends Node2D
## Root scene: owns the map, soldier, camera, and command bar.
## Routes mouse clicks to selection or movement depending on command mode.

const SoldierScene := preload("res://scenes/soldier.tscn")

@export var starting_grid_cell := Vector2i(10, 10)

@onready var _world: Node2D = $World
@onready var _iso_map: IsometricMap = $World/IsometricMap
@onready var _soldiers: Node2D = $World/Soldiers
@onready var _camera: Camera2D = $Camera2D
@onready var _command_bar: CommandBar = $UI/CommandBar

var _selected_soldier: Soldier = null
var _run_to_mode: bool = false


func _ready() -> void:
	_command_bar.run_to_mode_changed.connect(_on_run_to_mode_changed)
	_center_camera_on_map()
	_spawn_starting_soldier()
	_command_bar.show_status("WASD moves selected soldier. Run To + click also works.")


## Keyboard and map clicks use _unhandled_input so UI buttons are never misread as map clicks.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_keyboard(event)
		return

	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var world_click := _get_world_mouse_local()

	if _run_to_mode and _selected_soldier != null:
		var target_cell := IsometricGrid.world_to_grid(world_click)
		_move_selected_to_cell(target_cell)
		get_viewport().set_input_as_handled()
		return

	var clicked_soldier := _pick_soldier_at(world_click)
	if clicked_soldier != null:
		_select_soldier(clicked_soldier)
		get_viewport().set_input_as_handled()


func _handle_keyboard(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if _selected_soldier == null:
		return

	var offset := Vector2i.ZERO
	match event.keycode:
		KEY_W:
			offset = Vector2i(0, -1)
		KEY_S:
			offset = Vector2i(0, 1)
		KEY_A:
			offset = Vector2i(-1, 0)
		KEY_D:
			offset = Vector2i(1, 0)
		_:
			return

	var target_cell := _selected_soldier.grid_pos + offset
	_move_selected_to_cell(target_cell)
	get_viewport().set_input_as_handled()


func _spawn_starting_soldier() -> void:
	var soldier: Soldier = SoldierScene.instantiate()
	soldier.set_grid_position(starting_grid_cell)
	soldier.movement_finished.connect(_on_soldier_movement_finished)
	_soldiers.add_child(soldier)
	_select_soldier(soldier)


func _select_soldier(soldier: Soldier) -> void:
	if _selected_soldier != null:
		_selected_soldier.set_selected(false)

	_selected_soldier = soldier
	_selected_soldier.set_selected(true)
	_command_bar.show_status("Soldier selected. Use WASD or Run To.")


func _move_selected_to_cell(target_cell: Vector2i) -> void:
	if _selected_soldier == null:
		return
	if _selected_soldier.is_moving():
		_command_bar.show_status("Soldier is already moving.")
		return
	if target_cell == _selected_soldier.grid_pos:
		return
	if not _iso_map.is_in_bounds(target_cell):
		_command_bar.show_status("That tile is outside the map.")
		return

	var path := _iso_map.find_path(_selected_soldier.grid_pos, target_cell)
	if path.is_empty():
		_command_bar.show_status("No path to that tile.")
		return

	_iso_map.show_path(path, target_cell)
	_selected_soldier.follow_path(path)
	_command_bar.set_run_to_active(false)
	_command_bar.show_status("Moving to %s." % target_cell)


func _pick_soldier_at(local_world_pos: Vector2) -> Soldier:
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = _world.to_global(local_world_pos)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 1

	for hit in space.intersect_point(params):
		var area := hit.collider as Area2D
		if area == null:
			continue
		var soldier := area.get_parent() as Soldier
		if soldier != null:
			return soldier

	return null


func _get_world_mouse_local() -> Vector2:
	return _world.to_local(get_global_mouse_position())


func _center_camera_on_map() -> void:
	var map_center_cell := Vector2i(_iso_map.grid_width / 2, _iso_map.grid_height / 2)
	_camera.position = IsometricGrid.grid_to_world(map_center_cell) + Vector2(0.0, -60.0)


func _on_run_to_mode_changed(is_active: bool) -> void:
	_run_to_mode = is_active
	if is_active and _selected_soldier == null:
		_command_bar.set_run_to_active(false)
		_command_bar.show_status("Select a soldier first.")


func _on_soldier_movement_finished() -> void:
	_iso_map.clear_path()
	_command_bar.show_status("Move complete. WASD or Run To for next move.")
