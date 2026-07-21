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
## 0-based frame index into A–X throw sequence; -1 disables anim-driven release.
## Gameplay fuse still arms on command accept until a release frame is visually verified.
const DEFAULT_THROW_RELEASE_FRAME_USA := -1
const DEFAULT_THROW_RELEASE_FRAME_GERMANY := -1
const DEFAULT_THROW_ANIM_FPS := 8.0

var starting_count: int = DEFAULT_STARTING_COUNT
var throw_range: int = DEFAULT_THROW_RANGE
var fuse_msec: int = DEFAULT_FUSE_MSEC
var blast_radius: int = DEFAULT_BLAST_RADIUS
var kill_radius: int = DEFAULT_KILL_RADIUS
var kill_chance: float = DEFAULT_KILL_CHANCE
var stun_duration_sec: float = DEFAULT_STUN_DURATION_SEC
var throw_release_frame_usa: int = DEFAULT_THROW_RELEASE_FRAME_USA
var throw_release_frame_germany: int = DEFAULT_THROW_RELEASE_FRAME_GERMANY
var throw_anim_fps: float = DEFAULT_THROW_ANIM_FPS


func reset_to_defaults() -> void:
	starting_count = DEFAULT_STARTING_COUNT
	throw_range = DEFAULT_THROW_RANGE
	fuse_msec = DEFAULT_FUSE_MSEC
	blast_radius = DEFAULT_BLAST_RADIUS
	kill_radius = DEFAULT_KILL_RADIUS
	kill_chance = DEFAULT_KILL_CHANCE
	stun_duration_sec = DEFAULT_STUN_DURATION_SEC
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


func apply_config(section: Dictionary) -> void:
	if section.has("starting_count"):
		starting_count = int(section.starting_count)
	if section.has("throw_range"):
		throw_range = int(section.throw_range)
	if section.has("fuse_msec"):
		fuse_msec = int(section.fuse_msec)
	if section.has("blast_radius"):
		blast_radius = int(section.blast_radius)
	if section.has("kill_radius"):
		kill_radius = int(section.kill_radius)
	if section.has("kill_chance"):
		kill_chance = float(section.kill_chance)
	if section.has("stun_duration_sec"):
		stun_duration_sec = float(section.stun_duration_sec)
	if section.has("throw_release_frame_usa"):
		throw_release_frame_usa = int(section.throw_release_frame_usa)
	if section.has("throw_release_frame_germany"):
		throw_release_frame_germany = int(section.throw_release_frame_germany)
	if section.has("throw_anim_fps"):
		throw_anim_fps = float(section.throw_anim_fps)
