class_name DepthSortedLayer
extends Node2D
## Y-sorted presentation layer for map object sprites and soldier views.

const META_MAP_OBJECT := &"map_object_sprite"

const _TEXTURE_WALL_STRAIGHT := preload("res://assets/sprites/wall-straight-1-tile.png")

var map_data: MapData = null

var _object_textures: Dictionary = {}


func apply_map_data(data: MapData) -> void:
	map_data = data
	_rebuild_map_object_sprites()


func refresh_view_rotation() -> void:
	if map_data != null:
		_rebuild_map_object_sprites()


func _rebuild_map_object_sprites() -> void:
	for child in get_children():
		if child.has_meta(META_MAP_OBJECT):
			child.queue_free()

	if map_data == null:
		return

	for cell in map_data.get_object_cells():
		var type_id: String = map_data.get_object_type(cell)
		var object_def := MapObjectRegistry.get_def(type_id)
		if object_def == null or object_def.sprite_path.is_empty():
			continue
		var texture: Texture2D = _get_object_texture(object_def.sprite_path)
		if texture == null:
			push_warning("DepthSortedLayer: missing texture for '%s' at %s" % [type_id, cell])
			continue

		var sprite := Sprite2D.new()
		sprite.set_meta(META_MAP_OBJECT, true)
		sprite.texture = texture
		var center := IsometricGrid.grid_to_world(cell)
		var size := texture.get_size()
		sprite.position = _map_object_position(type_id, center, size)
		add_child(sprite)


func _map_object_position(type_id: String, center: Vector2, size: Vector2) -> Vector2:
	if type_id == MapObjectRegistry.TYPE_WALL_STRAIGHT:
		return Vector2(center.x, center.y - size.y * 0.5 + IsometricGrid.TILE_HEIGHT * 0.45)
	return center + Vector2(0.0, -8.0)


func _get_object_texture(sprite_path: String) -> Texture2D:
	if sprite_path == MapObjectRegistry.SPRITE_WALL_STRAIGHT:
		return _TEXTURE_WALL_STRAIGHT
	if _object_textures.has(sprite_path):
		return _object_textures[sprite_path] as Texture2D
	var texture: Texture2D = load(sprite_path) as Texture2D
	if texture != null:
		_object_textures[sprite_path] = texture
	return texture
