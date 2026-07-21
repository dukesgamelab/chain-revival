class_name GrenadePolicy
extends RefCounted
## Configurable grenade values. Defaults match current CombatSystem / SoldierState.

const DEFAULT_STARTING_COUNT := 5
const DEFAULT_THROW_RANGE := 7
const DEFAULT_FUSE_MSEC := 1800
const DEFAULT_BLAST_RADIUS := 3
const DEFAULT_KILL_RADIUS := 1
const DEFAULT_KILL_CHANCE := 0.25
const DEFAULT_STUN_DURATION_SEC := 8.0

var starting_count: int = DEFAULT_STARTING_COUNT
var throw_range: int = DEFAULT_THROW_RANGE
var fuse_msec: int = DEFAULT_FUSE_MSEC
var blast_radius: int = DEFAULT_BLAST_RADIUS
var kill_radius: int = DEFAULT_KILL_RADIUS
var kill_chance: float = DEFAULT_KILL_CHANCE
var stun_duration_sec: float = DEFAULT_STUN_DURATION_SEC


func reset_to_defaults() -> void:
	starting_count = DEFAULT_STARTING_COUNT
	throw_range = DEFAULT_THROW_RANGE
	fuse_msec = DEFAULT_FUSE_MSEC
	blast_radius = DEFAULT_BLAST_RADIUS
	kill_radius = DEFAULT_KILL_RADIUS
	kill_chance = DEFAULT_KILL_CHANCE
	stun_duration_sec = DEFAULT_STUN_DURATION_SEC
