class_name OriginalGroundLayer
extends Node2D
## Recovered GRS ground fill for original maps (metadata-driven).

var map_data: MapData = null
var _layer_visible: bool = true
var _textures: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	CocTileCatalog.ensure_loaded()


func apply_map_data(data: MapData) -> void:
	map_data = data
	queue_redraw()


## Load every ground variant once so the first full-map _draw does not hitch on disk I/O.
func prewarm_textures() -> void:
	CocTileCatalog.ensure_loaded()
	var n := CocTileCatalog.ground_variant_count()
	for i in n:
		var info := CocTileCatalog.ground_sprite(i)
		_get_texture(str(info.get("path", "")))


func set_layer_visible(show_layer: bool) -> void:
	_layer_visible = show_layer
	visible = show_layer
	queue_redraw()


func is_layer_visible() -> bool:
	return _layer_visible


func refresh_view_rotation() -> void:
	queue_redraw()


func _draw() -> void:
	if not _layer_visible or map_data == null or not map_data.is_original_visual_map():
		return
	if CocTileCatalog.ground_variant_count() <= 0:
		return
	@warning_ignore("shadowed_variable_base_class")
	var scale := OriginalMapProjection.map_scale()
	for y in range(map_data.height):
		for x in range(map_data.width):
			var cell := Vector2i(x, y)
			var visual := _visual_cell(cell)
			var info := CocTileCatalog.ground_sprite(
				CocRenderRules.ground_hash(cell, CocTileCatalog.ground_variant_count())
			)
			var path := str(info.get("path", ""))
			var texture := _get_texture(path)
			if texture == null:
				continue
			var hotspot: Vector2 = info.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
			var top_left := OriginalMapProjection.sprite_top_left(visual, hotspot)
			draw_texture_rect(texture, Rect2(top_left, texture.get_size() * scale), false)


func _visual_cell(cell: Vector2i) -> Vector2i:
	## Use the same presentation remap as IsometricGrid (camera rotation only).
	return IsometricGrid.logical_to_visual_cell(cell)


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
