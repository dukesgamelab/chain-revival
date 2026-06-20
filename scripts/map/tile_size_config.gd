class_name TileSizeConfig
extends RefCounted
## Central isometric tile footprint (80×40) and presentation tuning.

## Full width of one tile diamond (left point to right point).
const TILE_WIDTH := 80

## Full height of one tile diamond (top point to bottom point).
const TILE_HEIGHT := 40

## Presentation scale multipliers — adjust sprites without changing tile math.
const SOLDIER_SCALE := 1.0
const TREE_SCALE := 1.0
const HAYBAIL_SCALE := 1.0
const WALL_SCALE := 1.0
const GRASS_TILE_OVERLAP_SCALE := 1.04

## Soldier click-pick radius in world pixels.
const SOLDIER_PICK_RADIUS := TILE_WIDTH * 44.0 / 64.0

## Camera snap offset above a cell center when focusing on a grid cell.
const CAMERA_SNAP_VERTICAL_OFFSET := -TILE_HEIGHT * 90.0 / 32.0


static func half_width() -> float:
	return TILE_WIDTH * 0.5


static func half_height() -> float:
	return TILE_HEIGHT * 0.5


## Chest/aim height above tile center for tracers, LOS, and picking.
static func tracer_aim_offset() -> Vector2:
	return Vector2(0.0, -TILE_HEIGHT * 0.5)


static func soldier_standing_sprite_offset() -> Vector2:
	return Vector2(0.0, -TILE_HEIGHT * 0.75)


static func soldier_prone_sprite_offset() -> Vector2:
	return Vector2(0.0, -TILE_HEIGHT * 0.3125)


static func map_object_offset() -> Vector2:
	return Vector2(0.0, -TILE_HEIGHT * 0.25)


static func wall_anchor_y(texture_height: float) -> float:
	return -texture_height * 0.5 + TILE_HEIGHT * 0.45


static func facing_arrow_y() -> float:
	return -TILE_HEIGHT * 0.9375


static func prone_marker_y() -> float:
	return -TILE_HEIGHT * 0.1875


static func dead_marker_y() -> float:
	return -TILE_HEIGHT * 0.875


static func object_scale_for_type(type_id: String) -> float:
	match type_id:
		MapObjectRegistry.TYPE_TREE:
			return TREE_SCALE
		MapObjectRegistry.TYPE_HAYBAIL:
			return HAYBAIL_SCALE
		MapObjectRegistry.TYPE_WALL_STRAIGHT:
			return WALL_SCALE
		_:
			return 1.0
