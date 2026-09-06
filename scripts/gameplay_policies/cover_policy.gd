class_name CoverPolicy
extends RefCounted
## Cover hit / visibility modifiers + 8-direction adjacency cover check.
## Geometry: one compass-slot lookup on the target (shot-direction facing).
## Hit curve: recovered INITCoverHitMultiplier / INITCoverRangeLimit.

## Deprecated flat mult — replaced by cover_multiplier_for_range(). Kept for config compat.
const DEFAULT_MODERATE_HIT_MULT := 0.5
const DEFAULT_MODERATE_VISIBILITY_MULT := 0.65

## RECOVERED from Initial-*.oin.
const INIT_COVER_IN_MULTIPLIER := 1.0
const INIT_COVER_HIT_MULTIPLIER := 0.005 ## full-strength cover hit mult at range >= limit
const INIT_COVER_RANGE_LIMIT := 5 ## range (tiles) at which cover reaches full strength
const INIT_COVER_NEAR_FLOOR := 0.5 ## floor on the ramp before cover_range_limit
const INIT_MIN_DUCKING_RANGE := 4
const INIT_KILLED_PROBABILITY := 20

## TUNED optional per-obstruction strength. Original treats wall/hedge identically (= 1.0).
const DEFAULT_OBJECT_COVER_STRENGTH := 1.0

## Eight compass offsets stored on the target (N, NE, E, SE, S, SW, W, NW).
const DIR8_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
]

## UNRESOLVED: whether multiple qualifying tiles stack. Default FIRST = single slot.
enum StackMode { FIRST, COUNT }

enum Qualifier { NONE, CORNER } ## CORNER = diagonal compass slot (PseudoCover)


var moderate_hit_mult: float = DEFAULT_MODERATE_HIT_MULT ## deprecated flat alias
var moderate_visibility_mult: float = DEFAULT_MODERATE_VISIBILITY_MULT
## RECOVERED — full-strength cover hit multiplier (not a geometry radius).
var cover_hit_multiplier: float = INIT_COVER_HIT_MULTIPLIER
## RECOVERED — combat range at which cover_hit_multiplier applies in full.
var cover_range_limit: int = INIT_COVER_RANGE_LIMIT
## TUNED — multiplies the recovered curve; default 1.0 (no type differentiation).
var object_cover_strength: float = DEFAULT_OBJECT_COVER_STRENGTH
var stack_mode: int = StackMode.FIRST


class CoverCheckResult extends RefCounted:
	var in_cover: bool = false
	var qualifier: int = Qualifier.NONE
	var source_cell: Vector2i = Vector2i(-999, -999)
	## Slots that passed (debug). With 8-dir lookup this is 0–1 cells.
	var qualifying_cells: Array[Vector2i] = []
	var cover_offset: Vector2i = Vector2i.ZERO


func reset_to_defaults() -> void:
	moderate_hit_mult = DEFAULT_MODERATE_HIT_MULT
	moderate_visibility_mult = DEFAULT_MODERATE_VISIBILITY_MULT
	cover_hit_multiplier = INIT_COVER_HIT_MULTIPLIER
	cover_range_limit = INIT_COVER_RANGE_LIMIT
	object_cover_strength = DEFAULT_OBJECT_COVER_STRENGTH
	stack_mode = StackMode.FIRST


## Cover curve (combat range in tiles, Euclidean).
## range 1 → 1.0; ramps toward cover_hit_multiplier by cover_range_limit, floored at 0.5
## while still inside the limit so a hedge at 3 tiles is not a near-zero cliff.
func cover_multiplier_for_range(combat_range: float) -> float:
	var limit := float(maxi(cover_range_limit, 1))
	var r := maxf(combat_range, 1.0)
	var mult: float
	if r >= limit:
		mult = cover_hit_multiplier
	else:
		mult = (cover_hit_multiplier - 1.0) * (r - 1.0) / limit + 1.0
		mult = maxf(mult, INIT_COVER_NEAR_FLOOR)
	return clampf(mult * object_cover_strength, 0.0, 1.0)


func apply_hit_modifier(
	chance: float,
	is_in_cover: bool,
	combat_range: float = -1.0,
) -> float:
	if not is_in_cover:
		return chance
	var range_tiles := combat_range
	if range_tiles < 0.0:
		## Missing range → full-strength cover (conservative for callers).
		range_tiles = float(cover_range_limit)
	return chance * cover_multiplier_for_range(range_tiles)


## One compass-slot lookup: cover occupies the 8-adjacent cell facing the shooter.
func cover_check(
	shooter_cell: Vector2i,
	target_cell: Vector2i,
	map_data: MapData,
) -> CoverCheckResult:
	var result := CoverCheckResult.new()
	if map_data == null or shooter_cell == target_cell:
		return result

	var toward_shooter := Vector2(shooter_cell - target_cell)
	if toward_shooter.length_squared() <= 0.0001:
		return result

	var offset := snap_to_cover_offset(toward_shooter)
	result.cover_offset = offset
	var cell := target_cell + offset
	if not map_data.is_in_bounds(cell):
		return result
	if map_data.obstruction_height(cell) < 1:
		return result

	result.in_cover = true
	result.source_cell = cell
	result.qualifying_cells.append(cell)
	if offset.x != 0 and offset.y != 0:
		result.qualifier = Qualifier.CORNER
	return result


## Nearest of 8 compass offsets to the vector from target toward shooter.
static func snap_to_cover_offset(toward_shooter: Vector2) -> Vector2i:
	var dir := toward_shooter.normalized()
	var best := DIR8_OFFSETS[0]
	var best_dot := -INF
	for offset in DIR8_OFFSETS:
		var slot_dir := Vector2(offset).normalized()
		var d := dir.dot(slot_dir)
		if d > best_dot:
			best_dot = d
			best = offset
	return best


func apply_config(section: Dictionary) -> void:
	if section.has("moderate_hit_mult"):
		moderate_hit_mult = float(section.moderate_hit_mult)
	if section.has("moderate_visibility_mult"):
		moderate_visibility_mult = float(section.moderate_visibility_mult)
	if section.has("cover_hit_multiplier"):
		cover_hit_multiplier = float(section.cover_hit_multiplier)
	if section.has("cover_range_limit"):
		cover_range_limit = int(section.cover_range_limit)
	if section.has("object_cover_strength"):
		object_cover_strength = float(section.object_cover_strength)
	if section.has("stack_mode"):
		var mode := str(section.stack_mode).to_lower()
		if mode == "count" or mode == "1":
			stack_mode = StackMode.COUNT
		else:
			stack_mode = StackMode.FIRST
