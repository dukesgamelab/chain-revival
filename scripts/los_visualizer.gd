class_name LosVisualizer
extends Node2D
## Aim preview line while Fire At mode is active (separate from fired shot tracers).

const LOSSystemClass := preload("res://scripts/los_system.gd")

var _line: Line2D


func _ready() -> void:
	_line = Line2D.new()
	_line.width = 2.5
	_line.z_index = 6
	_line.visible = false
	add_child(_line)


func show_preview(from_world: Vector2, to_world: Vector2, los_result) -> void:
	_line.visible = true
	_line.points = PackedVector2Array([from_world, to_world])
	_line.default_color = LOSSystemClass.status_color(los_result.status)


func hide_preview() -> void:
	_line.visible = false
