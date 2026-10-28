class_name SuppressionPolicy
extends RefCounted
## Suppression / stress policy.
##
## SCALE DECISION (B): runtime and UI stress stay 0–100. The original uses 0–7
## (INITMaxStressOut). Convert with STRESS_SCALE only — never scatter 100/7 literals.
##
## Recovered generation uses WeaponData StressFactor + stress_limit_tiles (range
## cutoff). stress_limit is a separate TUNED cap input. Accuracy uses the Exp-Str
## × Range table (JSON), normalized before multiplying hit chance.

const TABLE_PATH := "res://assets/data/stress_accuracy_table.json"

## --- Scale (option B) ---
const ORIGINAL_MAX_STRESS := 7.0 ## RECOVERED INITMaxStressOut
## ONE named conversion: original_units * STRESS_SCALE → runtime 0–100.
const STRESS_SCALE := 100.0 / ORIGINAL_MAX_STRESS

## --- Recovered globals ---
const INIT_STRESS_BASE := 0.80 ## RECOVERED
## RECOVERED retain fraction per decay_reference_sec (not per combat-scan tick).
## Stage 3: scans are 0.5s while fire is ~5.5s — applying 0.3 every scan wiped stress
## between shots. Time-normalize so 0.3 means “keep 30% over one fire-cycle of idle.”
const INIT_STRESS_FALL_MULTIPLIER := 0.3
const INIT_STRESS_INITIAL := 0.0 ## RECOVERED
const STRESS_MULTIPLIER_GLOBAL := 1.0 ## RECOVERED StressMultiplier$global
## TUNED — match base_fire_cycle_sec so decay is paced to shot arrival, not scan rate.
const DEFAULT_DECAY_REFERENCE_SEC := 5.5

## TUNED relative mapping helper only (stress_limit → 0–100). OG StressLimit is a
## range cutoff for gain; accumulation caps at max_stress (INITMaxStressOut → 100).
const STRESS_LIMIT_REF := 25.0

## TUNED UI / band thresholds on the 0–100 runtime scale (not recovered).
const DEFAULT_PINNED_THRESHOLD := 45.0
const DEFAULT_PANIC_THRESHOLD := 70.0
const DEFAULT_BAND_NERVOUS := 10.0
const DEFAULT_BAND_SUPPRESSED := 25.0
const DEFAULT_BAND_PINNED := 45.0
const DEFAULT_BAND_PANICKED := 70.0
const DEFAULT_MAX_STRESS := 100.0

## Legacy absolute recovery aliases (combat_system constants); decay uses fall multiplier.
const DEFAULT_RECOVERY_PER_TICK := 0.15
const DEFAULT_RECOVERY_PRONE_PER_TICK := 0.25

const DEFAULT_MODERATE_COVER_SUPPRESSION_MULT := 0.65
const DEFAULT_PRONE_SUPPRESSION_MULT := 0.75

## Legacy band tables kept for movement / fire-delay only (accuracy uses Exp-Str table).
const DEFAULT_MOVEMENT_BY_BAND: Array[float] = [1.0, 0.9, 0.75, 0.5, 0.35]
const DEFAULT_FIRE_DELAY_BY_BAND: Array[float] = [1.0, 1.05, 1.15, 1.3, 1.5]

## Fallback StressFactor when weapon data missing — matches recovered rifle/SMG/LMG shape.
const DEFAULT_SUPPRESSION_RIFLE := 0.25
const DEFAULT_SUPPRESSION_SMG := 2.0
const DEFAULT_SUPPRESSION_LMG := 0.6
const DEFAULT_SUPPRESSION_DEFAULT := 0.25
const DEFAULT_STRESS_LIMIT_TILES := 25.0 ## RECOVERED rifle/LMG StressLimit

## PROBABLE default experience for effective_tier = experience − stress_original.
## Not proven — change effective_tier_from_stress() if the axis is pure stress.
const DEFAULT_EXPERIENCE := 4.0

## Sorted ascending: -8, -4, 0, +4, +8 with matching Range0..6 rows.
## Initial.oin ships Exp-Str4/0/-4/-8 only; +8 key added per combat model (row = +4
## ceiling until an authentic Exp-Str8 row is recovered).
var _tier_keys: Array[float] = [-8.0, -4.0, 0.0, 4.0, 8.0]
var _tier_rows: Array = [
	[0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0],
	[1.0, 1.5, 1.5, 2.0, 2.5, 3.0, 3.0],
	[1.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0],
	[1.0, 4.0, 4.5, 4.5, 5.0, 5.0, 5.0],
	[1.0, 4.0, 4.5, 4.5, 5.0, 5.0, 5.0], ## +8 — matches Exp-Str4 until recovered
]

