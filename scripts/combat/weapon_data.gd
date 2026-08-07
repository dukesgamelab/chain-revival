class_name WeaponData
extends RefCounted
## Static definition for one weapon (separate from soldier/combat logic).

const WeaponTypeClass := preload("res://scripts/enums/weapon_type.gd")

var weapon_id: String = ""
var weapon_name: String = ""
var weapon_type: int = WeaponTypeClass.RIFLE
## Generous engagement / cone envelope only — does not shape hit chance.
var range_tiles: int = 40
var rounds_per_attack: int = 1
## Starting carried ammo (ammo_pool / AmmoMax in original). NOT a hard cap —
## Ammunition Boxes add another starting load on top and can be stacked.
var ammo_capacity: int = 200
## Burst visual count; defaults to rounds_per_attack in _init.
var tracer_count: int = 1
## Unused for cadence (OG Aiming *is* the fire cycle). Kept for experiments only.
var aim_delay_sec: float = 0.0
## Per-weapon fire-cycle override. 0 = use HitChancePolicy.base_fire_cycle_sec (~5.5s).
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

## --- Hit polynomial (RECOVERED) ---
## HitFinal ∝ (aim_factor_sqr·AimTime² + aim_factor·AimTime + aim_plus)
##            / (cub·D³ + sqr·D² + pent·D⁵)
var aim_factor_sqr: float = 2000.0
var aim_factor: float = 0.0
var aim_plus: float = 0.0
var range_const_cub: float = 1.0
var range_const_sqr: float = 0.0
var range_const_pent: float = 0.0


func _init(
	p_weapon_id: String = "",
	p_weapon_name: String = "",
	p_weapon_type: int = WeaponTypeClass.RIFLE,
	p_range_tiles: int = 40,
	_p_hit_modifier: float = 0.0,
	p_rounds_per_attack: int = 1,
	p_ammo_capacity: int = 200,
	_p_close_range_bonus: float = 0.0,
	_p_close_range_tiles: int = 0,
	p_fire_interval_sec: float = 0.0,
	p_aim_delay_sec: float = 0.0,
	p_bullet_speed: int = 6,
	p_suppression_generated: float = 0.4,
	p_stress_limit: float = 25.0,
	p_stress_aim_factor: float = 0.5,
	_p_range_falloff: String = "",
	p_stress_limit_tiles: float = -1.0,
) -> void:
	weapon_id = p_weapon_id
	weapon_name = p_weapon_name
	weapon_type = p_weapon_type
	range_tiles = p_range_tiles
	rounds_per_attack = p_rounds_per_attack
	ammo_capacity = p_ammo_capacity
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


func is_burst() -> bool:
	return rounds_per_attack > 1


## Ammo spent per attack; capped by remaining ammo.
func ammo_cost(available: int) -> int:
	return mini(rounds_per_attack, available)


## Quotient denominator for combat range D (already MarksMan-adjusted).
func hit_denominator(d: float) -> float:
	var d2 := d * d
	var d3 := d2 * d
	var d5 := d3 * d2
	return range_const_cub * d3 + range_const_sqr * d2 + range_const_pent * d5


## Quotient numerator for a fixed AimTime (Exp-Str tables wire later).
func hit_numerator(aim_time: float) -> float:
	return (
		aim_factor_sqr * aim_time * aim_time
		+ aim_factor * aim_time
		+ aim_plus
	)
