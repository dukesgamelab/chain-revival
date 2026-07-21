class_name WeaponPolicy
extends RefCounted
## Weapon catalog tuning. Defaults match the former WeaponRegistry table.
## Gameplay asks: "What is the rifle cooldown / range / accuracy?"

const WeaponDataClass := preload("res://scripts/combat/weapon_data.gd")
const WeaponTypeClass := preload("res://scripts/enums/weapon_type.gd")

const ID_M1_GARAND := "m1_garand"
const ID_BAR := "bar"
const ID_THOMPSON := "thompson"
const ID_KAR98K := "kar98k"
const ID_MG42 := "mg42"
const ID_MP40 := "mp40"

## Per-weapon definition dictionaries (tunable; clone into WeaponData on request).
var definitions: Dictionary = {}


func _init() -> void:
	reset_to_defaults()


func reset_to_defaults() -> void:
	definitions = default_definitions()


static func default_definitions() -> Dictionary:
	return {
		ID_M1_GARAND: _def("M1 Garand", WeaponTypeClass.RIFLE, 18, 0.10, 1, 80, 0.0, 0, 1.2, 1.1),
		ID_BAR: _def("BAR", WeaponTypeClass.LMG, 20, 0.05, 4, 120, 0.0, 0, 1.1, 0.9),
		ID_THOMPSON: _def("Thompson", WeaponTypeClass.SMG, 8, 0.0, 3, 100, 0.15, 4, 0.8, 0.7),
		ID_KAR98K: _def("Kar98k", WeaponTypeClass.RIFLE, 20, 0.14, 1, 60, 0.0, 0, 2.0, 1.3),
		ID_MG42: _def("MG42", WeaponTypeClass.LMG, 22, 0.04, 6, 150, 0.0, 0, 0.6, 1.0),
		ID_MP40: _def("MP40", WeaponTypeClass.SMG, 8, 0.0, 3, 100, 0.12, 4, 0.9, 0.7),
	}


static func _def(
	weapon_name: String,
	weapon_type: int,
	range_tiles: int,
	hit_modifier: float,
	rounds_per_attack: int,
	ammo_capacity: int,
	close_range_bonus: float,
	close_range_tiles: int,
	fire_interval_sec: float,
	aim_delay_sec: float,
) -> Dictionary:
	return {
		"weapon_name": weapon_name,
		"weapon_type": weapon_type,
		"range_tiles": range_tiles,
		"hit_modifier": hit_modifier,
		"rounds_per_attack": rounds_per_attack,
		"ammo_capacity": ammo_capacity,
		"close_range_bonus": close_range_bonus,
		"close_range_tiles": close_range_tiles,
		"fire_interval_sec": fire_interval_sec,
		"aim_delay_sec": aim_delay_sec,
	}


func has_weapon(weapon_id: String) -> bool:
	return definitions.has(weapon_id)


func create_weapon(weapon_id: String) -> WeaponDataClass:
	if not definitions.has(weapon_id):
		return null
	var d: Dictionary = definitions[weapon_id]
	return WeaponDataClass.new(
		weapon_id,
		str(d.get("weapon_name", weapon_id)),
		int(d.get("weapon_type", WeaponTypeClass.RIFLE)),
		int(d.get("range_tiles", 18)),
		float(d.get("hit_modifier", 0.0)),
		int(d.get("rounds_per_attack", 1)),
		int(d.get("ammo_capacity", 200)),
		float(d.get("close_range_bonus", 0.0)),
		int(d.get("close_range_tiles", 0)),
		float(d.get("fire_interval_sec", 0.0)),
		float(d.get("aim_delay_sec", 0.0)),
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
