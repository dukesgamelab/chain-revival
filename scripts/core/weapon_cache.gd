class_name WeaponCache
extends RefCounted
## Per-player weapon/equipment pool (original WeaponCashe / WeaponAss_Cashe).
## IDs only — no node refs. Owned by GameState.

const WeaponPolicyClass := preload("res://scripts/gameplay_policies/weapon_policy.gd")
const WeaponRegistryClass := preload("res://scripts/combat/weapon_registry.gd")

enum Kind { WEAPON, EQUIPMENT }
enum TargetKind { PLAYER, SOLDIER }

const ITEM_AMMUNITION_BOX := "ammunition_box"

## Short UI names matching the original dialog ("Garand, 70").
const DISPLAY_NAMES := {
	"m1_garand": "Garand",
	"kar98k": "Kar98k",
	"thompson": "Thompson",
	"bar": "BAR",
	"mp40": "MP40",
	"mg42": "MG42",
	ITEM_AMMUNITION_BOX: "Ammunition Box",
}


## player_id -> Array[{ item_id, kind, count }]
var _caches: Dictionary = {}


func clear() -> void:
	_caches.clear()


func has_player(player_id: int) -> bool:
	return _caches.has(player_id)


func ensure_player(player_id: int) -> void:
	if not _caches.has(player_id):
		_caches[player_id] = []


## Default deployment pools (observed USA: Ammo Box x4, BAR x2, Thompson x3).
func bootstrap_default_caches(player_ids: Array[int], team_for_player: Callable) -> void:
	clear()
	for pid in player_ids:
		var team_id := int(team_for_player.call(pid))
		ensure_player(pid)
		_set_cache(
			pid,
			_default_pool_for_team(team_id),
		)


func _default_pool_for_team(team_id: int) -> Array:
	## Mirror the observed Weapons dialog contents per faction.
	if team_id == Team.GERMANY:
		return [
			_entry(ITEM_AMMUNITION_BOX, Kind.EQUIPMENT, 4),
			_entry(WeaponPolicyClass.ID_MG42, Kind.WEAPON, 2),
			_entry(WeaponPolicyClass.ID_MP40, Kind.WEAPON, 3),
		]
	return [
		_entry(ITEM_AMMUNITION_BOX, Kind.EQUIPMENT, 4),
		_entry(WeaponPolicyClass.ID_BAR, Kind.WEAPON, 2),
		_entry(WeaponPolicyClass.ID_THOMPSON, Kind.WEAPON, 3),
	]


static func _entry(item_id: String, kind: int, count: int) -> Dictionary:
	return {"item_id": item_id, "kind": kind, "count": count}


func _set_cache(player_id: int, entries: Array) -> void:
	var out: Array = []
	for e in entries:
		out.append((e as Dictionary).duplicate(true))
	_caches[player_id] = out


func get_cache(player_id: int) -> Array:
	ensure_player(player_id)
	var out: Array = []
	for e in _caches[player_id]:
		out.append((e as Dictionary).duplicate(true))
	return out


func pool_count(player_id: int, item_id: String) -> int:
	for e in get_cache(player_id):
		if str(e.get("item_id", "")) == item_id:
			return int(e.get("count", 0))
	return 0


func item_kind(item_id: String) -> int:
	if item_id == ITEM_AMMUNITION_BOX:
		return Kind.EQUIPMENT
	return Kind.WEAPON


func is_equipment(item_id: String) -> bool:
	return item_kind(item_id) == Kind.EQUIPMENT


func display_name(item_id: String) -> String:
	if DISPLAY_NAMES.has(item_id):
		return str(DISPLAY_NAMES[item_id])
	var weapon := WeaponRegistryClass.get_weapon(item_id)
	if weapon != null:
		return weapon.weapon_name
	return item_id


