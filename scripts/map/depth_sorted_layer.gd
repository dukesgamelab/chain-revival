class_name DepthSortedLayer
extends Node2D
## Presentation layer: static map objects (built once) + soldiers as Y-sorted siblings.
## Original CoC objects always resolve facets via CocSpriteResolver (shared with editor).
##
## Walls/trees are never rebuilt or re-sorted during movement. Godot's C++ y-sort on this
## node orders statics and movers together by world Y — no GDScript sort_custom per tick.
##
## Y-sort origin for every map object is the tile ground-contact point (cell world pos).
## Sprite hotspots/offsets only shift pixels; they must not move the holder used for sorting.
## Keep sibling z_index at 0 so Y-sort is not overridden.

const META_MAP_OBJECT := &"map_object_sprite"

const _TEXTURE_WALL_STRAIGHT := preload("res://assets/sprites/wall-straight-1-tile.png")

var map_data: MapData = null

var _object_textures: Dictionary = {}
var _placeholder_count: int = 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## Engine Y-sort: static map objects + soldiers must be direct children.
	y_sort_enabled = true


## Parent for soldier views — same node so y-sort interleaves with map objects.
func get_movers_root() -> Node2D:
	return self


func apply_map_data(data: MapData) -> void:
	map_data = data
	_rebuild_map_object_sprites()


func refresh_view_rotation() -> void:
	if map_data != null:
		_rebuild_map_object_sprites()


func _rebuild_map_object_sprites() -> void:
	## Free immediately — queue_free leaves stale camera facets visible until idle frame.
	## Only clears map objects; soldier children are left alone.
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

		## Holder at ground contact — Y-sort key. Sprite is offset above it.
		var holder := Node2D.new()
		holder.set_meta(META_MAP_OBJECT, true)
		holder.z_index = 0
		holder.position = IsometricGrid.grid_to_world(cell)
		add_child(holder)

		var sprite := Sprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = texture
		var scale_factor := TileSizeConfig.object_scale_for_type(type_id)
		sprite.scale = Vector2(scale_factor, scale_factor)
		var size := texture.get_size() * scale_factor
		sprite.position = _native_sprite_offset(type_id, size)
		holder.add_child(sprite)


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
	## One-time draw order at map apply / camera rotate — never during movement.
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
		holder.z_index = 0
		## Ground-contact sort point = cell world pos (+ authored depth_offset).
		var ground := IsometricGrid.grid_to_world(cell)
		var present := _presentation_offsets(family, draw_info)
		ground.y += float(present.get("depth_offset", 0.0)) * scale
		holder.position = ground
		add_child(holder)

		var hotspot: Vector2 = present.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
		var render_offset: Vector2 = present.get("render_offset", Vector2.ZERO)
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = texture
		sprite.scale = Vector2(scale, scale)
		sprite.position = hotspot * scale + render_offset * scale
		holder.add_child(sprite)


## Hotspot places sprite pixels relative to the holder's ground-contact origin.
## Prefer offsets already resolved into draw_info (shared CocSpriteResolver path).
func _presentation_offsets(family: String, draw_info: Dictionary) -> Dictionary:
	var hotspot: Vector2 = draw_info.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
	var render_offset: Vector2 = draw_info.get("render_offset", Vector2.ZERO)
	var depth_offset := float(draw_info.get("depth_offset", 0.0))
	## Legacy fallback if an older resolve omitted presentation fields.
	if not draw_info.has("render_offset") or not draw_info.has("depth_offset"):
		var variant := MapAssetRegistry.camera_variant(family, CocFacetSelector.camera_degrees())
		if not variant.is_empty():
			var hs_raw: Variant = variant.get("hotspot", null)
			if hs_raw is Array and (hs_raw as Array).size() >= 2 and not draw_info.has("hotspot"):
				hotspot = Vector2(float(hs_raw[0]), float(hs_raw[1]))
			if not draw_info.has("render_offset"):
				var ro_raw: Variant = variant.get("render_offset", null)
				if ro_raw is Array and (ro_raw as Array).size() >= 2:
					render_offset = Vector2(float(ro_raw[0]), float(ro_raw[1]))
			if not draw_info.has("depth_offset"):
				depth_offset = float(variant.get("depth_offset", 0.0))
	return {
		"hotspot": hotspot,
		"render_offset": render_offset,
		"depth_offset": depth_offset,
	}


func _native_sprite_offset(type_id: String, size: Vector2) -> Vector2:
	if type_id == MapObjectRegistry.TYPE_WALL_STRAIGHT:
		## Keep holder at ground; raise the centered sprite so feet meet the tile.
		return Vector2(0.0, TileSizeConfig.wall_anchor_y(size.y))
	return TileSizeConfig.map_object_offset()


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
