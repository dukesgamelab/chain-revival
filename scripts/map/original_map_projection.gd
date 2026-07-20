class_name OriginalMapProjection
extends RefCounted
## Recovered CoC tile pitch 62×32. Scale whole map by TILE_WIDTH / 62.
## Handedness (X-flip) lives in MapCoordinateTransform — not here.

const SOURCE_PITCH_WIDTH := 62.0
const SOURCE_STEP_X := 31.0
const SOURCE_STEP_Y := 16.0


static func map_scale() -> float:
	return float(TileSizeConfig.TILE_WIDTH) / SOURCE_PITCH_WIDTH


static func source_cell_point(cell: Vector2i) -> Vector2:
	## Unscaled source pitch — routes through MapCoordinateTransform for candidates.
	return MapCoordinateTransform.project_visual_point(Vector2(cell))


static func cell_to_world(cell: Vector2i) -> Vector2:
	return point_to_world(Vector2(cell))


static func point_to_world(point: Vector2) -> Vector2:
	return MapCoordinateTransform.project_visual_point_scaled(point)


static func world_to_point(world: Vector2) -> Vector2:
	return MapCoordinateTransform.unproject_to_visual_point(world)


static func world_to_cell(world: Vector2) -> Vector2i:
	var point := world_to_point(world)
	return Vector2i(int(floor(point.x)), int(floor(point.y)))


static func sprite_top_left(cell: Vector2i, hotspot: Vector2) -> Vector2:
	return (source_cell_point(cell) + hotspot) * map_scale()
