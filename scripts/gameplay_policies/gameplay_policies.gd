extends Node
## Autoload facade for gameplay policy instances.
##
## Access:
##   GameplayPolicies.hit / .grenade / .suppression / .movement
##   GameplayPolicies.weapons / .vision / .cover / .los / .fire_anim / .idle_anim
##
## Defaults preserve current CombatSystem / MovementMode numbers.
## Optional overrides: res://assets/data/gameplay_policies.json

const CONFIG_PATH := "res://assets/data/gameplay_policies.json"

const HitChancePolicyClass := preload("res://scripts/gameplay_policies/hit_chance_policy.gd")
const GrenadePolicyClass := preload("res://scripts/gameplay_policies/grenade_policy.gd")
const SuppressionPolicyClass := preload("res://scripts/gameplay_policies/suppression_policy.gd")
const MovementPolicyClass := preload("res://scripts/gameplay_policies/movement_policy.gd")
const FireAnimPolicyClass := preload("res://scripts/gameplay_policies/fire_anim_policy.gd")
const IdleAnimPolicyClass := preload("res://scripts/gameplay_policies/idle_anim_policy.gd")
const WeaponPolicyClass := preload("res://scripts/gameplay_policies/weapon_policy.gd")
const VisionPolicyClass := preload("res://scripts/gameplay_policies/vision_policy.gd")
const CoverPolicyClass := preload("res://scripts/gameplay_policies/cover_policy.gd")
const LOSPolicyClass := preload("res://scripts/gameplay_policies/los_policy.gd")

var hit: HitChancePolicyClass = HitChancePolicyClass.new()
var grenade: GrenadePolicyClass = GrenadePolicyClass.new()
var suppression: SuppressionPolicyClass = SuppressionPolicyClass.new()
var movement: MovementPolicyClass = MovementPolicyClass.new()
var fire_anim: FireAnimPolicyClass = FireAnimPolicyClass.new()
var idle_anim: IdleAnimPolicyClass = IdleAnimPolicyClass.new()
var weapons: WeaponPolicyClass = WeaponPolicyClass.new()
var vision: VisionPolicyClass = VisionPolicyClass.new()
var cover: CoverPolicyClass = CoverPolicyClass.new()
var los: LOSPolicyClass = LOSPolicyClass.new()


func _ready() -> void:
	reload_from_config()


func reset_all_to_defaults() -> void:
	hit.reset_to_defaults()
	grenade.reset_to_defaults()
	suppression.reset_to_defaults()
	movement.reset_to_defaults()
	fire_anim.reset_to_defaults()
	idle_anim.reset_to_defaults()
	weapons.reset_to_defaults()
	vision.reset_to_defaults()
	cover.reset_to_defaults()
	los.reset_to_defaults()
	SimulationClock.reset_tick_defaults()
	_sync_cross_policy_aliases()


## Load optional JSON overrides on top of defaults. Missing file = defaults only.
func reload_from_config() -> void:
	reset_all_to_defaults()
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("GameplayPolicies: could not open %s" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("GameplayPolicies: invalid JSON at %s" % CONFIG_PATH)
		return
	var root: Dictionary = parsed
	if root.has("hit") and root.hit is Dictionary:
		hit.apply_config(root.hit)
	if root.has("grenade") and root.grenade is Dictionary:
		grenade.apply_config(root.grenade)
	if root.has("suppression") and root.suppression is Dictionary:
		suppression.apply_config(root.suppression)
	if root.has("movement") and root.movement is Dictionary:
		movement.apply_config(root.movement)
	if root.has("weapons") and root.weapons is Dictionary:
		weapons.apply_config(root.weapons)
	if root.has("vision") and root.vision is Dictionary:
		vision.apply_config(root.vision)
	if root.has("cover") and root.cover is Dictionary:
		cover.apply_config(root.cover)
	if root.has("los") and root.los is Dictionary:
		los.apply_config(root.los)
	if root.has("idle_anim") and root.idle_anim is Dictionary:
		idle_anim.apply_config(root.idle_anim)
	if root.has("simulation") and root.simulation is Dictionary:
		SimulationClock.apply_config(root.simulation)
	_sync_cross_policy_aliases()


func _sync_cross_policy_aliases() -> void:
	## Legacy sync: expose full-strength cover mult for older HitChancePolicy callers.
	hit.moderate_cover_hit_mult = cover.cover_hit_multiplier
