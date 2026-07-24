class_name DepthSortedLayer
extends Node2D
## Y-sorted presentation layer for map object sprites and soldier views.
## Original CoC objects always resolve facets via CocSpriteResolver (shared with editor).

const META_MAP_OBJECT := &"map_object_sprite"

const _TEXTURE_WALL_STRAIGHT := preload("res://assets/sprites/wall-straight-1-tile.png")

var map_data: MapData = null

var _object_textures: Dictionary = {}
var _placeholder_count: int = 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func apply_map_data(data: MapData) -> void:
	map_data = data
	_rebuild_map_object_sprites()


func refresh_view_rotation() -> void:
	if map_data != null:
		_rebuild_map_object_sprites()


func _rebuild_map_object_sprites() -> void:
	## Free immediately — queue_free leaves stale camera facets visible until idle frame.
	_clear_map_object_sprites()

	if map_data == null:
		return

	_placeholder_count = 0
	if map_data.is_original_visual_map():
		_rebuild_original_sprites()
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
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = texture
		var scale_factor := TileSizeConfig.object_scale_for_type(type_id)
		sprite.scale = Vector2(scale_factor, scale_factor)
		var center := IsometricGrid.grid_to_world(cell)
		var size := texture.get_size() * scale_factor
		sprite.position = _native_map_object_position(type_id, center, size)
		add_child(sprite)


func _clear_map_object_sprites() -> void:
	var stale: Array[Node] = []
	for child in get_children():
		if child.has_meta(META_MAP_OBJECT):
			stale.append(child)
	for child in stale:
		remove_child(child)
		child.free()


func _rebuild_original_sprites() -> void:
	var scale := OriginalMapProjection.map_scale()
	var placements: Array = map_data.visual_placements.duplicate()
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cell := Vector2i(int(a.get("x", 0)), int(a.get("y", 0)))
		var b_cell := Vector2i(int(b.get("x", 0)), int(b.get("y", 0)))
		var av := IsometricGrid.logical_to_visual_cell(a_cell)
		var bv := IsometricGrid.logical_to_visual_cell(b_cell)
		var a_key := av.x + av.y
		var b_key := bv.x + bv.y
		if a_key == b_key:
			return int(a.get("z", 0)) < int(b.get("z", 0))
		return a_key < b_key
	)

	for entry in placements:
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if not map_data.is_in_bounds(cell):
			continue
		var family := str(entry.get("family", "")).to_upper()
		if family.is_empty():
			var source: Dictionary = entry.get("source", {}) if entry.get("source", {}) is Dictionary else {}
			family = str(source.get("image", "")).to_upper()
		if family.is_empty() or family == "NEAR":
			continue

		## Authoritative data: family + world direction only. Never read baked sprite paths.
		var direction := int(entry.get("direction", 0))
		var image1 := str(entry.get("image1", "")).to_upper()
		var draw_info := CocSpriteResolver.resolve_placement(family, direction, image1)
		if bool(draw_info.get("unusable", false)):
			_placeholder_count += 1
			continue
		var path := str(draw_info.get("path", ""))
		var texture := _get_object_texture(path)
		if texture == null:
			_placeholder_count += 1
			continue

		var holder := Node2D.new()
		holder.set_meta(META_MAP_OBJECT, true)
		holder.set_meta(&"coc_family", family)
		holder.set_meta(&"coc_direction", direction)
		holder.set_meta(&"coc_letter", str(draw_info.get("letter", "")))
		holder.set_meta(&"coc_path", path)
		holder.set_meta(&"coc_cell", cell)
		holder.set_meta(&"coc_z", int(entry.get("z", 0)))
		holder.set_meta(&"coc_image1", image1)
		holder.position = IsometricGrid.grid_to_world(cell)
		add_child(holder)

		var hotspot: Vector2 = draw_info.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
		var render_offset := Vector2.ZERO
		var ro_raw: Variant = draw_info.get("render_offset", Vector2.ZERO)
		if ro_raw is Vector2:
			render_offset = ro_raw
		elif ro_raw is Array and (ro_raw as Array).size() >= 2:
			render_offset = Vector2(float(ro_raw[0]), float(ro_raw[1]))
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = texture
		sprite.scale = Vector2(scale, scale)
		sprite.position = (hotspot + render_offset) * scale
		var depth_off := int(draw_info.get("depth_offset", 0))
		if depth_off != 0:
			sprite.z_index = depth_off
		holder.add_child(sprite)


func _native_map_object_position(type_id: String, center: Vector2, size: Vector2) -> Vector2:
	if type_id == MapObjectRegistry.TYPE_WALL_STRAIGHT:
		return Vector2(center.x, center.y + TileSizeConfig.wall_anchor_y(size.y))
	return center + TileSizeConfig.map_object_offset()


func _get_object_texture(sprite_path: String) -> Texture2D:
	if sprite_path.is_empty():
		return null
	if sprite_path == MapObjectRegistry.SPRITE_WALL_STRAIGHT:
		return _TEXTURE_WALL_STRAIGHT
	if _object_textures.has(sprite_path):
		return _object_textures[sprite_path] as Texture2D
	if not CocTileCatalog.exists(sprite_path) and not ResourceLoader.exists(sprite_path):
		return null
	var texture: Texture2D = load(sprite_path) as Texture2D
	if texture != null:
		_object_textures[sprite_path] = texture
	return texture
