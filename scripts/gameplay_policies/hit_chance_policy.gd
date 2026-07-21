class_name HitChancePolicy
extends RefCounted
## Configurable hit-chance, spotting windows, and target-score weights.
## Defaults match current CombatSystem behavior.

const DEFAULT_CLEAR_BASE_HIT_CHANCE := 0.78
const DEFAULT_CLEAR_DISTANCE_PENALTY := 0.025
const DEFAULT_MIN_HIT_CHANCE := 0.10
const DEFAULT_SHOOTER_PRONE_ACCURACY_MULT := 1.15
const DEFAULT_TARGET_PRONE_HIT_MULT := 0.55
const DEFAULT_MODERATE_COVER_HIT_MULT := 0.5
const DEFAULT_AUTO_TARGET_ENGAGED_BONUS := 10.0
const DEFAULT_AUTO_FIRE_SCAN_INTERVAL := 0.5
const DEFAULT_FIRE_PREP_DELAY_SEC := 1.0
const DEFAULT_RECENTLY_SEEN_SEC := 2.0
const DEFAULT_RECENTLY_FIRED_SPOT_SEC := 2.0
const DEFAULT_LAST_KNOWN_NEAR_TILES := 2
const DEFAULT_SPOTTING_RANGE_BONUS := 10

## Visibility score weights (spotting priority list).
const DEFAULT_VIS_SCORE_BASE := 100.0
const DEFAULT_VIS_SCORE_DIST_PENALTY := 4.0
const DEFAULT_VIS_SCORE_RUN_BONUS := 15.0
const DEFAULT_VIS_SCORE_WALK_BONUS := 10.0
const DEFAULT_VIS_SCORE_RECENTLY_FIRED_BONUS := 25.0
const DEFAULT_VIS_SCORE_MODERATE_COVER_PENALTY := 20.0

## Fire At Will auto-target score weights.
const DEFAULT_AUTO_SCORE_BASE := 100.0
const DEFAULT_AUTO_SCORE_DIST_PENALTY := 4.0
const DEFAULT_AUTO_SCORE_CLEAR_BONUS := 25.0
const DEFAULT_AUTO_SCORE_MODERATE_PENALTY := 10.0
const DEFAULT_AUTO_SCORE_COMPLETE_PENALTY := 25.0
const DEFAULT_AUTO_SCORE_MOVING_BONUS := 10.0
const DEFAULT_AUTO_SCORE_PRONE_PENALTY := 20.0
const DEFAULT_AUTO_SCORE_FACING_BONUS := 15.0
const DEFAULT_AUTO_SCORE_SMG_LMG_BONUS := 20.0

var clear_base_hit_chance: float = DEFAULT_CLEAR_BASE_HIT_CHANCE
var clear_distance_penalty: float = DEFAULT_CLEAR_DISTANCE_PENALTY
var min_hit_chance: float = DEFAULT_MIN_HIT_CHANCE
var shooter_prone_accuracy_mult: float = DEFAULT_SHOOTER_PRONE_ACCURACY_MULT
var target_prone_hit_mult: float = DEFAULT_TARGET_PRONE_HIT_MULT
## Kept in sync with CoverPolicy.moderate_hit_mult for backward-compatible callers.
var moderate_cover_hit_mult: float = DEFAULT_MODERATE_COVER_HIT_MULT
var auto_target_engaged_bonus: float = DEFAULT_AUTO_TARGET_ENGAGED_BONUS
var auto_fire_scan_interval: float = DEFAULT_AUTO_FIRE_SCAN_INTERVAL
var fire_prep_delay_sec: float = DEFAULT_FIRE_PREP_DELAY_SEC
var recently_seen_sec: float = DEFAULT_RECENTLY_SEEN_SEC
var recently_fired_spot_sec: float = DEFAULT_RECENTLY_FIRED_SPOT_SEC
var last_known_near_tiles: int = DEFAULT_LAST_KNOWN_NEAR_TILES
var spotting_range_bonus: int = DEFAULT_SPOTTING_RANGE_BONUS

var vis_score_base: float = DEFAULT_VIS_SCORE_BASE
var vis_score_dist_penalty: float = DEFAULT_VIS_SCORE_DIST_PENALTY
var vis_score_run_bonus: float = DEFAULT_VIS_SCORE_RUN_BONUS
var vis_score_walk_bonus: float = DEFAULT_VIS_SCORE_WALK_BONUS
var vis_score_recently_fired_bonus: float = DEFAULT_VIS_SCORE_RECENTLY_FIRED_BONUS
var vis_score_moderate_cover_penalty: float = DEFAULT_VIS_SCORE_MODERATE_COVER_PENALTY

var auto_score_base: float = DEFAULT_AUTO_SCORE_BASE
var auto_score_dist_penalty: float = DEFAULT_AUTO_SCORE_DIST_PENALTY
var auto_score_clear_bonus: float = DEFAULT_AUTO_SCORE_CLEAR_BONUS
var auto_score_moderate_penalty: float = DEFAULT_AUTO_SCORE_MODERATE_PENALTY
var auto_score_complete_penalty: float = DEFAULT_AUTO_SCORE_COMPLETE_PENALTY
var auto_score_moving_bonus: float = DEFAULT_AUTO_SCORE_MOVING_BONUS
var auto_score_prone_penalty: float = DEFAULT_AUTO_SCORE_PRONE_PENALTY
var auto_score_facing_bonus: float = DEFAULT_AUTO_SCORE_FACING_BONUS
var auto_score_smg_lmg_bonus: float = DEFAULT_AUTO_SCORE_SMG_LMG_BONUS