var moderate_cover_suppression_mult: float = DEFAULT_MODERATE_COVER_SUPPRESSION_MULT
var prone_suppression_mult: float = DEFAULT_PRONE_SUPPRESSION_MULT
var pinned_threshold: float = DEFAULT_PINNED_THRESHOLD
var panic_threshold: float = DEFAULT_PANIC_THRESHOLD
var band_nervous: float = DEFAULT_BAND_NERVOUS
var band_suppressed: float = DEFAULT_BAND_SUPPRESSED
var band_pinned: float = DEFAULT_BAND_PINNED
var band_panicked: float = DEFAULT_BAND_PANICKED
var movement_by_band: Array[float] = DEFAULT_MOVEMENT_BY_BAND.duplicate()
var fire_delay_by_band: Array[float] = DEFAULT_FIRE_DELAY_BY_BAND.duplicate()
var max_stress: float = DEFAULT_MAX_STRESS
var stress_base: float = INIT_STRESS_BASE
var stress_fall_multiplier: float = INIT_STRESS_FALL_MULTIPLIER
## Seconds over which stress_fall_multiplier is applied once (see apply_stress_decay).
var decay_reference_sec: float = DEFAULT_DECAY_REFERENCE_SEC
var stress_initial: float = INIT_STRESS_INITIAL
var stress_multiplier_global: float = STRESS_MULTIPLIER_GLOBAL
var default_experience: float = DEFAULT_EXPERIENCE

## Deprecated aliases (weapon StressFactor is authoritative). Kept for config compat.
var suppression_mg42: float = DEFAULT_SUPPRESSION_LMG
var suppression_bar: float = DEFAULT_SUPPRESSION_LMG
var suppression_smg: float = DEFAULT_SUPPRESSION_SMG
var suppression_default: float = DEFAULT_SUPPRESSION_DEFAULT
## Legacy absolute recovery (unused when fall multiplier is active); config may still set.
var recovery_per_tick: float = 0.15
var recovery_prone_per_tick: float = 0.25
var accuracy_by_band: Array[float] = [1.0, 0.85, 0.65, 0.4, 0.2]


func _init() -> void:
	reload_accuracy_table()


func reset_to_defaults() -> void:
	moderate_cover_suppression_mult = DEFAULT_MODERATE_COVER_SUPPRESSION_MULT
	prone_suppression_mult = DEFAULT_PRONE_SUPPRESSION_MULT
	pinned_threshold = DEFAULT_PINNED_THRESHOLD
	panic_threshold = DEFAULT_PANIC_THRESHOLD
	band_nervous = DEFAULT_BAND_NERVOUS
	band_suppressed = DEFAULT_BAND_SUPPRESSED
	band_pinned = DEFAULT_BAND_PINNED
	band_panicked = DEFAULT_BAND_PANICKED
	movement_by_band = DEFAULT_MOVEMENT_BY_BAND.duplicate()
	fire_delay_by_band = DEFAULT_FIRE_DELAY_BY_BAND.duplicate()
	max_stress = DEFAULT_MAX_STRESS
	stress_base = INIT_STRESS_BASE
	stress_fall_multiplier = INIT_STRESS_FALL_MULTIPLIER
	decay_reference_sec = DEFAULT_DECAY_REFERENCE_SEC
	stress_initial = INIT_STRESS_INITIAL
	stress_multiplier_global = STRESS_MULTIPLIER_GLOBAL
	default_experience = DEFAULT_EXPERIENCE
	suppression_mg42 = DEFAULT_SUPPRESSION_LMG
	suppression_bar = DEFAULT_SUPPRESSION_LMG
	suppression_smg = DEFAULT_SUPPRESSION_SMG
	suppression_default = DEFAULT_SUPPRESSION_DEFAULT
	recovery_per_tick = 0.15
	recovery_prone_per_tick = 0.25
	accuracy_by_band = [1.0, 0.85, 0.65, 0.4, 0.2]
	reload_accuracy_table()


## original (0–7) → runtime (0–100)
func to_runtime(original_stress: float) -> float:
	return original_stress * STRESS_SCALE


## runtime (0–100) → original (0–7)
func to_original(runtime_stress: float) -> float:
	return runtime_stress / STRESS_SCALE


func stress_initial_runtime() -> float:
	return to_runtime(stress_initial)


## PROBABLE mapping: effective_tier ≈ experience − stress_on_original_scale.
## Documented single function — swap body if the axis is pure-stress.
func effective_tier_from_stress(runtime_stress: float, experience: float = -999.0) -> float:
	var xp := default_experience if experience < -900.0 else experience
	return xp - to_original(runtime_stress)


