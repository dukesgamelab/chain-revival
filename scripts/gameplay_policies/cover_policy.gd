class_name CoverPolicy
extends RefCounted
## Cover hit / visibility modifiers + directional geometric cover check.
## Geometry matches the original's shooter-facing scan around the target.
## Gameplay asks: "Is the target in cover from this shot direction?"

## TUNED magnitude — keep existing feel; this policy changes *when* cover applies.
const DEFAULT_MODERATE_HIT_MULT := 0.5
const DEFAULT_MODERATE_VISIBILITY_MULT := 0.65

## RECOVERED from Initial-*.oin (values confirmed; combination arithmetic unresolved).
const INIT_COVER_IN_MULTIPLIER := 1.0
const INIT_COVER_HIT_MULTIPLIER := 0.005 ## how this combines into hit chance is UNRESOLVED
const INIT_COVER_RANGE_LIMIT := 3 ## Chebyshev scan radius around target (leaning; OG used OffsetX/Y box)
const INIT_MIN_DUCKING_RANGE := 4
const INIT_KILLED_PROBABILITY := 20

## UNRESOLVED: whether multiple qualifying tiles stack. Default FIRST = boolean / first hit
## (weakly supported by original int flag datatypes).
enum StackMode { FIRST, COUNT }

enum Qualifier { NONE, CORNER } ## CORNER models PseudoCover / CoverCorner — not a weaker tier

var moderate_hit_mult: float = DEFAULT_MODERATE_HIT_MULT
var moderate_visibility_mult: float = DEFAULT_MODERATE_VISIBILITY_MULT
var cover_range_limit: int = INIT_COVER_RANGE_LIMIT
var stack_mode: int = StackMode.FIRST


class CoverCheckResult extends RefCounted:
	var in_cover: bool = false
	var qualifier: int = Qualifier.NONE
	var source_cell: Vector2i = Vector2i(-999, -999)
	## All tiles that passed the geometric test (debug overlay / COUNT mode).
	var qualifying_cells: Array[Vector2i] = []


func reset_to_defaults() -> void:
	moderate_hit_mult = DEFAULT_MODERATE_HIT_MULT
	moderate_visibility_mult = DEFAULT_MODERATE_VISIBILITY_MULT
	cover_range_limit = INIT_COVER_RANGE_LIMIT
	stack_mode = StackMode.FIRST


func apply_hit_modifier(chance: float, is_moderate_cover: bool) -> float:
	if is_moderate_cover:
		return chance * moderate_hit_mult
	return chance


## Pure geometric cover: obstruction tiles on the shooter-facing side of the target.
## Uses obstruction_height (>=1), not blocks_movement. No node access.
func cover_check(
	shooter_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapData,
) -> CoverCheckResult:
	var result := CoverCheckResult.new()
	if map_data == null or shooter_cell == target_cell:
		return result

	var delta := Vector2(target_cell - shooter_cell)
	var length := delta.length()
	if length <= 0.0001:
		return result
	var shot_dir := delta / length ## v = normalize(target - shooter)
	var toward_shooter := -shot_dir ## cover must lie on the side fire comes from

	var radius := cover_range_limit
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if ox == 0 and oy == 0:
				continue
			var cell := target_cell + Vector2i(ox, oy)
			if not map_data.is_in_bounds(cell):
				continue
			if map_data.obstruction_height(cell) < 1:
				continue
			if not _on_shooter_facing_side(cell, target_cell, toward_shooter):
				continue
			result.qualifying_cells.append(cell)
			var is_corner := _is_corner_relative(cell, target_cell, shot_dir)
			if not result.in_cover:
				result.in_cover = true
				result.source_cell = cell
				if is_corner:
					result.qualifier = Qualifier.CORNER
				if stack_mode == StackMode.FIRST:
					return result
			elif is_corner:
				result.qualifier = Qualifier.CORNER
	return result


## Cover tile C is between target and shooter: (C - target) · (-v) > 0.
static func _on_shooter_facing_side(
	cover_cell: Vector2i,
	target_cell: Vector2i,
	toward_shooter: Vector2,
) -> bool:
	var from_target := Vector2(cover_cell - target_cell)
	return from_target.dot(toward_shooter) > 0.0001


## PseudoCover / corner: offset from target is not collinear with the shot vector.
static func _is_corner_relative(
	cover_cell: Vector2i,
	target_cell: Vector2i,
	shot_dir: Vector2,
) -> bool:
	var offset := Vector2(cover_cell - target_cell)
	var cross := offset.x * shot_dir.y - offset.y * shot_dir.x
	return absf(cross) > 0.0001


func apply_config(section: Dictionary) -> void:
	if section.has("moderate_hit_mult"):
		moderate_hit_mult = float(section.moderate_hit_mult)
	if section.has("moderate_visibility_mult"):
		moderate_visibility_mult = float(section.moderate_visibility_mult)
	if section.has("cover_range_limit"):
		cover_range_limit = int(section.cover_range_limit)
	if section.has("stack_mode"):
		var mode := str(section.stack_mode).to_lower()
		if mode == "count" or mode == "1":
			stack_mode = StackMode.COUNT
		else:
			stack_mode = StackMode.FIRST
