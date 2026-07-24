class_name FireteamLoadout
extends RefCounted
## Data-driven weapon assignments per faction. Add new teams here without changing soldier code.
## Squad weapon caps (RECOVERED INIT_LimitPerSquad): BAR 1, Thompson 2, MG42 1, MP40 2;
## rifles unlimited. See WeaponPolicy.squad_limit().
##
## Deployment start: every soldier begins on the faction default rifle (specials come from
## the weapon cache via Assign Weapons). LOADOUTS below is the intended end composition.

## Slot order: soldier_id 1–4. Composition: 2 rifles, 1 SMG, 1 LMG.
const LOADOUTS: Dictionary = {
	Team.USA: ["m1_garand", "m1_garand", "thompson", "bar"],
	Team.GERMANY: ["kar98k", "kar98k", "mp40", "mg42"],
}


static func default_rifle_for_team(team_id: int) -> String:
	if team_id == Team.GERMANY:
		return "kar98k"
	return "m1_garand"


static func weapon_ids_for_team(team_id: int) -> Array:
	return LOADOUTS.get(team_id, [])


static func weapon_id_for_soldier(team_id: int, soldier_id: int) -> String:
	var loadout: Array = weapon_ids_for_team(team_id)
	var slot_index := soldier_id - 1
	if slot_index < 0 or slot_index >= loadout.size():
		return ""
	return str(loadout[slot_index])


## Deployment spawn weapon — default rifle only (no specials until Assign Weapons).
static func deployment_weapon_id_for_soldier(team_id: int, _soldier_id: int) -> String:
	return default_rifle_for_team(team_id)


static func assignment_message(team_id: int, soldier_id: int, weapon_name: String) -> String:
	return "%s Soldier %d assigned %s" % [Team.display_name(team_id), soldier_id, weapon_name]
