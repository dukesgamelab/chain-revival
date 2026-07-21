class_name HitChancePolicy
extends RefCounted
## Configurable hit-chance and fire-cadence values. Defaults match current CombatSystem.

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

var clear_base_hit_chance: float = DEFAULT_CLEAR_BASE_HIT_CHANCE
var clear_distance_penalty: float = DEFAULT_CLEAR_DISTANCE_PENALTY
var min_hit_chance: float = DEFAULT_MIN_HIT_CHANCE
var shooter_prone_accuracy_mult: float = DEFAULT_SHOOTER_PRONE_ACCURACY_MULT
var target_prone_hit_mult: float = DEFAULT_TARGET_PRONE_HIT_MULT
var moderate_cover_hit_mult: float = DEFAULT_MODERATE_COVER_HIT_MULT
var auto_target_engaged_bonus: float = DEFAULT_AUTO_TARGET_ENGAGED_BONUS
var auto_fire_scan_interval: float = DEFAULT_AUTO_FIRE_SCAN_INTERVAL
var fire_prep_delay_sec: float = DEFAULT_FIRE_PREP_DELAY_SEC
var recently_seen_sec: float = DEFAULT_RECENTLY_SEEN_SEC
var recently_fired_spot_sec: float = DEFAULT_RECENTLY_FIRED_SPOT_SEC
var last_known_near_tiles: int = DEFAULT_LAST_KNOWN_NEAR_TILES
var spotting_range_bonus: int = DEFAULT_SPOTTING_RANGE_BONUS


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
