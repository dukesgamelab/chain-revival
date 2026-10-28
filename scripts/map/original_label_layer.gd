class_name OriginalLabelLayer
extends Node2D
## Yellow map labels drawn above objects (handoff draw order).

var map_data: MapData = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func apply_map_data(data: MapData) -> void:
	map_data = data
	queue_redraw()


func refresh_view_rotation() -> void:
	queue_redraw()


func _draw() -> void:
	if map_data == null or not map_data.is_original_visual_map():
		return
	@warning_ignore("shadowed_variable_base_class")
	var scale := OriginalMapProjection.map_scale()
	for entry in map_data.labels:
		var text := str(entry.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var visual := IsometricGrid.logical_to_visual_cell(cell)
		var pos := OriginalMapProjection.cell_to_world(visual)
		var font := ThemeDB.fallback_font
		var size := maxi(10, int(11.0 * scale))
		draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 1))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 1.0, 0.0, 1.0))
