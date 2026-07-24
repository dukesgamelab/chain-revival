class_name LosVisualizer
extends Node2D
## Aim preview cone while Fire At mode is active (separate from fired shot tracers).
## Drawing is gated by debug_visible (test overlay; off by default, toggle with T).

const FireAtPreviewResultClass := preload("res://scripts/combat/fire_at_preview_result.gd")
const LOSSystemClass := preload("res://scripts/combat/los_system.gd")

const CONE_COLOR_HAS_TARGET := Color(0.25, 0.95, 0.35, 0.16)
const CONE_COLOR_NO_TARGET := Color(0.95, 0.18, 0.12, 0.16)

## When false, show_* calls are ignored / cleared (test overlay).
var debug_visible: bool = false

var _cone: Polygon2D
var _aim_line: Line2D
var _squad_aim_lines: Array[Line2D] = []


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


func hide_preview() -> void:
	_cone.visible = false
	_aim_line.visible = false
	_clear_squad_aim_lines()


func _clear_squad_aim_lines() -> void:
	for line in _squad_aim_lines:
		if is_instance_valid(line):
			line.queue_free()
	_squad_aim_lines.clear()