func reset_to_defaults() -> void:
	clear_base_hit_chance = DEFAULT_CLEAR_BASE_HIT_CHANCE
	clear_distance_penalty = DEFAULT_CLEAR_DISTANCE_PENALTY
	min_hit_chance = DEFAULT_MIN_HIT_CHANCE
	shooter_prone_accuracy_mult = DEFAULT_SHOOTER_PRONE_ACCURACY_MULT
	target_prone_hit_mult = DEFAULT_TARGET_PRONE_HIT_MULT
	moderate_cover_hit_mult = DEFAULT_MODERATE_COVER_HIT_MULT
	auto_target_engaged_bonus = DEFAULT_AUTO_TARGET_ENGAGED_BONUS
	auto_fire_scan_interval = DEFAULT_AUTO_FIRE_SCAN_INTERVAL
	fire_prep_delay_sec = DEFAULT_FIRE_PREP_DELAY_SEC
	recently_seen_sec = DEFAULT_RECENTLY_SEEN_SEC
	recently_fired_spot_sec = DEFAULT_RECENTLY_FIRED_SPOT_SEC
	last_known_near_tiles = DEFAULT_LAST_KNOWN_NEAR_TILES
	spotting_range_bonus = DEFAULT_SPOTTING_RANGE_BONUS
	vis_score_base = DEFAULT_VIS_SCORE_BASE
	vis_score_dist_penalty = DEFAULT_VIS_SCORE_DIST_PENALTY
	vis_score_run_bonus = DEFAULT_VIS_SCORE_RUN_BONUS
	vis_score_walk_bonus = DEFAULT_VIS_SCORE_WALK_BONUS
	vis_score_recently_fired_bonus = DEFAULT_VIS_SCORE_RECENTLY_FIRED_BONUS
	vis_score_moderate_cover_penalty = DEFAULT_VIS_SCORE_MODERATE_COVER_PENALTY
	auto_score_base = DEFAULT_AUTO_SCORE_BASE
	auto_score_dist_penalty = DEFAULT_AUTO_SCORE_DIST_PENALTY
	auto_score_clear_bonus = DEFAULT_AUTO_SCORE_CLEAR_BONUS
	auto_score_moderate_penalty = DEFAULT_AUTO_SCORE_MODERATE_PENALTY
	auto_score_complete_penalty = DEFAULT_AUTO_SCORE_COMPLETE_PENALTY
	auto_score_moving_bonus = DEFAULT_AUTO_SCORE_MOVING_BONUS
	auto_score_prone_penalty = DEFAULT_AUTO_SCORE_PRONE_PENALTY
	auto_score_facing_bonus = DEFAULT_AUTO_SCORE_FACING_BONUS
	auto_score_smg_lmg_bonus = DEFAULT_AUTO_SCORE_SMG_LMG_BONUS


func apply_config(section: Dictionary) -> void:
	_set_float(section, "clear_base_hit_chance", "clear_base_hit_chance")
	_set_float(section, "clear_distance_penalty", "clear_distance_penalty")
	_set_float(section, "min_hit_chance", "min_hit_chance")
	_set_float(section, "shooter_prone_accuracy_mult", "shooter_prone_accuracy_mult")
	_set_float(section, "target_prone_hit_mult", "target_prone_hit_mult")
	_set_float(section, "moderate_cover_hit_mult", "moderate_cover_hit_mult")
	_set_float(section, "auto_target_engaged_bonus", "auto_target_engaged_bonus")
	_set_float(section, "auto_fire_scan_interval", "auto_fire_scan_interval")
	_set_float(section, "fire_prep_delay_sec", "fire_prep_delay_sec")
	_set_float(section, "recently_seen_sec", "recently_seen_sec")
	_set_float(section, "recently_fired_spot_sec", "recently_fired_spot_sec")
	if section.has("last_known_near_tiles"):
		last_known_near_tiles = int(section.last_known_near_tiles)
	if section.has("spotting_range_bonus"):
		spotting_range_bonus = int(section.spotting_range_bonus)
	_set_float(section, "vis_score_base", "vis_score_base")
	_set_float(section, "vis_score_dist_penalty", "vis_score_dist_penalty")
	_set_float(section, "vis_score_run_bonus", "vis_score_run_bonus")
	_set_float(section, "vis_score_walk_bonus", "vis_score_walk_bonus")
	_set_float(section, "vis_score_recently_fired_bonus", "vis_score_recently_fired_bonus")
	_set_float(section, "vis_score_moderate_cover_penalty", "vis_score_moderate_cover_penalty")
	_set_float(section, "auto_score_base", "auto_score_base")
	_set_float(section, "auto_score_dist_penalty", "auto_score_dist_penalty")
	_set_float(section, "auto_score_clear_bonus", "auto_score_clear_bonus")
	_set_float(section, "auto_score_moderate_penalty", "auto_score_moderate_penalty")
	_set_float(section, "auto_score_complete_penalty", "auto_score_complete_penalty")
	_set_float(section, "auto_score_moving_bonus", "auto_score_moving_bonus")
	_set_float(section, "auto_score_prone_penalty", "auto_score_prone_penalty")
	_set_float(section, "auto_score_facing_bonus", "auto_score_facing_bonus")
	_set_float(section, "auto_score_smg_lmg_bonus", "auto_score_smg_lmg_bonus")


func _set_float(section: Dictionary, key: String, field: String) -> void:
	if section.has(key):
		set(field, float(section[key]))
