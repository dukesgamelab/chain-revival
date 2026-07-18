class_name OriginalUnderlayLayer
extends Node2D
## Image1 under-images + documented half-diamond adjacency underlay for wall cells.

var map_data: MapData = null
var _textures: Dictionary = {}
var _half_cache: Dictionary = {}
var _floor_set: Dictionary = {}
var _tan_stone: Texture2D = null
var _tan_wood: Texture2D = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func apply_map_data(data: MapData) -> void:
	map_data = data
	_rebuild_floor_set()
	_ensure_tan_bases()
	queue_redraw()


func refresh_view_rotation() -> void:
	queue_redraw()


func _rebuild_floor_set() -> void:
	_floor_set.clear()
	if map_data == null:
		return
	for entry in map_data.floors:
		var fam := str(entry.get("image", "")).to_upper()
		if not CocRenderRules.is_floor_family(fam):
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		_floor_set[cell] = fam


func _ensure_tan_bases() -> void:
	var stone := CocRenderRules.resolve_floor_display("SFLO")
	var wood := CocRenderRules.resolve_floor_display("WFLO")
	_tan_stone = _get_texture(str(stone.get("path", "")))
	_tan_wood = _get_texture(str(wood.get("path", "")))


func _draw() -> void:
	if map_data == null or not map_data.is_original_visual_map():
		return
	var scale := OriginalMapProjection.map_scale()
	## 1) Explicit Image1 under-images (original engine property).
	for entry in map_data.visual_placements:
		var image1 := str(entry.get("image1", "")).to_upper()
		if image1.is_empty():
			var source: Dictionary = entry.get("source", {}) if entry.get("source", {}) is Dictionary else {}
			image1 = str(source.get("image1", source.get("Image1", ""))).to_upper()
		if image1.is_empty() or not CocRenderRules.is_floor_family(image1):
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		_draw_floor_sprite(cell, image1, scale)

	## 2) Half-diamond adjacency underlay for wallish cells without Image1.
	for entry in map_data.visual_placements:
		var family := str(entry.get("family", "")).to_upper()
		if family.is_empty():
			var source: Dictionary = entry.get("source", {}) if entry.get("source", {}) is Dictionary else {}
			family = str(source.get("image", "")).to_upper()
		if not CocRenderRules.is_wallish_family(family):
			continue
		var image1 := str(entry.get("image1", "")).to_upper()
		if image1.is_empty():
			var src2: Dictionary = entry.get("source", {}) if entry.get("source", {}) is Dictionary else {}
			image1 = str(src2.get("image1", "")).to_upper()
		if not image1.is_empty():
			continue
		var cell := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		_draw_half_diamond(cell, scale)


func _draw_floor_sprite(cell: Vector2i, family: String, scale: float) -> void:
	if map_data == null or not map_data.is_in_bounds(cell):
		return
	var info := CocRenderRules.resolve_floor_display(family)
	if CocRenderRules.is_unusable_sprite(info):
		return
	var texture := _get_texture(str(info.get("path", "")))
	if texture == null:
		return
	var hotspot: Vector2 = info.get("hotspot", CocTileCatalog.DEFAULT_HOTSPOT)
	var visual := IsometricGrid.logical_to_visual_cell(cell)
	var top_left := OriginalMapProjection.sprite_top_left(visual, hotspot)
	draw_texture_rect(texture, Rect2(top_left, texture.get_size() * scale), false)


func _draw_half_diamond(cell: Vector2i, scale: float) -> void:
	var nbrs: Array[Vector2i] = []
	var wood := false
	var wood_set := false
	for nb in CocRenderRules.NEIGHBOR_DIRS:
		var p: Vector2i = cell + nb
		if not _floor_set.has(p):
			continue
		nbrs.append(nb)
		if not wood_set:
			wood = str(_floor_set[p]) == "WFLO"
			wood_set = true
	if nbrs.is_empty():
		return
	var texture := _half_texture(wood, nbrs)
	if texture == null:
		return
	var hotspot := CocTileCatalog.DEFAULT_HOTSPOT
	var visual := IsometricGrid.logical_to_visual_cell(cell)
	var top_left := OriginalMapProjection.sprite_top_left(visual, hotspot)
	draw_texture_rect(texture, Rect2(top_left, texture.get_size() * scale), false)


func _half_texture(wood: bool, nbrs: Array[Vector2i]) -> Texture2D:
	var mask_bits := 0
	for i in range(CocRenderRules.NEIGHBOR_DIRS.size()):
		if nbrs.has(CocRenderRules.NEIGHBOR_DIRS[i]):
			mask_bits |= 1 << i
	var key := "%s|%d" % ["W" if wood else "S", mask_bits]
	if _half_cache.has(key):
		return _half_cache[key] as Texture2D
	var base := _tan_wood if wood else _tan_stone
	if base == null:
		return null
	var img := base.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var keep := false
			for i in range(CocRenderRules.NEIGHBOR_DIRS.size()):
				if (mask_bits & (1 << i)) == 0:
					continue
				var d: Vector2 = CocRenderRules.NEIGHBOR_SCREEN[i]
				if (float(x) - 52.0) * d.x + (float(y) - 74.0) * d.y > 0.0:
					keep = true
					break
			if not keep:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_half_cache[key] = tex
	return tex


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
