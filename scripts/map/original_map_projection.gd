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
	return source_cell_point(cell) * map_scale()


static func world_to_cell(world: Vector2) -> Vector2i:
	var s := map_scale()
	if s <= 0.0:
		return Vector2i.ZERO
	var sx := world.x / (SOURCE_STEP_X * s)
	var sy := world.y / (SOURCE_STEP_Y * s)
	var gx := (sx + sy) * 0.5
	var gy := (sy - sx) * 0.5
	return Vector2i(int(floor(gx)), int(floor(gy)))


static func sprite_top_left(cell: Vector2i, hotspot: Vector2) -> Vector2:
	return (source_cell_point(cell) + hotspot) * map_scale()
