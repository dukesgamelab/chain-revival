class_name VisionPolicy
extends RefCounted
## Spotting / cone-of-fire / visibility tuning.
## Gameplay asks: "What vision distance / cone width / prone visibility?"

## Legacy width alias — derived from half-angle when unset. Kept for older configs/UI.
const DEFAULT_CONE_WIDTH_AT_MAX_RANGE := 48
const DEFAULT_CONE_RANGE_BONUS := 8
## TUNED — must exceed 22.5° so a full 8-way facing sector fits inside the cone.
## (atan(15/48)≈17.4° with old width=30 left sector edges outside the cone at every range.)
const DEFAULT_CONE_HALF_ANGLE_DEG := 26.0
## TUNED — absolute floor so near/adjacent off-axis targets are never squeezed out.
const DEFAULT_CONE_MIN_HALF_WIDTH_TILES := 1.0
const DEFAULT_WORLD_AIM_FORWARD_SLACK := 8.0
const DEFAULT_WORLD_AIM_LATERAL_SLACK := 4.0
const DEFAULT_AIM_DIR_MIN_LENGTH_SQ := 4.0
const DEFAULT_PRONE_VISIBILITY_MULT := 0.75


var cone_width_at_max_range: int = DEFAULT_CONE_WIDTH_AT_MAX_RANGE
var cone_range_bonus: int = DEFAULT_CONE_RANGE_BONUS
var cone_half_angle_deg: float = DEFAULT_CONE_HALF_ANGLE_DEG
var cone_min_half_width_tiles: float = DEFAULT_CONE_MIN_HALF_WIDTH_TILES
var world_aim_forward_slack: float = DEFAULT_WORLD_AIM_FORWARD_SLACK
var world_aim_lateral_slack: float = DEFAULT_WORLD_AIM_LATERAL_SLACK
var aim_dir_min_length_sq: float = DEFAULT_AIM_DIR_MIN_LENGTH_SQ
var prone_visibility_mult: float = DEFAULT_PRONE_VISIBILITY_MULT


func reset_to_defaults() -> void:
	cone_half_angle_deg = DEFAULT_CONE_HALF_ANGLE_DEG
	cone_min_half_width_tiles = DEFAULT_CONE_MIN_HALF_WIDTH_TILES
	cone_range_bonus = DEFAULT_CONE_RANGE_BONUS
	cone_width_at_max_range = _width_from_half_angle(48)
	world_aim_forward_slack = DEFAULT_WORLD_AIM_FORWARD_SLACK
	world_aim_lateral_slack = DEFAULT_WORLD_AIM_LATERAL_SLACK
	aim_dir_min_length_sq = DEFAULT_AIM_DIR_MIN_LENGTH_SQ
	prone_visibility_mult = DEFAULT_PRONE_VISIBILITY_MULT


func effective_cone_range(weapon_range: int) -> int:
	return weapon_range + cone_range_bonus


## Half-width (tiles) allowed at this forward distance along the facing axis.
func cone_half_width_at_forward(forward: float, max_range: int) -> float:
	var reach := maxf(float(maxi(max_range, 1)), 0.001)
	var fwd := clampf(forward, 0.0, reach)
	var tan_half := tan(deg_to_rad(cone_half_angle_deg))
	## Linear growth with range (constant half-angle), floored by min absolute width.
	return maxf(cone_min_half_width_tiles, fwd * tan_half)


## Integer full width at max range — for outline / legacy call sites.
func cone_width_tiles_at_max(max_range: int) -> int:
	var half := cone_half_width_at_forward(float(maxi(max_range, 1)), max_range)
	return maxi(ceili(half * 2.0), 1)


func _width_from_half_angle(max_range: int) -> int:
	var tan_half := tan(deg_to_rad(cone_half_angle_deg))
	var half := maxf(cone_min_half_width_tiles, float(maxi(max_range, 1)) * tan_half)
	return maxi(ceili(half * 2.0), 1)


func apply_config(section: Dictionary) -> void:
	if section.has("cone_half_angle_deg"):
		cone_half_angle_deg = float(section.cone_half_angle_deg)
	if section.has("cone_min_half_width_tiles"):
		cone_min_half_width_tiles = float(section.cone_min_half_width_tiles)
	if section.has("cone_range_bonus"):
		cone_range_bonus = int(section.cone_range_bonus)
	if section.has("cone_width_at_max_range"):
		## Legacy key — only applied when half-angle is not explicitly set.
		if not section.has("cone_half_angle_deg"):
			cone_width_at_max_range = int(section.cone_width_at_max_range)
			## Approximate half-angle from width@48 so old configs keep similar openness.
			var half_w := float(cone_width_at_max_range) * 0.5
			cone_half_angle_deg = rad_to_deg(atan(half_w / 48.0))
	else:
		cone_width_at_max_range = _width_from_half_angle(48)
	if section.has("world_aim_forward_slack"):
		world_aim_forward_slack = float(section.world_aim_forward_slack)
	if section.has("world_aim_lateral_slack"):
		world_aim_lateral_slack = float(section.world_aim_lateral_slack)
	if section.has("aim_dir_min_length_sq"):
		aim_dir_min_length_sq = float(section.aim_dir_min_length_sq)
	if section.has("prone_visibility_mult"):
		prone_visibility_mult = float(section.prone_visibility_mult)
