class_name CoverSystem
extends RefCounted
## V1 cover: adjacent cover objects that lie roughly between shooter and target.

const MapDataClass := preload("res://scripts/map_data.gd")
const MapObjectRegistryClass := preload("res://scripts/map_object_registry.gd")

const ADJACENT_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1),
]


## Highest cover_value from qualifying adjacent tiles (0.0 = no cover).
static func get_cover_value(
	from_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapDataClass,
) -> float:
	if map_data == null or from_cell == target_cell:
		return 0.0

	var best_cover := 0.0
	for offset in ADJACENT_OFFSETS:
		var cover_cell := target_cell + offset
		if not map_data.is_in_bounds(cover_cell):
			continue
		var cover_type: String = map_data.get_object_type(cover_cell)
		if cover_type.is_empty():
			continue
		var cover_def := MapObjectRegistryClass.get_def(cover_type)
		if cover_def == null or not cover_def.provides_cover:
			continue
		if not _is_cover_between(from_cell, cover_cell, target_cell):
			continue
		best_cover = maxf(best_cover, cover_def.cover_value)

	return best_cover


## Type id of the cover object contributing the most cover (empty if none).
static func get_cover_type(
	from_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapDataClass,
) -> String:
	if map_data == null or from_cell == target_cell:
		return ""

	var best_cover := 0.0
	var best_type := ""
	for offset in ADJACENT_OFFSETS:
		var cover_cell := target_cell + offset
		if not map_data.is_in_bounds(cover_cell):
			continue
		var cover_type: String = map_data.get_object_type(cover_cell)
		if cover_type.is_empty():
			continue
		var cover_def := MapObjectRegistryClass.get_def(cover_type)
		if cover_def == null or not cover_def.provides_cover:
			continue
		if not _is_cover_between(from_cell, cover_cell, target_cell):
			continue
		if cover_def.cover_value >= best_cover:
			best_cover = cover_def.cover_value
			best_type = cover_type

	return best_type


## Cover tile is adjacent to target, closer than target, and in the shooter's direction.
static func _is_cover_between(
	from_cell: Vector2i,
	cover_cell: Vector2i,
	target_cell: Vector2i,
) -> bool:
	if cover_cell == from_cell:
		return false

	var to_target := target_cell - from_cell
	var to_cover := cover_cell - from_cell
	if to_target == Vector2i.ZERO or to_cover == Vector2i.ZERO:
		return false

	var shooter_to_target := _manhattan(from_cell, target_cell)
	var shooter_to_cover := _manhattan(from_cell, cover_cell)
	if shooter_to_cover >= shooter_to_target:
		return false

	# Same general direction (rough alignment — no directional cover yet).
	var alignment := to_target.x * to_cover.x + to_target.y * to_cover.y
	return alignment > 0


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
