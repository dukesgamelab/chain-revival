class_name WeaponPolicy
extends RefCounted
## Weapon catalog. Recovered fields come from Initial-*.oin (identical across scenarios).
## Absolute aim/fire seconds and range_tiles / hit_modifier are TUNED, not recovered.

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

## Per-weapon definition dictionaries (clone into WeaponData on request).
var definitions: Dictionary = {}


func _init() -> void:
	reset_to_defaults()


func reset_to_defaults() -> void:
	definitions = default_definitions()


static func default_definitions() -> Dictionary:
	## Cadence note: ratio from recovered aim_factor_sqr (2000 rifles/SMGs, 7000 LMGs ~3.5x);
	## absolute seconds are TUNED, not recovered. Anchored to ~1.1s rifle aim @ 20 Hz clock.
	return {
		ID_M1_GARAND: {
			"weapon_name": "M1 Garand",
			"weapon_type": WeaponTypeClass.RIFLE,
			## TUNED engagement envelope
			"range_tiles": 18,
			"hit_modifier": 0.10,
			"close_range_bonus": 0.0,
			"close_range_tiles": 0,
			## RECOVERED
			"rounds_per_attack": 1,
			"ammo_pool": 70, ## total rounds carried; no reload in the original
			"bullet_speed": 6,
			"suppression_generated": 0.25,
			"stress_limit": 25.0,
			"stress_aim_factor": 0.5,
			"range_falloff": WeaponDataClass.FALLOFF_CUBIC,
			## TUNED cadence (aim_factor_sqr 2000)
			"aim_delay_sec": 1.1,
			"fire_interval_sec": 1.2,
		},
		ID_KAR98K: {
			"weapon_name": "Kar98k",
			"weapon_type": WeaponTypeClass.RIFLE,
			"range_tiles": 20,
			"hit_modifier": 0.14,
			"close_range_bonus": 0.0,
			"close_range_tiles": 0,
			"rounds_per_attack": 1,
			"ammo_pool": 70,
			"bullet_speed": 6,
			"suppression_generated": 0.25,
			"stress_limit": 25.0,
			"stress_aim_factor": 0.5,
			"range_falloff": WeaponDataClass.FALLOFF_CUBIC,
			"aim_delay_sec": 1.1,
			"fire_interval_sec": 1.5, ## bolt — TUNED
		},
		ID_THOMPSON: {
			"weapon_name": "Thompson",
			"weapon_type": WeaponTypeClass.SMG,
			"range_tiles": 8,
			"hit_modifier": 0.0,
			"close_range_bonus": 0.15, ## TUNED close-in feel
			"close_range_tiles": 4,
			"rounds_per_attack": 4,
			"ammo_pool": 200,
			"bullet_speed": 6,
			"suppression_generated": 2.0,
			"stress_limit": 13.0,
			"stress_aim_factor": 1.5,
			"range_falloff": WeaponDataClass.FALLOFF_PENTIC, ## RECOVERED range_const_pent 0.02
			"aim_delay_sec": 1.1,
			"fire_interval_sec": 0.8,
		},
		ID_MP40: {
			"weapon_name": "MP40",
			"weapon_type": WeaponTypeClass.SMG,
			"range_tiles": 8,
			"hit_modifier": 0.0,
			"close_range_bonus": 0.12,
			"close_range_tiles": 4,
			"rounds_per_attack": 5,
			"ammo_pool": 200,
			"bullet_speed": 6,
			"suppression_generated": 2.0,
			"stress_limit": 13.0,
			"stress_aim_factor": 1.5,
			"range_falloff": WeaponDataClass.FALLOFF_PENTIC,
			"aim_delay_sec": 1.1,
			"fire_interval_sec": 0.9,
		},
		ID_BAR: {
			"weapon_name": "BAR",
			"weapon_type": WeaponTypeClass.LMG,
			"range_tiles": 20,
			"hit_modifier": 0.05,
			"close_range_bonus": 0.0,
			"close_range_tiles": 0,
			"rounds_per_attack": 7,
			"ammo_pool": 900,
			"bullet_speed": 6,
			"suppression_generated": 0.6,
			"stress_limit": 25.0,
			"stress_aim_factor": 2.0,
			"range_falloff": WeaponDataClass.FALLOFF_CUBIC,
			"aim_delay_sec": 1.7, ## LMG ~ longer aim cycle; TUNED absolute
			"fire_interval_sec": 1.1,
		},
		ID_MG42: {
			"weapon_name": "MG42",
			"weapon_type": WeaponTypeClass.LMG,
			"range_tiles": 22,
			"hit_modifier": 0.04,
			"close_range_bonus": 0.0,
			"close_range_tiles": 0,
			"rounds_per_attack": 6,
			"ammo_pool": 900,
			"bullet_speed": 7,
			"suppression_generated": 0.6,
			"stress_limit": 25.0,
			"stress_aim_factor": 2.0,
			"range_falloff": WeaponDataClass.FALLOFF_CUBIC,
			"aim_delay_sec": 1.7,
			"fire_interval_sec": 0.6,
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
	return WeaponDataClass.new(
		weapon_id,
		str(d.get("weapon_name", weapon_id)),
		int(d.get("weapon_type", WeaponTypeClass.RIFLE)),
		int(d.get("range_tiles", 18)),
		float(d.get("hit_modifier", 0.0)),
		int(d.get("rounds_per_attack", 1)),
		ammo,
		float(d.get("close_range_bonus", 0.0)),
		int(d.get("close_range_tiles", 0)),
		float(d.get("fire_interval_sec", 0.0)),
		float(d.get("aim_delay_sec", 0.0)),
		int(d.get("bullet_speed", 6)),
		float(d.get("suppression_generated", 0.4)),
		float(d.get("stress_limit", 25.0)),
		float(d.get("stress_aim_factor", 0.5)),
		str(d.get("range_falloff", WeaponDataClass.FALLOFF_CUBIC)),
	)


func fire_interval_sec(weapon_id: String) -> float:
	var weapon := create_weapon(weapon_id)
	return weapon.fire_interval_sec if weapon != null else 0.0


func range_tiles(weapon_id: String) -> int:
	var weapon := create_weapon(weapon_id)
	return weapon.range_tiles if weapon != null else 0


func hit_modifier(weapon_id: String) -> float:
	var weapon := create_weapon(weapon_id)
	return weapon.hit_modifier if weapon != null else 0.0


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
