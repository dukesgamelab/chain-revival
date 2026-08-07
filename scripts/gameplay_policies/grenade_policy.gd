class_name GrenadePolicy
extends RefCounted
## Configurable grenade values.
## RECOVERED: starting_count (ArmamentGranade=5), throw_range (INITMaxGranadeDistance=5),
## hit_distance (GranadeHitDistance=2), VarA/B/C/D blast model.
## TUNED: fuse_msec; distance_denom_min (divide-by-zero guard).

const WeaponPolicyClass := preload("res://scripts/gameplay_policies/weapon_policy.gd")

const DEFAULT_STARTING_COUNT := 5 ## RECOVERED ArmamentGranade
const DEFAULT_THROW_RANGE := 5 ## RECOVERED INITMaxGranadeDistance
const DEFAULT_HIT_DISTANCE := 2.0 ## RECOVERED GranadeHitDistance (tiles, Euclidean)
const DEFAULT_FUSE_MSEC := 1800 ## TUNED
## RECOVERED blast model — also mirrored on WeaponPolicy grenade entry.
const DEFAULT_VAR_A := WeaponPolicyClass.GRENADE_VAR_A
const DEFAULT_VAR_B := WeaponPolicyClass.GRENADE_VAR_B
const DEFAULT_VAR_C := WeaponPolicyClass.GRENADE_VAR_C
const DEFAULT_VAR_D := WeaponPolicyClass.GRENADE_VAR_D
## TUNED — clamps (distance + VarB) so a direct hit never divides by zero.
## With VarA=30 this caps casualty at 60% (30 / 0.5), matching the recovered 0.5-tile row.
const DEFAULT_DISTANCE_DENOM_MIN := 0.5
## 0-based frame index into A–X throw sequence; -1 disables anim-driven release.
## Gameplay fuse still arms on command accept until a release frame is visually verified.
const DEFAULT_THROW_RELEASE_FRAME_USA := -1
const DEFAULT_THROW_RELEASE_FRAME_GERMANY := -1
const DEFAULT_THROW_ANIM_FPS := 8.0

var starting_count: int = DEFAULT_STARTING_COUNT
var throw_range: int = DEFAULT_THROW_RANGE
var hit_distance: float = DEFAULT_HIT_DISTANCE
var fuse_msec: int = DEFAULT_FUSE_MSEC
var var_a: float = DEFAULT_VAR_A ## RECOVERED casualty numerator
var var_b: float = DEFAULT_VAR_B ## RECOVERED casualty distance offset
var var_c: float = DEFAULT_VAR_C ## RECOVERED stun numerator
var var_d: float = DEFAULT_VAR_D ## RECOVERED stun distance offset
var distance_denom_min: float = DEFAULT_DISTANCE_DENOM_MIN ## TUNED
var throw_release_frame_usa: int = DEFAULT_THROW_RELEASE_FRAME_USA
var throw_release_frame_germany: int = DEFAULT_THROW_RELEASE_FRAME_GERMANY
var throw_anim_fps: float = DEFAULT_THROW_ANIM_FPS


func reset_to_defaults() -> void:
	starting_count = DEFAULT_STARTING_COUNT
	throw_range = DEFAULT_THROW_RANGE
	hit_distance = DEFAULT_HIT_DISTANCE
	fuse_msec = DEFAULT_FUSE_MSEC
	var_a = DEFAULT_VAR_A
	var_b = DEFAULT_VAR_B
	var_c = DEFAULT_VAR_C
	var_d = DEFAULT_VAR_D
	distance_denom_min = DEFAULT_DISTANCE_DENOM_MIN
	throw_release_frame_usa = DEFAULT_THROW_RELEASE_FRAME_USA
	throw_release_frame_germany = DEFAULT_THROW_RELEASE_FRAME_GERMANY
	throw_anim_fps = DEFAULT_THROW_ANIM_FPS


## Anim-driven release frame for a faction, or -1 if disabled (presentation-only throw).
func throw_release_frame_for_team(team_id: int) -> int:
	if team_id == Team.GERMANY:
		return throw_release_frame_germany
	return throw_release_frame_usa


func is_throw_release_enabled_for_team(team_id: int) -> bool:
	return throw_release_frame_for_team(team_id) >= 0


## P(casualty) before lethality, as 0–1. AuxDecimal = VarA / (d + VarB) vs rand 0–100.
func casualty_chance_at_distance(distance: float) -> float:
	var denom := maxf(float(distance) + var_b, distance_denom_min)
	var pct := var_a / denom
	return clampf(pct / 100.0, 0.0, 1.0)


## Stun duration in seconds — every survivor, no roll. VarC / (d + VarD).
func stun_duration_at_distance(distance: float) -> float:
	var denom := maxf(float(distance) + var_d, distance_denom_min)
	return maxf(var_c / denom, 0.0)


func apply_config(section: Dictionary) -> void:
	if section.has("starting_count"):
		starting_count = int(section.starting_count)
	if section.has("throw_range"):
		throw_range = int(section.throw_range)
	if section.has("hit_distance"):
		hit_distance = float(section.hit_distance)
	elif section.has("blast_radius"):
		## Legacy key — treat as hit distance (tiles).
		hit_distance = float(section.blast_radius)
	if section.has("fuse_msec"):
		fuse_msec = int(section.fuse_msec)
	if section.has("var_a"):
		var_a = float(section.var_a)
	if section.has("var_b"):
		var_b = float(section.var_b)
	if section.has("var_c"):
		var_c = float(section.var_c)
	if section.has("var_d"):
		var_d = float(section.var_d)
	if section.has("distance_denom_min"):
		distance_denom_min = float(section.distance_denom_min)
	if section.has("throw_release_frame_usa"):
		throw_release_frame_usa = int(section.throw_release_frame_usa)
	if section.has("throw_release_frame_germany"):
		throw_release_frame_germany = int(section.throw_release_frame_germany)
	if section.has("throw_anim_fps"):
		throw_anim_fps = float(section.throw_anim_fps)
