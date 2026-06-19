class_name WeaponRegistry
extends RefCounted
## Weapon definition catalog. Loadout assignments live in FireteamLoadout.

const WeaponDataClass := preload("res://scripts/weapon_data.gd")
const WeaponTypeClass := preload("res://scripts/weapon_type.gd")

const ID_M1_GARAND := "m1_garand"
const ID_BAR := "bar"
const ID_THOMPSON := "thompson"
const ID_KAR98K := "kar98k"
const ID_MG42 := "mg42"
const ID_MP40 := "mp40"


static func get_weapon(weapon_id: String) -> WeaponDataClass:
	match weapon_id:
		ID_M1_GARAND:
			return WeaponDataClass.new(
				ID_M1_GARAND, "M1 Garand", WeaponTypeClass.RIFLE,
				18, 0.10, 1, 80,
				0.0, 0, 1.2, 1.1,
			)
		ID_BAR:
			return WeaponDataClass.new(
				ID_BAR, "BAR", WeaponTypeClass.LMG,
				20, 0.05, 4, 120,
				0.0, 0, 1.1, 0.9,
			)
		ID_THOMPSON:
			return WeaponDataClass.new(
				ID_THOMPSON, "Thompson", WeaponTypeClass.SMG,
				8, 0.0, 3, 100, 0.15, 4, 0.8, 0.7,
			)
		ID_KAR98K:
			return WeaponDataClass.new(
				ID_KAR98K, "Kar98k", WeaponTypeClass.RIFLE,
				20, 0.14, 1, 60,
				0.0, 0, 2.0, 1.3,
			)
		ID_MG42:
			return WeaponDataClass.new(
				ID_MG42, "MG42", WeaponTypeClass.LMG,
				22, 0.04, 6, 150,
				0.0, 0, 0.6, 1.0,
			)
		ID_MP40:
			return WeaponDataClass.new(
				ID_MP40, "MP40", WeaponTypeClass.SMG,
				8, 0.0, 3, 100, 0.12, 4, 0.9, 0.7,
			)
		_:
			return null
