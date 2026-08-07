class_name WeaponPolicy
extends RefCounted
## Weapon catalog. Recovered fields come from Initial-*.oin (identical across scenarios).
## Hit chance uses aim_factor_sqr / range_const_* (Stage 5). range_tiles is engagement only.

const WeaponDataClass := preload("res://scripts/combat/weapon_data.gd")
const WeaponTypeClass := preload("res://scripts/enums/weapon_type.gd")

const ID_M1_GARAND := "m1_garand"
const ID_BAR := "bar"
const ID_THOMPSON := "thompson"
const ID_KAR98K := "kar98k"
const ID_MG42 := "mg42"
const ID_MP40 := "mp40"

## RECOVERED INIT_LimitPerSquad. -1 = unlimited (rifles).
const SQUAD_LIMIT_BAR := 1
const SQUAD_LIMIT_THOMPSON := 2
const SQUAD_LIMIT_MG42 := 1
const SQUAD_LIMIT_MP40 := 2
const SQUAD_LIMIT_UNLIMITED := -1

## Generous cone / out-of-range envelope. Hit falloff is the polynomial, not this.
const ENGAGEMENT_RANGE_TILES := 40

## Per-weapon definition dictionaries (clone into WeaponData on request).
var definitions: Dictionary = {}


func _init() -> void:
	reset_to_defaults()


func reset_to_defaults() -> void:
	definitions = default_definitions()


static func default_definitions() -> Dictionary:
	return {
		ID_M1_GARAND: {
			"weapon_name": "M1 Garand",
			"weapon_type": WeaponTypeClass.RIFLE,
			"range_tiles": ENGAGEMENT_RANGE_TILES,
			## RECOVERED hit polynomial
			"aim_factor_sqr": 2000.0,
			"range_const_cub": 1.0,
			"range_const_pent": 0.0,
			"rounds_per_attack": 1,
			"ammo_pool": 70, ## total rounds carried; no reload in the original
			"bullet_speed": 6,
			"suppression_generated": 0.25, ## RECOVERED StressFactor
			"stress_limit_tiles": 25.0, ## RECOVERED StressLimit — range cutoff
			"stress_limit": 25.0, ## TUNED cap mapping input (separate from tiles cutoff)
			"stress_aim_factor": 0.5,
			## Cadence: 0 = HitChancePolicy.base_fire_cycle_sec (global ~5.5s).
			"aim_delay_sec": 0.0,
			"fire_interval_sec": 0.0,
		},
		ID_KAR98K: {
			"weapon_name": "Kar98k",
			"weapon_type": WeaponTypeClass.RIFLE,
			"range_tiles": ENGAGEMENT_RANGE_TILES,
			"aim_factor_sqr": 2000.0,
			"range_const_cub": 1.0,
			"range_const_pent": 0.0,
			"rounds_per_attack": 1,
			"ammo_pool": 70,
			"bullet_speed": 6,
			"suppression_generated": 0.25,
			"stress_limit_tiles": 25.0, ## RECOVERED
			"stress_limit": 25.0, ## TUNED cap mapping
			"stress_aim_factor": 0.5,
			"aim_delay_sec": 0.0,
			"fire_interval_sec": 0.0,
		},
		ID_THOMPSON: {
			"weapon_name": "Thompson",
			"weapon_type": WeaponTypeClass.SMG,
			"range_tiles": ENGAGEMENT_RANGE_TILES,
			"aim_factor_sqr": 2000.0,
			"range_const_cub": 0.0,
			"range_const_pent": 0.02, ## RECOVERED — SMG cliff via D⁵
			"rounds_per_attack": 4,
			"ammo_pool": 200,
			"bullet_speed": 6,
			"suppression_generated": 2.0,
			"stress_limit_tiles": 13.0, ## RECOVERED
			"stress_limit": 13.0, ## TUNED cap mapping
			"stress_aim_factor": 1.5,
			"aim_delay_sec": 0.0,
			"fire_interval_sec": 0.0,
		},
		ID_MP40: {
			"weapon_name": "MP40",
			"weapon_type": WeaponTypeClass.SMG,
			"range_tiles": ENGAGEMENT_RANGE_TILES,
			"aim_factor_sqr": 2000.0,
			"range_const_cub": 0.0,
			"range_const_pent": 0.02,
			"rounds_per_attack": 5,
			"ammo_pool": 200,
			"bullet_speed": 6,
			"suppression_generated": 2.0,
			"stress_limit_tiles": 13.0, ## RECOVERED
			"stress_limit": 13.0, ## TUNED cap mapping
			"stress_aim_factor": 1.5,
			"aim_delay_sec": 0.0,
			"fire_interval_sec": 0.0,
		},
		ID_BAR: {
			"weapon_name": "BAR",
			"weapon_type": WeaponTypeClass.LMG,
			"range_tiles": ENGAGEMENT_RANGE_TILES,
			## RECOVERED aim_factor_sqr 8000 — 4× rifle accuracy (numerator), not slower aim.
			"aim_factor_sqr": 8000.0,
			"range_const_cub": 1.0,
			"range_const_pent": 0.0,
			"rounds_per_attack": 7,
			"ammo_pool": 900,
			"bullet_speed": 6,
			"suppression_generated": 0.6,
			"stress_limit_tiles": 25.0, ## RECOVERED
			"stress_limit": 25.0, ## TUNED cap mapping
			"stress_aim_factor": 2.0,
			"aim_delay_sec": 0.0,
			"fire_interval_sec": 0.0,
		},
		ID_MG42: {
			"weapon_name": "MG42",
			"weapon_type": WeaponTypeClass.LMG,
			"range_tiles": ENGAGEMENT_RANGE_TILES,
			"aim_factor_sqr": 8000.0,
			"range_const_cub": 1.0,
			"range_const_pent": 0.0,
			"rounds_per_attack": 6,
			"ammo_pool": 900,
			"bullet_speed": 7,
			"suppression_generated": 0.6,
			"stress_limit_tiles": 25.0, ## RECOVERED
			"stress_limit": 25.0, ## TUNED cap mapping
			"stress_aim_factor": 2.0,
			"aim_delay_sec": 0.0,
			"fire_interval_sec": 0.0,
		},
	}


