class_name SuppressionPolicy
extends RefCounted
## Configurable suppression / stress values. Defaults match current CombatSystem.

const DEFAULT_RECOVERY_PER_TICK := 0.15
const DEFAULT_RECOVERY_PRONE_PER_TICK := 0.25
const DEFAULT_MODERATE_COVER_SUPPRESSION_MULT := 0.65
const DEFAULT_PRONE_SUPPRESSION_MULT := 0.75
const DEFAULT_PINNED_THRESHOLD := 45.0
const DEFAULT_PANIC_THRESHOLD := 70.0
const DEFAULT_BAND_NERVOUS := 10.0
const DEFAULT_BAND_SUPPRESSED := 25.0
const DEFAULT_BAND_PINNED := 45.0
const DEFAULT_BAND_PANICKED := 70.0

## Per-band accuracy multipliers (index = stress band 0..4).
const DEFAULT_ACCURACY_BY_BAND: Array[float] = [1.0, 0.85, 0.65, 0.4, 0.2]
## Per-band movement multipliers.
const DEFAULT_MOVEMENT_BY_BAND: Array[float] = [1.0, 0.9, 0.75, 0.5, 0.35]
## Per-band fire-delay multipliers.
const DEFAULT_FIRE_DELAY_BY_BAND: Array[float] = [1.0, 1.1, 1.25, 1.5, 2.0]

const DEFAULT_SUPPRESSION_MG42 := 2.0
const DEFAULT_SUPPRESSION_BAR := 1.2
const DEFAULT_SUPPRESSION_SMG := 0.8
const DEFAULT_SUPPRESSION_DEFAULT := 0.4
const DEFAULT_MAX_STRESS := 100.0

var recovery_per_tick: float = DEFAULT_RECOVERY_PER_TICK
var recovery_prone_per_tick: float = DEFAULT_RECOVERY_PRONE_PER_TICK
var moderate_cover_suppression_mult: float = DEFAULT_MODERATE_COVER_SUPPRESSION_MULT
var prone_suppression_mult: float = DEFAULT_PRONE_SUPPRESSION_MULT
var pinned_threshold: float = DEFAULT_PINNED_THRESHOLD
var panic_threshold: float = DEFAULT_PANIC_THRESHOLD
var band_nervous: float = DEFAULT_BAND_NERVOUS
var band_suppressed: float = DEFAULT_BAND_SUPPRESSED
var band_pinned: float = DEFAULT_BAND_PINNED
var band_panicked: float = DEFAULT_BAND_PANICKED
var accuracy_by_band: Array[float] = DEFAULT_ACCURACY_BY_BAND.duplicate()
var movement_by_band: Array[float] = DEFAULT_MOVEMENT_BY_BAND.duplicate()
var fire_delay_by_band: Array[float] = DEFAULT_FIRE_DELAY_BY_BAND.duplicate()
var suppression_mg42: float = DEFAULT_SUPPRESSION_MG42
var suppression_bar: float = DEFAULT_SUPPRESSION_BAR
var suppression_smg: float = DEFAULT_SUPPRESSION_SMG
var suppression_default: float = DEFAULT_SUPPRESSION_DEFAULT
var max_stress: float = DEFAULT_MAX_STRESS


func reset_to_defaults() -> void:
	recovery_per_tick = DEFAULT_RECOVERY_PER_TICK
	recovery_prone_per_tick = DEFAULT_RECOVERY_PRONE_PER_TICK
	moderate_cover_suppression_mult = DEFAULT_MODERATE_COVER_SUPPRESSION_MULT
	prone_suppression_mult = DEFAULT_PRONE_SUPPRESSION_MULT
	pinned_threshold = DEFAULT_PINNED_THRESHOLD
	panic_threshold = DEFAULT_PANIC_THRESHOLD
	band_nervous = DEFAULT_BAND_NERVOUS
	band_suppressed = DEFAULT_BAND_SUPPRESSED
	band_pinned = DEFAULT_BAND_PINNED
	band_panicked = DEFAULT_BAND_PANICKED
	accuracy_by_band = DEFAULT_ACCURACY_BY_BAND.duplicate()
	movement_by_band = DEFAULT_MOVEMENT_BY_BAND.duplicate()
	fire_delay_by_band = DEFAULT_FIRE_DELAY_BY_BAND.duplicate()
	suppression_mg42 = DEFAULT_SUPPRESSION_MG42
	suppression_bar = DEFAULT_SUPPRESSION_BAR
	suppression_smg = DEFAULT_SUPPRESSION_SMG
	suppression_default = DEFAULT_SUPPRESSION_DEFAULT
	max_stress = DEFAULT_MAX_STRESS


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
	if section.has("accuracy_by_band") and section.accuracy_by_band is Array:
		accuracy_by_band = _float_array(section.accuracy_by_band)
	if section.has("movement_by_band") and section.movement_by_band is Array:
		movement_by_band = _float_array(section.movement_by_band)
	if section.has("fire_delay_by_band") and section.fire_delay_by_band is Array:
		fire_delay_by_band = _float_array(section.fire_delay_by_band)


func _float_array(raw: Array) -> Array[float]:
	var out: Array[float] = []
	for v in raw:
		out.append(float(v))
	return out


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


func accuracy_modifier(stress: float) -> float:
	var band := stress_band(stress)
	if band < 0 or band >= accuracy_by_band.size():
		return 1.0
	return accuracy_by_band[band]


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
