class_name WeaponType
extends RefCounted
## Broad weapon categories (suppression and other systems can key off these later).

enum Type { RIFLE, SMG, LMG }

const RIFLE := Type.RIFLE
const SMG := Type.SMG
const LMG := Type.LMG


static func display_name(weapon_type: int) -> String:
	match weapon_type:
		Type.SMG:
			return "SMG"
		Type.LMG:
			return "Light Machine Gun"
		_:
			return "Rifle"


## Single-letter map indicator: Rifle=R, SMG=S, LMG=L.
static func short_code(weapon_type: int) -> String:
	match weapon_type:
		Type.SMG:
			return "S"
		Type.LMG:
			return "L"
		_:
			return "R"
