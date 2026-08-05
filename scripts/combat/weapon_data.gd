class_name WeaponData
extends RefCounted
## Static definition for one weapon (separate from soldier/combat logic).

const WeaponTypeClass := preload("res://scripts/enums/weapon_type.gd")

const FALLOFF_CUBIC := "cubic"
const FALLOFF_PENTIC := "pentic"

var weapon_id: String = ""
var weapon_name: String = ""
var weapon_type: int = WeaponTypeClass.RIFLE
var range_tiles: int = 18
var hit_modifier: float = 0.0
var close_range_bonus: float = 0.0
var close_range_tiles: int = 0
var rounds_per_attack: int = 1
## Starting carried ammo (ammo_pool / AmmoMax in original). NOT a hard cap —
## Ammunition Boxes add another starting load on top and can be stacked.
var ammo_capacity: int = 200
## Burst visual count; defaults to rounds_per_attack in _init.
var tracer_count: int = 1
## First-shot target acquisition time; target changes restart aiming via begin_fire_prep().
## Absolute seconds are TUNED; ratio tracks recovered aim_factor_sqr.
var aim_delay_sec: float = 0.0
## Repeat shot/burst cadence after the first aimed shot (last_shot_msec + this value).
## Absolute seconds are TUNED, not recovered.
var fire_interval_sec: float = 0.0
## RECOVERED BulletSpeed$weapon.
var bullet_speed: int = 6
## RECOVERED StressFactor$weapon — per-tile stress factor in the range-scaled gain formula.
var suppression_generated: float = 0.4
## RECOVERED StressLimit$weapon — range cutoff in tiles; no suppression at range >= this.
var stress_limit_tiles: float = 25.0
## TUNED per-weapon stress cap input (mapped via STRESS_LIMIT_REF). Not the OG range cutoff.
var stress_limit: float = 25.0
## RECOVERED stress_aim_factor$weapon — scales how hard the shooter's stress degrades their aim.
var stress_aim_factor: float = 0.5
## RECOVERED range_const_cub / range_const_pent selector: "cubic" | "pentic".
var range_falloff: String = FALLOFF_CUBIC


func _init(
	p_weapon_id: String = "",
	p_weapon_name: String = "",
	p_weapon_type: int = WeaponTypeClass.RIFLE,
	p_range_tiles: int = 18,
	p_hit_modifier: float = 0.0,
	p_rounds_per_attack: int = 1,
	p_ammo_capacity: int = 200,
	p_close_range_bonus: float = 0.0,
	p_close_range_tiles: int = 0,
	p_fire_interval_sec: float = 0.0,
	p_aim_delay_sec: float = 0.0,
	p_bullet_speed: int = 6,
	p_suppression_generated: float = 0.4,
	p_stress_limit: float = 25.0,
	p_stress_aim_factor: float = 0.5,
	p_range_falloff: String = FALLOFF_CUBIC,
	p_stress_limit_tiles: float = -1.0,
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
	bullet_speed = p_bullet_speed
	suppression_generated = p_suppression_generated
	stress_limit = p_stress_limit
	## Default tiles cutoff to the recovered StressLimit value when not passed separately.
	stress_limit_tiles = p_stress_limit if p_stress_limit_tiles < 0.0 else p_stress_limit_tiles
	stress_aim_factor = p_stress_aim_factor
	range_falloff = p_range_falloff


func is_burst() -> bool:
	return rounds_per_attack > 1


## Ammo spent per attack; capped by remaining ammo.
func ammo_cost(available: int) -> int:
	return mini(rounds_per_attack, available)


## Hit modifier including optional SMG close-range bonus (TUNED, not recovered).
func effective_hit_modifier(distance_tiles: int) -> float:
	var modifier := hit_modifier
	if close_range_bonus > 0.0 and distance_tiles <= close_range_tiles:
		modifier += close_range_bonus
	return modifier


## Extra hit-chance penalty from recovered range_const_cub / range_const_pent.
## Cubic (rifles/LMGs): gentle long-range loss. Pentic 0.02 (SMGs): steep drop-off.
func range_falloff_penalty(distance_tiles: int) -> float:
	var d := float(maxi(distance_tiles, 0))
	match range_falloff:
		FALLOFF_PENTIC:
			## RECOVERED range_const_pent$weapon = 0.02
			return 0.02 * pow(d / 6.0, 5.0)
		FALLOFF_CUBIC:
			## RECOVERED range_const_cub$weapon = 1 — accurate at distance vs pentic
			return pow(d / 28.0, 3.0)
		_:
			return 0.0
