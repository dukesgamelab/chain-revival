class_name MapCamera
extends Camera2D
## Pan/zoom camera for the isometric map. Keeps the view inside map bounds.

@export var pan_speed := 520.0
@export var default_zoom := Vector2(0.55, 0.55)
@export var zoom_min := 0.35
@export var zoom_max := 2.0
@export var zoom_step := 0.08
@export var edge_margin := 24.0
## Nudge camera up so soldiers sit above the bottom command bar.
@export var focus_vertical_offset := -56.0

var _map_width: int = 0
var _map_height: int = 0
var _map_bounds := Rect2()
var _dragging := false
var _drag_button := MOUSE_BUTTON_NONE


func _ready() -> void:
	enabled = true
	zoom = default_zoom
	get_tree().root.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if _map_width > 0:
		_clamp_position()


## Call whenever map width/height changes so clamping stays correct.
func set_map_size(map_width: int, map_height: int) -> void:
	_map_width = map_width
	_map_height = map_height
	_map_bounds = IsometricGrid.get_map_world_bounds(
		map_width,
		map_height,
		IsometricGrid.MAP_VISUAL_BORDER,
	)
	_clamp_position()


## Default CoC-style view: fixed zoom, centered on a world point (usually the fireteam).
func reset_to_default_view(world_focus: Vector2) -> void:
	zoom = default_zoom
	position = world_focus + Vector2(0.0, focus_vertical_offset)
	_clamp_position()


## Move camera to the world center of a grid cell (used after map load).
func snap_to_cell(cell: Vector2i, vertical_offset: float = TileSizeConfig.CAMERA_SNAP_VERTICAL_OFFSET) -> void:
	position = IsometricGrid.grid_to_world(cell) + Vector2(0.0, vertical_offset)
	_clamp_position()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		move.y -= 1.0
	if Input.is_action_pressed("move_down"):
		move.y += 1.0
	if Input.is_action_pressed("move_left"):
		move.x -= 1.0
	if Input.is_action_pressed("move_right"):
		move.x += 1.0

	if move != Vector2.ZERO:
		position += move.normalized() * pan_speed * delta
		_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _dragging:
		_handle_drag(event as InputEventMouseMotion)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_apply_zoom(zoom_step)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_apply_zoom(-zoom_step)
		get_viewport().set_input_as_handled()
	elif event.pressed and (event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT):
		_dragging = true
		_drag_button = event.button_index
		get_viewport().set_input_as_handled()
	elif not event.pressed and event.button_index == _drag_button:
		_dragging = false
		_drag_button = MOUSE_BUTTON_NONE
		get_viewport().set_input_as_handled()


func _handle_drag(event: InputEventMouseMotion) -> void:
	position -= event.relative / zoom
	_clamp_position()
	get_viewport().set_input_as_handled()


func _apply_zoom(delta_zoom: float) -> void:
	var old_zoom := zoom.x
	var new_zoom := clampf(old_zoom + delta_zoom, zoom_min, zoom_max)
	if is_equal_approx(new_zoom, old_zoom):
		return

	var mouse_world := _world_mouse_position()
	zoom = Vector2(new_zoom, new_zoom)
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_screen := get_viewport().get_mouse_position()
	position = mouse_world - (mouse_screen - viewport_size * 0.5) / zoom.x
	_clamp_position()


func _world_mouse_position() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_screen := get_viewport().get_mouse_position()
	return position + (mouse_screen - viewport_size * 0.5) / zoom.x


func _clamp_position() -> void:
	if _map_bounds.size == Vector2.ZERO:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var half_view := (viewport_size * 0.5) / zoom.x

	var min_x := _map_bounds.position.x + half_view.x - edge_margin
	var max_x := _map_bounds.end.x - half_view.x + edge_margin
	var min_y := _map_bounds.position.y + half_view.y - edge_margin
	var max_y := _map_bounds.end.y - half_view.y + edge_margin

	if min_x > max_x:
		position.x = _map_bounds.get_center().x
	else:
		position.x = clampf(position.x, min_x, max_x)

	if min_y > max_y:
		position.y = _map_bounds.get_center().y
	else:
		position.y = clampf(position.y, min_y, max_y)
