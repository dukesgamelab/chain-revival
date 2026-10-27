class_name HandednessDebugOverlay
extends Node2D
## Dev-only: grid axes, compass, landmarks, and ±X/±Y markers for handedness diagnosis.
## Toggle with F4 in editor/gameplay. Does not mutate map data.

const LANDMARK_NAMES: PackedStringArray = [
	"Hundred Acre Woods",
	"Hay field",
	"Western Approach",
	"The Fortress",
	"Garage",
	"Back Forty",
]

const AXIS_ORIGIN := Vector2i(32, 77) ## Near "The Fortress" label
const AXIS_LEN := 6

var map_data: MapData = null
var enabled: bool = false
var selected_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	z_index = 45
	visible = false


func apply_map_data(data: MapData) -> void:
	map_data = data
	queue_redraw()


func set_overlay_enabled(is_on: bool) -> void:
	enabled = is_on
	visible = is_on
	queue_redraw()


func toggle() -> void:
	set_overlay_enabled(not enabled)


func refresh_view_rotation() -> void:
	queue_redraw()


func set_selected_cell(cell: Vector2i) -> void:
	selected_cell = cell
	if enabled:
		queue_redraw()


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled or map_data == null:
		return
	_draw_axis_markers()
	_draw_compass()
	_draw_landmarks()
	_draw_selection()
	_draw_hud()


func _cell_world(cell: Vector2i) -> Vector2:
	return IsometricGrid.grid_to_world(cell)


func _draw_axis_markers() -> void:
	var origin := AXIS_ORIGIN
	if not map_data.is_in_bounds(origin):
		@warning_ignore("integer_division")
		origin = Vector2i(map_data.width / 2, map_data.height / 2)
	var o := _cell_world(origin)
	var px := _cell_world(origin + Vector2i(AXIS_LEN, 0))
	var mx := _cell_world(origin + Vector2i(-AXIS_LEN, 0))
	var py := _cell_world(origin + Vector2i(0, AXIS_LEN))
	var my := _cell_world(origin + Vector2i(0, -AXIS_LEN))
	draw_line(o, px, Color(1.0, 0.25, 0.2, 0.95), 2.0)
	draw_line(o, mx, Color(1.0, 0.45, 0.35, 0.55), 1.5)
	draw_line(o, py, Color(0.25, 0.85, 1.0, 0.95), 2.0)
	draw_line(o, my, Color(0.45, 0.75, 1.0, 0.55), 1.5)
	_label_at(px + Vector2(4, -6), "+X", Color(1.0, 0.35, 0.25))
	_label_at(mx + Vector2(4, -6), "-X", Color(1.0, 0.55, 0.4))
	_label_at(py + Vector2(4, -6), "+Y", Color(0.35, 0.9, 1.0))
	_label_at(my + Vector2(4, -6), "-Y", Color(0.55, 0.85, 1.0))
	_label_at(o + Vector2(6, 10), "origin %s" % origin, Color(1, 1, 1, 0.85))
	## Cardinal world dirs from origin (E=0°, S=90°, W=180°, N=270°).
	var east := _cell_world(origin + Vector2i(AXIS_LEN, 0))
	var south := _cell_world(origin + Vector2i(0, AXIS_LEN))
	var west := _cell_world(origin + Vector2i(-AXIS_LEN, 0))
	var north := _cell_world(origin + Vector2i(0, -AXIS_LEN))
	_label_at(east + Vector2(0, 12), "E/0°", Color(1, 0.8, 0.3))
	_label_at(south + Vector2(0, 12), "S/90°", Color(1, 0.8, 0.3))
	_label_at(west + Vector2(0, 12), "W/180°", Color(1, 0.8, 0.3))
	_label_at(north + Vector2(0, 12), "N/270°", Color(1, 0.8, 0.3))


func _draw_compass() -> void:
	var facet_cam := IsometricGrid.facet_camera_direction_degrees()
	var coord_cam := IsometricGrid.camera_direction_degrees()
	var rot := IsometricGrid.current_view_rotation
	## Screen-fixed compass in world units near origin for current framing.
	var o := _cell_world(AXIS_ORIGIN)
	var tip := o + Vector2(0, -90)
	draw_line(o, tip, Color(1, 1, 0.2, 0.7), 1.5)
	_label_at(
		tip + Vector2(4, -4),
		"facet %d° coord %d° (rot %d)" % [facet_cam, coord_cam, rot],
		Color(1, 1, 0.4),
	)


func _draw_landmarks() -> void:
	if map_data.labels.is_empty():
		return
	for entry in map_data.labels:
		var text := str(entry.get("text", "")).strip_edges()
		if text not in LANDMARK_NAMES:
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var world := _cell_world(cell)
		var visual := IsometricGrid.logical_to_visual_cell(cell)
		draw_circle(world, 5.0, Color(1, 1, 0, 0.9))
		_label_at(
			world + Vector2(8, -18),
			"%s  L%s V%s" % [text, cell, visual],
			Color(1, 1, 0.55),
		)


func _draw_selection() -> void:
	if selected_cell.x < 0 or map_data == null or not map_data.is_in_bounds(selected_cell):
		return
	var world := _cell_world(selected_cell)
	var visual := IsometricGrid.logical_to_visual_cell(selected_cell)
	draw_arc(world, 10.0, 0.0, TAU, 24, Color(0.2, 1.0, 0.4, 0.95), 2.0)
	var vis := map_data.get_visual_at(selected_cell)
	var family := str(vis.get("family", ""))
	var world_dir := int(vis.get("direction", 0))
	var facet_cam := IsometricGrid.facet_camera_direction_degrees()
	var letter := ""
	if not family.is_empty():
		var draw_info := CocSpriteResolver.resolve_placement(family, world_dir, str(vis.get("image1", "")))
		letter = str(draw_info.get("letter", ""))
	_label_at(
		world + Vector2(12, 16),
		"sel L%s V%s fam=%s worldDir=%d° facetCam=%d° letter=%s" % [
			selected_cell, visual, family, world_dir, facet_cam, letter,
		],
		Color(0.4, 1.0, 0.55),
	)


func _draw_hud() -> void:
	var facet_cam := IsometricGrid.facet_camera_direction_degrees()
	var coord_cam := IsometricGrid.camera_direction_degrees()
	var mode := MapCoordinateTransform.candidate_name()
	var lines := PackedStringArray([
		"Handedness debug (F4)  candidate=%s (F5 cycle)" % mode,
		"A=CURRENT (xflip+revCam)  B=legacy  C=xflipOnly  D=reflectH  E=swap  F=flipY  G=dir",
		"facetCam=%d° coordCam=%d° (coord remap stays reversed)" % [facet_cam, coord_cam],
	])
	var anchor := _cell_world(AXIS_ORIGIN) + Vector2(-220, -160)
	var y := anchor.y
	for line in lines:
		_label_at(Vector2(anchor.x, y), line, Color(0.9, 0.95, 1.0, 0.92))
		y += 14


func _label_at(pos: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := 12
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.75))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
