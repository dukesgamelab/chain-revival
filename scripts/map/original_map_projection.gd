class_name OriginalMapProjection
extends RefCounted
## Recovered CoC tile pitch 62×32. Scale whole map by TILE_WIDTH / 62.

const SOURCE_PITCH_WIDTH := 62.0
const SOURCE_STEP_X := 31.0
const SOURCE_STEP_Y := 16.0


static func map_scale() -> float:
	return float(TileSizeConfig.TILE_WIDTH) / SOURCE_PITCH_WIDTH


static func source_cell_point(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x - cell.y) * SOURCE_STEP_X,
		float(cell.x + cell.y) * SOURCE_STEP_Y,
	)


static func cell_to_world(cell: Vector2i) -> Vector2:
	return point_to_world(Vector2(cell))


static func point_to_world(point: Vector2) -> Vector2:
	return Vector2(
		(point.x - point.y) * SOURCE_STEP_X,
		(point.x + point.y) * SOURCE_STEP_Y,
	) * map_scale()


static func world_to_point(world: Vector2) -> Vector2:
	var s := map_scale()
	if s <= 0.0:
		return Vector2.ZERO
	var sx := world.x / (SOURCE_STEP_X * s)
	var sy := world.y / (SOURCE_STEP_Y * s)
	return Vector2((sx + sy) * 0.5, (sy - sx) * 0.5)


static func world_to_cell(world: Vector2) -> Vector2i:
	var point := world_to_point(world)
	return Vector2i(int(floor(point.x)), int(floor(point.y)))


static func sprite_top_left(cell: Vector2i, hotspot: Vector2) -> Vector2:
	return (source_cell_point(cell) + hotspot) * map_scale()