## RECOVERED INIT_LimitPerSquad for a future loadout system. Rifles unlimited.
static func squad_limit(weapon_id: String) -> int:
	match weapon_id:
		ID_BAR:
			return SQUAD_LIMIT_BAR
		ID_THOMPSON:
			return SQUAD_LIMIT_THOMPSON
		ID_MG42:
			return SQUAD_LIMIT_MG42
		ID_MP40:
			return SQUAD_LIMIT_MP40
		ID_M1_GARAND, ID_KAR98K:
			return SQUAD_LIMIT_UNLIMITED
		_:
			return SQUAD_LIMIT_UNLIMITED


func has_weapon(weapon_id: String) -> bool:
	return definitions.has(weapon_id)


func create_weapon(weapon_id: String) -> WeaponDataClass:
	if not definitions.has(weapon_id):
		return null
	var d: Dictionary = definitions[weapon_id]
	## ammo_pool is the recovered name; ammo_capacity kept as legacy JSON key.
	var ammo := int(d.get("ammo_pool", d.get("ammo_capacity", 200)))
	var stress_limit := float(d.get("stress_limit", 25.0))
	var stress_limit_tiles := float(d.get("stress_limit_tiles", stress_limit))
	var weapon := WeaponDataClass.new(
		weapon_id,
		str(d.get("weapon_name", weapon_id)),
		int(d.get("weapon_type", WeaponTypeClass.RIFLE)),
		int(d.get("range_tiles", ENGAGEMENT_RANGE_TILES)),
		0.0,
		int(d.get("rounds_per_attack", 1)),
		ammo,
		0.0,
		0,
		float(d.get("fire_interval_sec", 0.0)),
		float(d.get("aim_delay_sec", 0.0)),
		int(d.get("bullet_speed", 6)),
		float(d.get("suppression_generated", 0.4)),
		stress_limit,
		float(d.get("stress_aim_factor", 0.5)),
		"",
		stress_limit_tiles,
	)
	weapon.aim_factor_sqr = float(d.get("aim_factor_sqr", weapon.aim_factor_sqr))
	weapon.aim_factor = float(d.get("aim_factor", 0.0))
	weapon.aim_plus = float(d.get("aim_plus", 0.0))
	weapon.range_const_cub = float(d.get("range_const_cub", weapon.range_const_cub))
	weapon.range_const_sqr = float(d.get("range_const_sqr", 0.0))
	weapon.range_const_pent = float(d.get("range_const_pent", weapon.range_const_pent))
	return weapon


func fire_interval_sec(weapon_id: String) -> float:
	## Effective cycle: per-weapon override, else global base_fire_cycle_sec.
	var weapon := create_weapon(weapon_id)
	if weapon == null:
		return 0.0
	if weapon.fire_interval_sec > 0.0:
		return weapon.fire_interval_sec
	return GameplayPolicies.hit.base_fire_cycle_sec


func range_tiles(weapon_id: String) -> int:
	var weapon := create_weapon(weapon_id)
	return weapon.range_tiles if weapon != null else 0


func hit_modifier(weapon_id: String) -> float:
	## Deprecated — polynomial replaced additive hit_modifier.
	return 0.0


func apply_config(section: Dictionary) -> void:
	if section.is_empty():
		return
	var weapons: Variant = section.get("definitions", section)
	if not (weapons is Dictionary):
		return
	for weapon_id in weapons.keys():
		var entry: Variant = weapons[weapon_id]
		if not (entry is Dictionary):
			continue
		var merged: Dictionary = (
			definitions.get(str(weapon_id), {}).duplicate(true)
			if definitions.has(str(weapon_id))
			else {}
		)
		for key in entry.keys():
			merged[str(key)] = entry[key]
		definitions[str(weapon_id)] = merged
