class_name WeaponData
extends RefCounted
## Static definition for one weapon (separate from soldier/combat logic).

const WeaponTypeClass := preload("res://scripts/weapon_type.gd")

var weapon_id: String = ""
var weapon_name: String = ""
var weapon_type: int = WeaponTypeClass.RIFLE
var range_tiles: int = 18
var hit_modifier: float = 0.0
var close_range_bonus: float = 0.0
var close_range_tiles: int = 0
var rounds_per_attack: int = 1
var ammo_capacity: int = 200
## Burst visual count; defaults to rounds_per_attack in _init.
var tracer_count: int = 1
## First-shot target acquisition time; target changes restart aiming via begin_fire_prep().
var aim_delay_sec: float = 0.0
## Repeat shot/burst cadence after the first aimed shot (last_shot_msec + this value).
var fire_interval_sec: float = 0.0


func _init(
	p_weapon_id: String,
	p_weapon_name: String,
	p_weapon_type: int,
	p_range_tiles: int,
	p_hit_modifier: float,
	p_rounds_per_attack: int,
	p_ammo_capacity: int,
	p_close_range_bonus: float = 0.0,
	p_close_range_tiles: int = 0,
	p_fire_interval_sec: float = 0.0,
	p_aim_delay_sec: float = 0.0,
) -> void:
	weapon_id = p_weapon_id
	weapon_name = p_weapon_name
	weapon_type = p_weapon_type
	range_tiles = p_range_tiles
	hit_modifier = p_hit_modifier
	rounds_per_attack = p_rounds_per_attack
	ammo_capacity = p_ammo_capacity
	close_range_bonus = p_close_range_bonus
	close_range_tiles = p_close_range_tiles
	# rounds_per_attack = burst size, ammo cost per attack, and tracer count (V1).
	tracer_count = p_rounds_per_attack
	fire_interval_sec = p_fire_interval_sec
	aim_delay_sec = p_aim_delay_sec


func is_burst() -> bool:
	return rounds_per_attack > 1


## Ammo spent per attack; capped by remaining ammo.
func ammo_cost(available: int) -> int:
	return mini(rounds_per_attack, available)


## Hit modifier including optional SMG close-range bonus.
func effective_hit_modifier(distance_tiles: int) -> float:
	var modifier := hit_modifier
	if close_range_bonus > 0.0 and distance_tiles <= close_range_tiles:
		modifier += close_range_bonus
	return modifier
