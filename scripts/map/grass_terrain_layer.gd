class_name GrassTerrainLayer
extends Node2D
## Presentation-only grass texture fill for every playable map cell (toggle with B in dev).

const GRASS_VARIANT_PATHS: Array[String] = [
	"res://assets/sprites/grass_base_tile.png",
	"res://assets/sprites/grass_1.png",
	"res://assets/sprites/grass_2.png",
	"res://assets/sprites/grass_3.png",
]
const TILE_OVERLAP_SCALE := TileSizeConfig.GRASS_TILE_OVERLAP_SCALE
const TINT_SPREAD := 0.07

var map_data: MapData = null
var _layer_visible: bool = true
var _grass_textures: Array[Texture2D] = []


func _ready() -> void:
	_load_grass_textures()
	queue_redraw()


func apply_map_data(data: MapData) -> void:
	map_data = data
	queue_redraw()


func set_layer_visible(show_layer: bool) -> void:
	_layer_visible = show_layer
	visible = show_layer
	queue_redraw()


func is_layer_visible() -> bool:
	return _layer_visible


func refresh_view_rotation() -> void:
	queue_redraw()


func _load_grass_textures() -> void:
	_grass_textures.clear()
	for path in GRASS_VARIANT_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = load(path)
		if texture != null:
			_grass_textures.append(texture)


func _draw() -> void:
	if not _layer_visible or map_data == null or _grass_textures.is_empty():
		return
	## Original maps use OriginalGroundLayer (recovered GRS tiles).
	if map_data.is_original_visual_map():
		return

	for y in range(map_data.height):
		for x in range(map_data.width):
			_draw_grass_at_cell(Vector2i(x, y))

	var border := IsometricGrid.MAP_VISUAL_BORDER
	for ring in range(1, border + 1):
		var x_min := -ring
		var x_max := map_data.width - 1 + ring
		var y_min := -ring
		var y_max := map_data.height - 1 + ring
		for x in range(x_min, x_max + 1):
			_draw_grass_at_cell(Vector2i(x, y_min))
			if y_max != y_min:
				_draw_grass_at_cell(Vector2i(x, y_max))
		for y in range(y_min + 1, y_max):
			_draw_grass_at_cell(Vector2i(x_min, y))
			if x_max != x_min:
				_draw_grass_at_cell(Vector2i(x_max, y))


func _draw_grass_at_cell(cell: Vector2i) -> void:
	var style := _grass_style_for_cell(cell)
	var texture := _grass_textures[style.variant_index]
	var half := texture.get_size() * 0.5
	var center := IsometricGrid.grid_to_world(cell)

	var scale := Vector2(TILE_OVERLAP_SCALE, TILE_OVERLAP_SCALE)
	if style.flip_h:
		scale.x *= -1.0
	if style.flip_v:
		scale.y *= -1.0

	draw_set_transform(center, style.rotation, scale)
	draw_texture(texture, -half, style.tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _grass_style_for_cell(cell: Vector2i) -> Dictionary:
	var hash := _stable_hash(cell)
	var variant_index := _stable_hash(Vector2i(cell.x + 9001, cell.y + 4271)) % _grass_textures.size()
	# Isometric diamonds: mirror flips and 180° rotation only (no 90°/270°).
	var flip_h := (hash & 1) != 0
	var flip_v := (hash & 2) != 0
	var rotation := PI if (hash & 4) != 0 else 0.0
	var tint := Color(
		0.93 + _hash_unit(hash, 11) * TINT_SPREAD,
		0.88 + _hash_unit(hash, 23) * TINT_SPREAD,
		0.82 + _hash_unit(hash, 37) * TINT_SPREAD,
		1.0,
	)
	return {
		"variant_index": variant_index,
		"flip_h": flip_h,
		"flip_v": flip_v,
		"rotation": rotation,
		"tint": tint,
	}


static func _stable_hash(cell: Vector2i) -> int:
	var n := cell.x * 374761393 ^ cell.y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return absi(n)


static func _hash_unit(hash: int, salt: int) -> float:
	var mixed := hash ^ salt * 2654435761
	mixed = (mixed ^ (mixed >> 15)) * 2246822519
	return float(mixed & 0xFFFF) / 65535.0
