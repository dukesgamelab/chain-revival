class_name LosVisualizer
extends Node2D
## Aim preview cone while Fire At mode is active (separate from fired shot tracers).

const FireAtPreviewResultClass := preload("res://scripts/combat/fire_at_preview_result.gd")
const LOSSystemClass := preload("res://scripts/combat/los_system.gd")

const CONE_COLOR_HAS_TARGET := Color(0.25, 0.95, 0.35, 0.16)
const CONE_COLOR_NO_TARGET := Color(0.95, 0.18, 0.12, 0.16)

var _cone: Polygon2D
var _aim_line: Line2D


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


func show_fire_at_preview(
	from_world: Vector2,
	cone_world_points: PackedVector2Array,
	preview: FireAtPreviewResultClass,
) -> void:
	_cone.visible = true
	_aim_line.visible = true
	_cone.polygon = cone_world_points
	_cone.color = (
		CONE_COLOR_HAS_TARGET
		if preview.targetable and preview.enemy_in_cone
		else CONE_COLOR_NO_TARGET
	)
	_aim_line.points = PackedVector2Array([from_world, preview.aim_to_world])
	_aim_line.default_color = LOSSystemClass.preview_line_color(preview)


func hide_preview() -> void:
	_cone.visible = false
	_aim_line.visible = false