## Manhattan / Chebyshev tile distance → Range0..Range6 index.
func range_band_from_distance(distance_tiles: int) -> int:
	return clampi(distance_tiles, 0, 6)


## Normalized hit-chance multiplier from the recovered table.
## Raw weights are relative; divide by the best tier key at the same band so calm ≈ 1.0.
func accuracy_multiplier(effective_tier: float, range_band: int) -> float:
	var band := clampi(range_band, 0, 6)
	var raw := _raw_weight(effective_tier, band)
	var best_tier := 4.0 if _tier_keys.is_empty() else _tier_keys[_tier_keys.size() - 1]
	var ref := _raw_weight(best_tier, band)
	if ref <= 0.0001:
		return 1.0
	return clampf(raw / ref, 0.0, 2.0)


## stress_aim_factor scales how hard the shooter's own stress degrades aim (RECOVERED).
func apply_stress_aim_factor(table_multiplier: float, stress_aim_factor: float) -> float:
	var degradation := 1.0 - clampf(table_multiplier, 0.0, 1.0)
	var factor := maxf(stress_aim_factor, 0.0)
	return clampf(1.0 - degradation * factor, 0.05, 1.0)


## Convenience: runtime stress + distance (+ optional weapon aim factor) → accuracy mult.
func accuracy_modifier_for(
	runtime_stress: float,
	distance_tiles: int,
	stress_aim_factor: float = 1.0,
	experience: float = -999.0,
) -> float:
	var tier := effective_tier_from_stress(runtime_stress, experience)
	var band := range_band_from_distance(distance_tiles)
	var table_mult := accuracy_multiplier(tier, band)
	return apply_stress_aim_factor(table_mult, stress_aim_factor)


## Legacy API: mid-range band, aim factor 1.0.
func accuracy_modifier(stress: float) -> float:
	return accuracy_modifier_for(stress, 3, 1.0)


## Legacy factor-only gain (no range). Prefer range_suppression_gain_runtime().
func suppression_gain_runtime(stress_factor: float) -> float:
	return (
		float(stress_factor)
		* stress_base
		* stress_multiplier_global
		* STRESS_SCALE
	)


## RECOVERED GivenStress = (StressLimit − range) × StressFactor when range < StressLimit.
## Returns runtime 0–100 units (original × STRESS_SCALE). No gain at/ beyond cutoff.
func range_suppression_gain_runtime(
	stress_factor: float,
	stress_limit_tiles: float,
	range_tiles: int,
) -> float:
	if stress_limit_tiles <= 0.0 or float(range_tiles) >= stress_limit_tiles:
		return 0.0
	var original := (stress_limit_tiles - float(range_tiles)) * float(stress_factor)
	if original <= 0.0:
		return 0.0
	return original * stress_multiplier_global * STRESS_SCALE


## TUNED per-weapon stress_limit → runtime cap (relative mapping; see STRESS_LIMIT_REF).
func weapon_stress_cap_runtime(stress_limit: float) -> float:
	if stress_limit <= 0.0:
		return max_stress
	return clampf((stress_limit / STRESS_LIMIT_REF) * max_stress, 0.0, max_stress)


## Decay toward INITStressInitial when unthreatened.
## stress_fall_multiplier = retain fraction over decay_reference_sec; delta_sec scales it
## so a 0.5s combat scan does not apply a full recovery step.
func apply_stress_decay(
	runtime_stress: float,
	prone: bool = false,
	delta_sec: float = -1.0,
) -> float:
	var target := stress_initial_runtime()
	if runtime_stress <= target:
		return target
	var dt := decay_reference_sec if delta_sec < 0.0 else maxf(delta_sec, 0.0)
	if dt <= 0.0:
		return runtime_stress
	var retain_period := stress_fall_multiplier
	if prone:
		## TUNED: prone recovers faster (lower retain) than standing.
		retain_period *= 0.5
	retain_period = clampf(retain_period, 0.0, 1.0)
	var period := maxf(decay_reference_sec, 0.001)
	var retain := pow(retain_period, dt / period)
	return maxf(target, runtime_stress * retain)


func stress_band(stress: float) -> int:
	if stress < band_nervous:
		return 0
	if stress < band_suppressed:
		return 1
	if stress < band_pinned:
		return 2
	if stress < band_panicked:
		return 3
	return 4


func movement_modifier(stress: float) -> float:
	var band := stress_band(stress)
	if band < 0 or band >= movement_by_band.size():
		return 1.0
	return movement_by_band[band]


func fire_delay_modifier(stress: float) -> float:
	var band := stress_band(stress)
	if band < 0 or band >= fire_delay_by_band.size():
		return 1.0
	return fire_delay_by_band[band]


