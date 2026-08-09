class_name HitChancePolicy
extends RefCounted
## Configurable hit-chance, spotting windows, and target-score weights.
## Hit chance uses the recovered quotient polynomial (Stage 5); absolute scale via hit_scale.

## Deprecated subtractive-curve leftovers (unused by hit_chance; kept for config compat).
const DEFAULT_CLEAR_BASE_HIT_CHANCE := 0.78
const DEFAULT_CLEAR_DISTANCE_PENALTY := 0.025
## Optional floor on base polynomial result. 0 — HUD anchors include SMG ≈ 0.03.
const DEFAULT_MIN_HIT_CHANCE := 0.0
const DEFAULT_SHOOTER_PRONE_ACCURACY_MULT := 1.15
const DEFAULT_TARGET_PRONE_HIT_MULT := 0.55
const DEFAULT_MODERATE_COVER_HIT_MULT := 0.5
## TUNED — fitted so rifle ≈ 0.09 at Euclidean range 11, AimTime=1, Stress 0 (OG HUD).
## Relative weapon shape is RECOVERED; only this absolute scale is free.
## Was 0.07776 (rifle ≈11.7% at 11 tiles); trimmed so long-range matches original.
const DEFAULT_HIT_SCALE := 0.060
## Fixed AimTime until Exp-Str × Range tables are wired.
const DEFAULT_AIM_TIME := 1.0
## Floor on D = Range − MarksMan so the denominator never hits zero.
const DEFAULT_RANGE_EPSILON := 0.25
## Generous engagement envelope (cone / out-of-range). Hit falloff is via the polynomial.
const DEFAULT_MAX_ENGAGEMENT_TILES := 40
## RECOVERED INITKilledProbability = 0.20 (separate kill roll after hit).
const RECOVERED_LETHALITY_MULTIPLIER := 0.20
## TUNED — without a wound state, a hit should ≈ remove the soldier (OG casualty rate).
## Was 0.40 (point-blank hits often did nothing). Revert to 0.20 when wound state lands.
## Folded as P(death) = HitFinal × lethality_multiplier (bullets + grenade casualty).
const DEFAULT_LETHALITY_MULTIPLIER := 0.90
const DEFAULT_AUTO_TARGET_ENGAGED_BONUS := 10.0
const DEFAULT_AUTO_FIRE_SCAN_INTERVAL := 0.5
## RECOVERED from gameplay capture — 5.05s and 6.09s observed; midpoint used as default.
## Aim cycle and fire interval are the same thing in the original (continuous Aiming).
const DEFAULT_BASE_FIRE_CYCLE_SEC := 5.5
## TUNED visual/audio spacing within a burst (6 rounds ≈ 0.2s). Does not affect hit rolls.
const DEFAULT_BURST_ROUND_INTERVAL_SEC := 0.04
## Legacy alias of base_fire_cycle_sec (kept for older callers / tests).
const DEFAULT_FIRE_PREP_DELAY_SEC := DEFAULT_BASE_FIRE_CYCLE_SEC
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
## Absolute scale on the recovered hit quotient. See DEFAULT_HIT_SCALE.
var hit_scale: float = DEFAULT_HIT_SCALE
var aim_time: float = DEFAULT_AIM_TIME
var range_epsilon: float = DEFAULT_RANGE_EPSILON
var max_engagement_tiles: int = DEFAULT_MAX_ENGAGEMENT_TILES
var shooter_prone_accuracy_mult: float = DEFAULT_SHOOTER_PRONE_ACCURACY_MULT
var target_prone_hit_mult: float = DEFAULT_TARGET_PRONE_HIT_MULT
## Kept in sync with CoverPolicy.moderate_hit_mult for backward-compatible callers.
var moderate_cover_hit_mult: float = DEFAULT_MODERATE_COVER_HIT_MULT
## Multiplies HitFinal immediately before the kill roll. Not baked into hit_chance().
var lethality_multiplier: float = DEFAULT_LETHALITY_MULTIPLIER
var auto_target_engaged_bonus: float = DEFAULT_AUTO_TARGET_ENGAGED_BONUS
var auto_fire_scan_interval: float = DEFAULT_AUTO_FIRE_SCAN_INTERVAL
## Global aim/fire cycle (seconds). Per-weapon fire_interval_sec overrides when > 0.
var base_fire_cycle_sec: float = DEFAULT_BASE_FIRE_CYCLE_SEC
var burst_round_interval_sec: float = DEFAULT_BURST_ROUND_INTERVAL_SEC
## Legacy alias — always kept equal to base_fire_cycle_sec.
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
	hit_scale = DEFAULT_HIT_SCALE
	aim_time = DEFAULT_AIM_TIME
	range_epsilon = DEFAULT_RANGE_EPSILON
	max_engagement_tiles = DEFAULT_MAX_ENGAGEMENT_TILES
	shooter_prone_accuracy_mult = DEFAULT_SHOOTER_PRONE_ACCURACY_MULT
	target_prone_hit_mult = DEFAULT_TARGET_PRONE_HIT_MULT
	moderate_cover_hit_mult = DEFAULT_MODERATE_COVER_HIT_MULT
	lethality_multiplier = DEFAULT_LETHALITY_MULTIPLIER
	auto_target_engaged_bonus = DEFAULT_AUTO_TARGET_ENGAGED_BONUS
	auto_fire_scan_interval = DEFAULT_AUTO_FIRE_SCAN_INTERVAL
	base_fire_cycle_sec = DEFAULT_BASE_FIRE_CYCLE_SEC
	burst_round_interval_sec = DEFAULT_BURST_ROUND_INTERVAL_SEC
	fire_prep_delay_sec = base_fire_cycle_sec
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
	_set_float(section, "hit_scale", "hit_scale")
	_set_float(section, "aim_time", "aim_time")
	_set_float(section, "range_epsilon", "range_epsilon")
	if section.has("max_engagement_tiles"):
		max_engagement_tiles = int(section.max_engagement_tiles)
	_set_float(section, "shooter_prone_accuracy_mult", "shooter_prone_accuracy_mult")
	_set_float(section, "target_prone_hit_mult", "target_prone_hit_mult")
	_set_float(section, "moderate_cover_hit_mult", "moderate_cover_hit_mult")
	_set_float(section, "lethality_multiplier", "lethality_multiplier")
	_set_float(section, "auto_target_engaged_bonus", "auto_target_engaged_bonus")
	_set_float(section, "auto_fire_scan_interval", "auto_fire_scan_interval")
	_set_float(section, "base_fire_cycle_sec", "base_fire_cycle_sec")
	_set_float(section, "burst_round_interval_sec", "burst_round_interval_sec")
	# Legacy key: prefer base_fire_cycle_sec when both are present.
	if section.has("fire_prep_delay_sec") and not section.has("base_fire_cycle_sec"):
		_set_float(section, "fire_prep_delay_sec", "base_fire_cycle_sec")
	fire_prep_delay_sec = base_fire_cycle_sec
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
