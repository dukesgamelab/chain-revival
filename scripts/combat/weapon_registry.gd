class_name WeaponRegistry
extends RefCounted
## Weapon definition catalog facade. Stats live in GameplayPolicies.weapons.
## Loadout assignments live in FireteamLoadout.

const WeaponDataClass := preload("res://scripts/combat/weapon_data.gd")
const WeaponPolicyClass := preload("res://scripts/gameplay_policies/weapon_policy.gd")

const ID_M1_GARAND := WeaponPolicyClass.ID_M1_GARAND
const ID_BAR := WeaponPolicyClass.ID_BAR
const ID_THOMPSON := WeaponPolicyClass.ID_THOMPSON
const ID_KAR98K := WeaponPolicyClass.ID_KAR98K
const ID_MG42 := WeaponPolicyClass.ID_MG42
const ID_MP40 := WeaponPolicyClass.ID_MP40


static func get_weapon(weapon_id: String) -> WeaponDataClass:
	return GameplayPolicies.weapons.create_weapon(weapon_id)
