class_name LosVisualizer
extends Node2D
## Aim preview cone while Fire At mode is active (separate from fired shot tracers).
## Drawing is gated by debug_visible (test overlay; off by default, toggle with T).
## When a shooter→target pair is previewed, qualifying directional cover tiles are highlighted.

const FireAtPreviewResultClass := preload("res://scripts/combat/fire_at_preview_result.gd")
const LOSSystemClass := preload("res://scripts/combat/los_system.gd")
const CoverPolicyClass := preload("res://scripts/gameplay_policies/cover_policy.gd")

const CONE_COLOR_HAS_TARGET := Color(0.25, 0.95, 0.35, 0.16)
const CONE_COLOR_NO_TARGET := Color(0.95, 0.18, 0.12, 0.16)
const COVER_TILE_COLOR := Color(0.95, 0.78, 0.12, 0.42)
const COVER_CORNER_COLOR := Color(0.95, 0.45, 0.12, 0.50)

## When false, show_* calls are ignored / cleared (test overlay).
var debug_visible: bool = false

var _cone: Polygon2D
var _aim_line: Line2D
var _squad_aim_lines: Array[Line2D] = []
var _cover_cells: Array[Vector2i] = []
var _cover_qualifier: int = CoverPolicyClass.Qualifier.NONE


func _ready() -> void:
	_cone = Polygon2D.new()
	_cone.z_index = 5
	_cone.visible = false
	add_child(_cone)

	_aim_line = Line2D.new()
	_aim_line.width = 2.5
	_aim_line.z_index = 6
	_aim_line.visible = false
	add_child(_aim_line)


func set_debug_visible(enabled: bool) -> void:
	debug_visible = enabled
	if not debug_visible:
		hide_preview()


func show_fire_at_preview(
	from_world: Vector2,
	cone_world_points: PackedVector2Array,
	preview: FireAtPreviewResultClass,
) -> void:
	if not debug_visible:
		hide_preview()
		return
	_clear_squad_aim_lines()
	_aim_line.visible = true
	_cone.visible = true
	_cone.polygon = cone_world_points
	_cone.color = (
		CONE_COLOR_HAS_TARGET
		if preview.targetable and preview.enemy_in_cone
		else CONE_COLOR_NO_TARGET
	)
	_aim_line.points = PackedVector2Array([from_world, preview.aim_to_world])
	_aim_line.default_color = LOSSystemClass.preview_line_color(preview)
	_set_cover_highlight_from_los(preview.los if preview != null else null)
	queue_redraw()


func show_squad_fire_at_previews(
	entries: Array,
	cone_world_points: PackedVector2Array,
	cone_has_target: bool,
) -> void:
	if not debug_visible:
		hide_preview()
		return
	_clear_squad_aim_lines()
	_aim_line.visible = false
	_cone.visible = true
	_cone.polygon = cone_world_points
	_cone.color = CONE_COLOR_HAS_TARGET if cone_has_target else CONE_COLOR_NO_TARGET

	var first_los = null
	for entry in entries:
		var from_world: Vector2 = entry.get("from_world", Vector2.ZERO)
		var preview: FireAtPreviewResultClass = entry.get("preview")
		if preview == null:
			continue
		var line := Line2D.new()
		line.width = 2.5
		line.z_index = 6
		line.points = PackedVector2Array([from_world, preview.aim_to_world])
		line.default_color = LOSSystemClass.preview_line_color(preview)
		add_child(line)
		_squad_aim_lines.append(line)
		if first_los == null and preview.los != null:
			first_los = preview.los
	_set_cover_highlight_from_los(first_los)
	queue_redraw()


func show_grenade_throw_preview(
	from_world: Vector2,
	target_world: Vector2,
	in_range: bool,
) -> void:
	if not debug_visible:
		hide_preview()
		return
	_clear_squad_aim_lines()
	_cone.visible = false
	_aim_line.visible = true
	_aim_line.points = PackedVector2Array([from_world, target_world])
	_aim_line.default_color = (
		LOSSystemClass.COLOR_CLEAR if in_range else LOSSystemClass.COLOR_BLOCKED
	)
	_clear_cover_highlight()
	queue_redraw()


## Explicit shooter→target cover highlight (tests / debug tools).
func show_directional_cover_cells(
	qualifying_cells: Array[Vector2i],
	qualifier: int = CoverPolicyClass.Qualifier.NONE,
) -> void:
	if not debug_visible:
		return
	_cover_cells = qualifying_cells.duplicate()
	_cover_qualifier = qualifier
	queue_redraw()


func hide_preview() -> void:
	_cone.visible = false
	_aim_line.visible = false
	_clear_squad_aim_lines()
	_clear_cover_highlight()
	queue_redraw()


func _set_cover_highlight_from_los(los) -> void:
	if los == null:
		_clear_cover_highlight()
		return
	_cover_cells = []
	for cell in los.cover_qualifying_cells:
		_cover_cells.append(cell)
	_cover_qualifier = int(los.cover_qualifier)


func _clear_cover_highlight() -> void:
	_cover_cells.clear()
	_cover_qualifier = CoverPolicyClass.Qualifier.NONE


func _clear_squad_aim_lines() -> void:
	for line in _squad_aim_lines:
		if is_instance_valid(line):
			line.queue_free()
	_squad_aim_lines.clear()


func _draw() -> void:
	if not debug_visible or _cover_cells.is_empty():
		return
	var fill := (
		COVER_CORNER_COLOR
		if _cover_qualifier == CoverPolicyClass.Qualifier.CORNER
		else COVER_TILE_COLOR
	)
	for cell in _cover_cells:
		var center := IsometricGrid.grid_to_world(cell)
		var corners := IsometricGrid.diamond_corners(center)
		draw_colored_polygon(corners, fill)
