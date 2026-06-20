class_name GrassTerrainLayer
extends Node2D
## Presentation-only grass texture fill for every playable map cell (toggle with B in dev).

const GRASS_TEXTURE := preload("res://assets/sprites/grass_base_tile.png")

var map_data: MapData = null
var _layer_visible: bool = true


func _ready() -> void:
	queue_redraw()


func apply_map_data(data: MapData) -> void:
	map_data = data
	queue_redraw()


func set_layer_visible(show_layer: bool) -> void:
	_layer_visible = show_layer
	visible = show_layer
	queue_redraw()


func is_layer_visible() -> bool:
	return _layer_visible


func refresh_view_rotation() -> void:
	queue_redraw()


func _draw() -> void:
	if not _layer_visible or map_data == null:
		return

	var size := GRASS_TEXTURE.get_size()
	var half := size * 0.5
	for y in range(map_data.height):
		for x in range(map_data.width):
			_draw_grass_at_cell(Vector2i(x, y), half)

	var border := IsometricGrid.MAP_VISUAL_BORDER
	for ring in range(1, border + 1):
		var x_min := -ring
		var x_max := map_data.width - 1 + ring
		var y_min := -ring
		var y_max := map_data.height - 1 + ring
		for x in range(x_min, x_max + 1):
			_draw_grass_at_cell(Vector2i(x, y_min), half)
			if y_max != y_min:
				_draw_grass_at_cell(Vector2i(x, y_max), half)
		for y in range(y_min + 1, y_max):
			_draw_grass_at_cell(Vector2i(x_min, y), half)
			if x_max != x_min:
				_draw_grass_at_cell(Vector2i(x_max, y), half)


func _draw_grass_at_cell(cell: Vector2i, half: Vector2) -> void:
	var center := IsometricGrid.grid_to_world(cell)
	draw_set_transform(center, 0.0, Vector2(1.04, 1.04))
	draw_texture(GRASS_TEXTURE, -half)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