## Faction default rifles are never assignable cache items (Garand / Kar98k).
static func is_default_rifle(item_id: String) -> bool:
	return item_id == WeaponPolicyClass.ID_M1_GARAND or item_id == WeaponPolicyClass.ID_KAR98K


func pool_line(item_id: String, count: int) -> String:
	if count <= 1:
		return display_name(item_id)
	return "%s x%d" % [display_name(item_id), count]


## Remove one unit from the pool. Returns false if unavailable.
func take_from_pool(player_id: int, item_id: String) -> bool:
	ensure_player(player_id)
	var cache: Array = _caches[player_id]
	for i in cache.size():
		var e: Dictionary = cache[i]
		if str(e.get("item_id", "")) != item_id:
			continue
		var count := int(e.get("count", 0))
		if count <= 0:
			return false
		count -= 1
		if count <= 0:
			cache.remove_at(i)
		else:
			e["count"] = count
			cache[i] = e
		_caches[player_id] = cache
		return true
	return false


## Add count units to the pool (merge existing rows). Default rifles are never cached.
func add_to_pool(player_id: int, item_id: String, count: int = 1, kind: int = -1) -> void:
	if count <= 0 or item_id.is_empty():
		return
	if is_default_rifle(item_id):
		return
	ensure_player(player_id)
	var resolved_kind := kind if kind >= 0 else item_kind(item_id)
	var cache: Array = _caches[player_id]
	for i in cache.size():
		var e: Dictionary = cache[i]
		if str(e.get("item_id", "")) != item_id:
			continue
		e["count"] = int(e.get("count", 0)) + count
		cache[i] = e
		_caches[player_id] = cache
		return
	cache.append(_entry(item_id, resolved_kind, count))
	_caches[player_id] = cache


## How many of weapon_id are already held by soldiers on this fireteam.
static func squad_weapon_count(game_state, team_id: int, weapon_id: String) -> int:
	var n := 0
	var fireteam = game_state.session.get_fireteam(team_id)
	for state in fireteam.soldiers:
		if str(state.weapon_id) == weapon_id:
			n += 1
	return n


## True if assigning one more of weapon_id would exceed INIT_LimitPerSquad.
static func would_exceed_squad_limit(game_state, team_id: int, weapon_id: String) -> bool:
	var limit := WeaponPolicyClass.squad_limit(weapon_id)
	if limit < 0:
		return false
	return squad_weapon_count(game_state, team_id, weapon_id) >= limit


## Faction default rifle for return-to-pool / AI fill.
static func default_rifle_for_team(team_id: int) -> String:
	if team_id == Team.GERMANY:
		return WeaponPolicyClass.ID_KAR98K
	return WeaponPolicyClass.ID_M1_GARAND


## AI: move specials from this player's cache onto soldiers still holding the default rifle.
func auto_distribute_to_soldiers(game_state, player_id: int, soldier_ids: Array[int], team_id: int) -> void:
	var default_rifle := default_rifle_for_team(team_id)
	var specials: Array[String] = []
	for e in get_cache(player_id):
		var item_id := str(e.get("item_id", ""))
		if is_equipment(item_id):
			continue
		if item_id == default_rifle:
			continue
		for _i in int(e.get("count", 0)):
			specials.append(item_id)
	if specials.is_empty():
		return
	var si := 0
	for soldier_id in soldier_ids:
		if si >= specials.size():
			break
		var soldier = game_state.get_soldier(team_id, soldier_id)
		if soldier == null or soldier.is_dead:
			continue
		if str(soldier.weapon_id) != default_rifle:
			continue
		var item_id := specials[si]
		if would_exceed_squad_limit(game_state, team_id, item_id):
			si += 1
			continue
		if not take_from_pool(player_id, item_id):
			si += 1
			continue
		var old_id := str(soldier.weapon_id)
		soldier.assign_weapon(item_id, true)
		if not old_id.is_empty():
			add_to_pool(player_id, old_id, 1, Kind.WEAPON)
		si += 1
