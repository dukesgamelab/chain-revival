extends Node
## Autoload facade for gameplay policy instances.
##
## Access: GameplayPolicies.hit / .grenade / .suppression / .movement
## Defaults preserve current CombatSystem / MovementMode numbers.

const HitChancePolicyClass := preload("res://scripts/gameplay_policies/hit_chance_policy.gd")
const GrenadePolicyClass := preload("res://scripts/gameplay_policies/grenade_policy.gd")
const SuppressionPolicyClass := preload("res://scripts/gameplay_policies/suppression_policy.gd")
const MovementPolicyClass := preload("res://scripts/gameplay_policies/movement_policy.gd")

var hit: HitChancePolicyClass = HitChancePolicyClass.new()
var grenade: GrenadePolicyClass = GrenadePolicyClass.new()
var suppression: SuppressionPolicyClass = SuppressionPolicyClass.new()
var movement: MovementPolicyClass = MovementPolicyClass.new()


func reset_all_to_defaults() -> void:
	hit.reset_to_defaults()
	grenade.reset_to_defaults()
	suppression.reset_to_defaults()
	movement.reset_to_defaults()
