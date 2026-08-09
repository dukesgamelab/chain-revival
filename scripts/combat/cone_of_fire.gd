class_name ConeOfFire
extends RefCounted
## Forward cone used for target acquisition and aim preview (wider and longer than a single grid line).
## Numeric tuning lives in GameplayPolicies.vision.
##
## Geometry is a constant half-angle (not a fixed width-at-max that shrinks too hard near the
## shooter). Half-angle must exceed 22.5° so every cell in an 8-way facing sector is covered.

const VisionPolicyClass := preload("res://scripts/gameplay_policies/vision_policy.gd")

## Frozen aliases of defaults for call sites that still reference ConeOfFire consts.
const WIDTH_AT_MAX_RANGE := VisionPolicyClass.DEFAULT_CONE_WIDTH_AT_MAX_RANGE
const RANGE_BONUS := VisionPolicyClass.DEFAULT_CONE_RANGE_BONUS


static func effective_range(weapon_range: int) -> int:
	return GameplayPolicies.vision.effective_cone_range(weapon_range)


static func is_cell_in_cone(
	from_cell: Vector2i,
	facing: Vector2i,
	target_cell: Vector2i,
	max_range: int,
) -> bool:
	var forward := _forward_tiles(from_cell, facing, target_cell)
	if forward <= 0.0 or forward > float(max_range) + 0.001:
		return false
	var lateral := _lateral_tiles(from_cell, facing, target_cell)
	var half_width := GameplayPolicies.vision.cone_half_width_at_forward(forward, max_range)
	return lateral <= half_width + 0.001


## Spotting uses a broad forward arc (no lateral squeeze) — facing the fight, not a fire cone.
static func is_in_spotting_forward_arc(
	from_cell: Vector2i,
	facing: Vector2i,
	target_cell: Vector2i,
	max_range: int,
) -> bool:
	var forward := _forward_tiles(from_cell, facing, target_cell)
	return forward > 0.0 and forward <= float(max_range) + 0.001


static func is_facing_toward_target(
	from_cell: Vector2i,
	facing: Vector2i,
	target_cell: Vector2i,
	max_range: int,
) -> bool:
	if FacingDirection.toward_cell(from_cell, target_cell) == FacingDirection.normalize(facing):
		return true
	return is_in_spotting_forward_arc(from_cell, facing, target_cell, max_range)


## Grid-facing cone (combat acquisition). Works for all eight facings.
static func cone_outline_world(from_cell: Vector2i, facing: Vector2i, max_range: int) -> PackedVector2Array:
	var normalized := FacingDirection.normalize(facing)
	var lateral := Vector2i(-normalized.y, normalized.x)
	var half_tiles := maxi(ceili(GameplayPolicies.vision.cone_half_width_at_forward(
		float(maxi(max_range, 1)), max_range
	)), 1)
	var far_center := from_cell + normalized * max_range
	var far_left := far_center + lateral * half_tiles
	var far_right := far_center - lateral * half_tiles
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
	if to_aim.length_squared() >= GameplayPolicies.vision.aim_dir_min_length_sq:
		reach_dist = minf(to_aim.length(), max_reach)

	var far_center := from_world + aim_dir * reach_dist
	var lateral_dir := Vector2(-aim_dir.y, aim_dir.x)
	var half_width_at_max := _world_half_width(from_cell, aim_world, max_range_tiles)
	var width_scale := reach_dist / max_reach if max_reach > 0.001 else 1.0
	## Match grid cone: never narrower than the min half-width floor (in world units).
	var min_world := _world_min_half_width(from_cell, aim_world, max_range_tiles)
	var half_width := maxf(min_world, half_width_at_max * width_scale)

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
	if forward <= 0.0 or forward > max_reach + GameplayPolicies.vision.world_aim_forward_slack:
		return false
	var lateral := absf(to_point.dot(Vector2(-aim_dir.y, aim_dir.x)))
	var half_width_at_max := _world_half_width(from_cell, aim_world, max_range_tiles)
	var min_world := _world_min_half_width(from_cell, aim_world, max_range_tiles)
	var width_at_forward := maxf(min_world, half_width_at_max * (forward / max_reach))
	return lateral <= width_at_forward + GameplayPolicies.vision.world_aim_lateral_slack


static func _aim_direction(from_world: Vector2, aim_world: Vector2, from_cell: Vector2i) -> Vector2:
	var to_aim := aim_world - from_world
	if to_aim.length_squared() >= GameplayPolicies.vision.aim_dir_min_length_sq:
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
	var half_tiles := maxi(ceili(GameplayPolicies.vision.cone_half_width_at_forward(
		float(maxi(max_range_tiles, 1)), max_range_tiles
	)), 1)
	var far_center := IsometricGrid.grid_to_world(from_cell + facing * max_range_tiles)
	var far_left := IsometricGrid.grid_to_world(
		from_cell + facing * max_range_tiles + lateral * half_tiles,
	)
	return far_center.distance_to(far_left)


static func _world_min_half_width(from_cell: Vector2i, aim_world: Vector2, max_range_tiles: int) -> float:
	## Convert the tile min half-width into world units at max range (same scale as half_width).
	var half_at_max := _world_half_width(from_cell, aim_world, max_range_tiles)
	var tile_half_at_max := GameplayPolicies.vision.cone_half_width_at_forward(
		float(maxi(max_range_tiles, 1)), max_range_tiles
	)
	if tile_half_at_max <= 0.001:
		return 0.0
	var min_tiles := GameplayPolicies.vision.cone_min_half_width_tiles
	return half_at_max * (min_tiles / tile_half_at_max)


static func _forward_tiles(from_cell: Vector2i, facing: Vector2i, target_cell: Vector2i) -> float:
	## Steps along facing. Divide by |facing|^2 so diagonal unit steps count as 1
	## (same effective range as cardinals; avoids √2 stretch from (1,1)).
	var normalized := FacingDirection.normalize(facing)
	if normalized == Vector2i.ZERO:
		return 0.0
	var offset := Vector2(target_cell - from_cell)
	var forward_v := Vector2(normalized)
	var denom := forward_v.length_squared()
	if denom < 0.0001:
		return 0.0
	return offset.dot(forward_v) / denom


static func _lateral_tiles(from_cell: Vector2i, facing: Vector2i, target_cell: Vector2i) -> float:
	var normalized := FacingDirection.normalize(facing)
	if normalized == Vector2i.ZERO:
		return 0.0
	var offset := Vector2(target_cell - from_cell)
	var lateral_v := Vector2(-normalized.y, normalized.x)
	var denom := lateral_v.length_squared()
	if denom < 0.0001:
		return 0.0
	return absf(offset.dot(lateral_v) / denom)
