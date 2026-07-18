class_name OriginalFloorLayer
extends Node2D
## Authored floor tiles for original maps (labels live on OriginalLabelLayer).

var map_data: MapData = null
var _textures: Dictionary = {}
var _missing_logged: Dictionary = {}


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
	var scale := OriginalMapProjection.map_scale()
	for entry in map_data.floors:
		_draw_family_tile(
			Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))),
			str(entry.get("image", "")),
			int(entry.get("direction", 0)),
			scale,
		)


func _draw_family_tile(cell: Vector2i, family: String, direction: int, scale: float) -> void:
	if map_data == null or not map_data.is_in_bounds(cell):
		return
	var visual := IsometricGrid.logical_to_visual_cell(cell)
	var draw_info := CocRenderRules.resolve_floor_display(family, direction)
	if CocRenderRules.is_unusable_sprite(draw_info):
		_log_missing(family, str(draw_info.get("letter", "?")))
		return
	var path := str(draw_info.get("path", ""))
	var texture := _get_texture(path)
	if texture == null:
		_log_missing(family, str(draw_info.get("letter", "?")))
		return
	var hotspot: Vector2 = draw_info.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
	var top_left := OriginalMapProjection.sprite_top_left(visual, hotspot)
	draw_texture_rect(texture, Rect2(top_left, texture.get_size() * scale), false)


func _log_missing(family: String, letter: String) -> void:
	var key := "%s_%s" % [family, letter]
	if _missing_logged.has(key):
		return
	_missing_logged[key] = true
	push_warning("OriginalFloorLayer: missing sprite family=%s letter=%s" % [family, letter])


func _get_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not CocTileCatalog.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture
