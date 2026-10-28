class_name CocPlacementPreviewLayer
extends Node2D
## Editor ghost preview — uses CocSpriteResolver (same pipeline as DepthSortedLayer).
## Drawn under DepthSorted so ghosts/path tiles stay beneath walls and soldiers.

var _family: String = ""
var _world_direction: int = 0
var _cell: Vector2i = Vector2i(-999, -999)
var _textures: Dictionary = {}


func set_preview(family: String, world_direction_degrees: int, cell: Vector2i) -> void:
	## Always redraw — camera may have changed with the same family/world dir/cell.
	_family = family.to_upper()
	_world_direction = world_direction_degrees
	_cell = cell
	queue_redraw()


func clear_preview() -> void:
	if _family.is_empty() and _cell.x <= -900:
		return
	_family = ""
	_world_direction = 0
	_cell = Vector2i(-999, -999)
	queue_redraw()


func refresh_view_rotation() -> void:
	## Camera changed — re-resolve facet for the same world direction.
	queue_redraw()


func _draw() -> void:
	if _family.is_empty() or _cell.x <= -900:
		return
	var info := CocSpriteResolver.resolve_preview(_family, _world_direction)
	if bool(info.get("unusable", false)) or bool(info.get("missing", false)):
		return
	var path := str(info.get("path", ""))
	var texture := _get_texture(path)
	if texture == null:
		return
	@warning_ignore("shadowed_variable_base_class")
	var scale := OriginalMapProjection.map_scale()
	var hotspot: Vector2 = info.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
	## Match DepthSortedLayer: holder at cell world point, sprite at hotspot * scale.
	var cell_world := IsometricGrid.grid_to_world(_cell)
	var pos := cell_world + hotspot * scale
	draw_texture_rect(
		texture,
		Rect2(pos, texture.get_size() * scale),
		false,
		Color(1.0, 1.0, 1.0, 0.55),
	)


func _get_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not CocTileCatalog.exists(path) and not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture
