class_name VisionPolicy
extends RefCounted
## Spotting / cone-of-fire / visibility tuning.
## Gameplay asks: "What vision distance / cone width / prone visibility?"

const DEFAULT_CONE_WIDTH_AT_MAX_RANGE := 30
const DEFAULT_CONE_RANGE_BONUS := 8
const DEFAULT_WORLD_AIM_FORWARD_SLACK := 8.0
const DEFAULT_WORLD_AIM_LATERAL_SLACK := 4.0
const DEFAULT_AIM_DIR_MIN_LENGTH_SQ := 4.0
const DEFAULT_PRONE_VISIBILITY_MULT := 0.75


var cone_width_at_max_range: int = DEFAULT_CONE_WIDTH_AT_MAX_RANGE
var cone_range_bonus: int = DEFAULT_CONE_RANGE_BONUS
var world_aim_forward_slack: float = DEFAULT_WORLD_AIM_FORWARD_SLACK
var world_aim_lateral_slack: float = DEFAULT_WORLD_AIM_LATERAL_SLACK
var aim_dir_min_length_sq: float = DEFAULT_AIM_DIR_MIN_LENGTH_SQ
var prone_visibility_mult: float = DEFAULT_PRONE_VISIBILITY_MULT


func reset_to_defaults() -> void:
	cone_width_at_max_range = DEFAULT_CONE_WIDTH_AT_MAX_RANGE
	cone_range_bonus = DEFAULT_CONE_RANGE_BONUS
	world_aim_forward_slack = DEFAULT_WORLD_AIM_FORWARD_SLACK
	world_aim_lateral_slack = DEFAULT_WORLD_AIM_LATERAL_SLACK
	aim_dir_min_length_sq = DEFAULT_AIM_DIR_MIN_LENGTH_SQ
	prone_visibility_mult = DEFAULT_PRONE_VISIBILITY_MULT


func effective_cone_range(weapon_range: int) -> int:
	return weapon_range + cone_range_bonus


func apply_config(section: Dictionary) -> void:
	if section.has("cone_width_at_max_range"):
		cone_width_at_max_range = int(section.cone_width_at_max_range)
	if section.has("cone_range_bonus"):
		cone_range_bonus = int(section.cone_range_bonus)
	if section.has("world_aim_forward_slack"):
		world_aim_forward_slack = float(section.world_aim_forward_slack)
	if section.has("world_aim_lateral_slack"):
		world_aim_lateral_slack = float(section.world_aim_lateral_slack)
	if section.has("aim_dir_min_length_sq"):
		aim_dir_min_length_sq = float(section.aim_dir_min_length_sq)
	if section.has("prone_visibility_mult"):
		prone_visibility_mult = float(section.prone_visibility_mult)
