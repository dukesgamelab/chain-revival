class_name ConeOfFire
extends RefCounted
## Forward cone used for target acquisition and aim preview (wider and longer than a single grid line).

## Full width in tiles at maximum cone range.
const WIDTH_AT_MAX_RANGE := 30

## Extra tiles beyond weapon range for cone reach and preview.
const RANGE_BONUS := 8


static func effective_range(weapon_range: int) -> int:
	return weapon_range + RANGE_BONUS


static func is_cell_in_cone(
	from_cell: Vector2i,
	facing: Vector2i,
	target_cell: Vector2i,
	max_range: int,
) -> bool:
	var forward := _forward_tiles(from_cell, facing, target_cell)
	if forward <= 0 or forward > max_range:
		return false
	var lateral := _lateral_tiles(from_cell, facing, target_cell)
	var half_width := (float(forward) / float(max_range)) * (WIDTH_AT_MAX_RANGE * 0.5)
	return float(lateral) <= half_width + 0.001


## Spotting uses a broad forward arc (no lateral squeeze) — facing the fight, not a fire cone.
static func is_in_spotting_forward_arc(
	from_cell: Vector2i,
	facing: Vector2i,
	target_cell: Vector2i,
	max_range: int,
) -> bool:
	var forward := _forward_tiles(from_cell, facing, target_cell)
	return forward > 0 and forward <= max_range


static func is_facing_toward_target(
	from_cell: Vector2i,
	facing: Vector2i,
	target_cell: Vector2i,
	max_range: int,
) -> bool:
	if FacingDirection.toward_cell(from_cell, target_cell) == FacingDirection.normalize(facing):
		return true
	return is_in_spotting_forward_arc(from_cell, facing, target_cell, max_range)


## Grid-facing cone (combat acquisition).
static func cone_outline_world(from_cell: Vector2i, facing: Vector2i, max_range: int) -> PackedVector2Array:
	var normalized := FacingDirection.normalize(facing)
	var lateral := Vector2i(-normalized.y, normalized.x)
	var half_width := WIDTH_AT_MAX_RANGE >> 1
	var far_center := from_cell + normalized * max_range
	var far_left := far_center + lateral * half_width
	var far_right := far_center - lateral * half_width
	var origin := IsometricGrid.grid_to_world(from_cell)
	return PackedVector2Array([
		origin,
		IsometricGrid.grid_to_world(far_left),
		IsometricGrid.grid_to_world(far_center),
		IsometricGrid.grid_to_world(far_right),
		origin,
	])


## Mouse-aimed cone wedge in world space (Fire At preview).
static func cone_outline_world_toward(
	from_world: Vector2,
	aim_world: Vector2,
	from_cell: Vector2i,
	max_range_tiles: int,
) -> PackedVector2Array:
	var aim_dir := _aim_direction(from_world, aim_world, from_cell)
	var max_reach := _world_reach(from_cell, aim_world, from_world, max_range_tiles)
	var to_aim := aim_world - from_world
	var reach_dist := max_reach
	if to_aim.length_squared() >= 4.0:
		reach_dist = minf(to_aim.length(), max_reach)

	var far_center := from_world + aim_dir * reach_dist
	var lateral_dir := Vector2(-aim_dir.y, aim_dir.x)
	var half_width_at_max := _world_half_width(from_cell, aim_world, max_range_tiles)
	var width_scale := reach_dist / max_reach if max_reach > 0.001 else 1.0
	var half_width := half_width_at_max * width_scale

	return PackedVector2Array([
		from_world,
		far_center + lateral_dir * half_width,
		far_center,
		far_center - lateral_dir * half_width,
		from_world,
	])


static func is_world_point_in_aim_cone(
	from_world: Vector2,
	aim_world: Vector2,
	point_world: Vector2,
	from_cell: Vector2i,
	max_range_tiles: int,
) -> bool:
	var aim_dir := _aim_direction(from_world, aim_world, from_cell)
	var to_point := point_world - from_world
	var max_reach := _world_reach(from_cell, aim_world, from_world, max_range_tiles)
	var forward := to_point.dot(aim_dir)
	if forward <= 0.0 or forward > max_reach + 8.0:
		return false
	var lateral := absf(to_point.dot(Vector2(-aim_dir.y, aim_dir.x)))
	var half_width_at_max := _world_half_width(from_cell, aim_world, max_range_tiles)
	var width_at_forward := half_width_at_max * (forward / max_reach)
	return lateral <= width_at_forward + 4.0


static func _aim_direction(from_world: Vector2, aim_world: Vector2, from_cell: Vector2i) -> Vector2:
	var to_aim := aim_world - from_world
	if to_aim.length_squared() >= 4.0:
		return to_aim.normalized()
	var aim_cell := IsometricGrid.world_to_cell_at_point(aim_world)
	var facing := FacingDirection.toward_cell(from_cell, aim_cell)
	var screen_dir := IsometricGrid.grid_facing_to_screen(facing, from_cell)
	if screen_dir.length_squared() < 0.001:
		return Vector2(1.0, 0.0)
	return screen_dir.normalized()


static func _world_reach(
	from_cell: Vector2i,
	aim_world: Vector2,
	from_world: Vector2,
	max_range_tiles: int,
) -> float:
	var aim_cell := IsometricGrid.world_to_cell_at_point(aim_world)
	var facing := FacingDirection.toward_cell(from_cell, aim_cell)
	var far_cell := from_cell + facing * max_range_tiles
	return from_world.distance_to(IsometricGrid.grid_to_world(far_cell))


static func _world_half_width(from_cell: Vector2i, aim_world: Vector2, max_range_tiles: int) -> float:
	var aim_cell := IsometricGrid.world_to_cell_at_point(aim_world)
	var facing := FacingDirection.toward_cell(from_cell, aim_cell)
	var lateral := Vector2i(-facing.y, facing.x)
	var half_tiles := WIDTH_AT_MAX_RANGE >> 1
	var far_center := IsometricGrid.grid_to_world(from_cell + facing * max_range_tiles)
	var far_left := IsometricGrid.grid_to_world(
		from_cell + facing * max_range_tiles + lateral * half_tiles,
	)
	return far_center.distance_to(far_left)


static func _forward_tiles(from_cell: Vector2i, facing: Vector2i, target_cell: Vector2i) -> int:
	var normalized := FacingDirection.normalize(facing)
	if normalized == FacingDirection.NORTH:
		return maxi(0, from_cell.y - target_cell.y)
	if normalized == FacingDirection.SOUTH:
		return maxi(0, target_cell.y - from_cell.y)
	if normalized == FacingDirection.EAST:
		return maxi(0, target_cell.x - from_cell.x)
	if normalized == FacingDirection.WEST:
		return maxi(0, from_cell.x - target_cell.x)
	return 0


static func _lateral_tiles(from_cell: Vector2i, facing: Vector2i, target_cell: Vector2i) -> int:
	var normalized := FacingDirection.normalize(facing)
	if normalized == FacingDirection.NORTH or normalized == FacingDirection.SOUTH:
		return absi(target_cell.x - from_cell.x)
	return absi(target_cell.y - from_cell.y)