func reload_accuracy_table() -> void:
	if not FileAccess.file_exists(TABLE_PATH):
		return
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var tiers: Variant = parsed.get("tiers", [])
	if not (tiers is Array) or (tiers as Array).is_empty():
		return
	var keys: Array[float] = []
	var rows: Array = []
	for entry in tiers:
		if not (entry is Dictionary):
			continue
		var tier := float(entry.get("effective_tier", 0.0))
		var ranges: Variant = entry.get("ranges", [])
		if not (ranges is Array) or (ranges as Array).size() < 7:
			continue
		var row: Array[float] = []
		for i in 7:
			row.append(float(ranges[i]))
		keys.append(tier)
		rows.append(row)
	if keys.is_empty():
		return
	## Sort ascending by tier key for interpolation.
	var order: Array[int] = []
	for i in keys.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return keys[a] < keys[b])
	_tier_keys.clear()
	_tier_rows.clear()
	for i in order:
		_tier_keys.append(keys[i])
		_tier_rows.append(rows[i])


func apply_config(section: Dictionary) -> void:
	if section.has("recovery_per_tick"):
		recovery_per_tick = float(section.recovery_per_tick)
	if section.has("recovery_prone_per_tick"):
		recovery_prone_per_tick = float(section.recovery_prone_per_tick)
	if section.has("moderate_cover_suppression_mult"):
		moderate_cover_suppression_mult = float(section.moderate_cover_suppression_mult)
	if section.has("prone_suppression_mult"):
		prone_suppression_mult = float(section.prone_suppression_mult)
	if section.has("pinned_threshold"):
		pinned_threshold = float(section.pinned_threshold)
	if section.has("panic_threshold"):
		panic_threshold = float(section.panic_threshold)
	if section.has("band_nervous"):
		band_nervous = float(section.band_nervous)
	if section.has("band_suppressed"):
		band_suppressed = float(section.band_suppressed)
	if section.has("band_pinned"):
		band_pinned = float(section.band_pinned)
	if section.has("band_panicked"):
		band_panicked = float(section.band_panicked)
	if section.has("suppression_mg42"):
		suppression_mg42 = float(section.suppression_mg42)
	if section.has("suppression_bar"):
		suppression_bar = float(section.suppression_bar)
	if section.has("suppression_smg"):
		suppression_smg = float(section.suppression_smg)
	if section.has("suppression_default"):
		suppression_default = float(section.suppression_default)
	if section.has("max_stress"):
		max_stress = float(section.max_stress)
	if section.has("stress_base"):
		stress_base = float(section.stress_base)
	if section.has("stress_fall_multiplier"):
		stress_fall_multiplier = float(section.stress_fall_multiplier)
	if section.has("decay_reference_sec"):
		decay_reference_sec = float(section.decay_reference_sec)
	if section.has("stress_initial"):
		stress_initial = float(section.stress_initial)
	if section.has("stress_multiplier_global"):
		stress_multiplier_global = float(section.stress_multiplier_global)
	if section.has("default_experience"):
		default_experience = float(section.default_experience)
	if section.has("movement_by_band") and section.movement_by_band is Array:
		movement_by_band = _float_array(section.movement_by_band)
	if section.has("fire_delay_by_band") and section.fire_delay_by_band is Array:
		fire_delay_by_band = _float_array(section.fire_delay_by_band)
	if section.has("accuracy_by_band") and section.accuracy_by_band is Array:
		accuracy_by_band = _float_array(section.accuracy_by_band)
	if section.get("reload_accuracy_table", true):
		reload_accuracy_table()


func _float_array(raw: Array) -> Array[float]:
	var out: Array[float] = []
	for v in raw:
		out.append(float(v))
	return out


func _raw_weight(effective_tier: float, band: int) -> float:
	if _tier_keys.is_empty() or _tier_rows.is_empty():
		return 1.0
	var b := clampi(band, 0, 6)
	if effective_tier <= _tier_keys[0]:
		return float((_tier_rows[0] as Array)[b])
	if effective_tier >= _tier_keys[_tier_keys.size() - 1]:
		return float((_tier_rows[_tier_rows.size() - 1] as Array)[b])
	for i in range(_tier_keys.size() - 1):
		var lo := _tier_keys[i]
		var hi := _tier_keys[i + 1]
		if effective_tier >= lo and effective_tier <= hi:
			var t := 0.0 if is_equal_approx(hi, lo) else (effective_tier - lo) / (hi - lo)
			var a := float((_tier_rows[i] as Array)[b])
			var c := float((_tier_rows[i + 1] as Array)[b])
			return lerpf(a, c, t)
	return 1.0
