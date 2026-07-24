class_name TerrainDebugOverlay
extends Node2D
## Dev-only: paint Even/Climb/NoPass + height digit on every authored tile (F6).

const COLOR_EVEN := Color(0.20, 0.85, 0.30, 0.28)
const COLOR_CLIMB := Color(0.95, 0.85, 0.15, 0.32)
const COLOR_NO_PASS := Color(0.95, 0.18, 0.15, 0.32)
const COLOR_EMPTY := Color(0.5, 0.5, 0.55, 0.08)

var map_data: MapData = null
var enabled: bool = false


func _ready() -> void:
	z_index = 42
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


func _draw() -> void:
	if not enabled or map_data == null:
		return
	for y in range(map_data.height):
		for x in range(map_data.width):
			var cell := Vector2i(x, y)
			var center := IsometricGrid.grid_to_world(cell)
			var corners := IsometricGrid.diamond_corners(center)
			var terrain := map_data.terrain_class(cell)
			var fill := COLOR_EMPTY
			match terrain:
				MapData.TerrainClass.EVEN:
					fill = COLOR_EVEN if map_data.has_object(cell) else COLOR_EMPTY
				MapData.TerrainClass.CLIMB:
					fill = COLOR_CLIMB
				MapData.TerrainClass.NO_PASS:
					fill = COLOR_NO_PASS
			draw_colored_polygon(corners, fill)
			if map_data.has_object(cell) or terrain != MapData.TerrainClass.EVEN:
				var height := map_data.obstruction_height(cell)
				var label := "%d" % height
				draw_string(
					ThemeDB.fallback_font,
					center + Vector2(-4, 4),
					label,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					12,
					Color(1, 1, 1, 0.9),
				)
