class_name VictoryPointLayer
extends Node2D
## Draws victory / flag tiles: gray diamond with GE (black) or USA (R/W/B) by holder.

var map_data: MapData = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func apply_map_data(data: MapData) -> void:
	map_data = data
	queue_redraw()


func refresh_view_rotation() -> void:
	queue_redraw()


func _draw() -> void:
	if map_data == null:
		return
	for entry in map_data.victory_points:
		if not entry is Dictionary:
			continue
		var cell := Vector2i(int(entry.get("x", -999)), int(entry.get("y", -999)))
		if cell.x <= -900 or not map_data.is_in_bounds(cell):
			continue
		var holder := str(entry.get("holder", entry.get("initial_holder", "Germany"))).strip_edges()
		_draw_flag_tile(cell, holder)


func _draw_flag_tile(cell: Vector2i, holder: String) -> void:
	var center := IsometricGrid.grid_to_world(cell)
	var corners := IsometricGrid.diamond_corners(center)
	var inset := PackedVector2Array()
	for point in corners:
		inset.append(center + (point - center) * 0.78)
	## Gray tile under the flag text (OG GTTL-style marker).
	draw_colored_polygon(inset, Color(0.55, 0.55, 0.58, 0.92))
	draw_polyline(inset, Color(0.22, 0.22, 0.25, 1.0), 1.5, true)

	var scale := (
		OriginalMapProjection.map_scale()
		if map_data.is_original_visual_map()
		else 1.0
	)
	var font := ThemeDB.fallback_font
	var size := maxi(12, int(14.0 * scale))
	var is_usa := _holder_is_usa(holder)
	var label := "USA" if is_usa else "GE"
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var origin := center - Vector2(text_size.x * 0.5, text_size.y * 0.25)

	## Black outline for readability on gray.
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			if ox == 0 and oy == 0:
				continue
			_draw_label_colored(font, origin + Vector2(ox, oy), label, size, is_usa, true)
	_draw_label_colored(font, origin, label, size, is_usa, false)


func _draw_label_colored(
	font: Font,
	origin: Vector2,
	label: String,
	size: int,
	is_usa: bool,
	outline: bool,
) -> void:
	var x := origin.x
	for i in label.length():
		var ch := label.substr(i, 1)
		var color: Color
		if outline:
			color = Color(0, 0, 0, 1)
		elif not is_usa:
			color = Color(0, 0, 0, 1)
		else:
			## Red / white / blue per letter.
			match i % 3:
				0:
					color = Color(0.85, 0.12, 0.14, 1)
				1:
					color = Color(1, 1, 1, 1)
				_:
					color = Color(0.15, 0.28, 0.85, 1)
		draw_string(font, Vector2(x, origin.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func _holder_is_usa(holder: String) -> bool:
	var key := holder.to_lower()
	return key == "usa" or key == "us" or key.contains("american")
