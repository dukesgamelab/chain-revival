class_name AssignWeaponCommand
extends RefCounted
## Plain data: assign a cache item to a player or soldier. ActionResolver applies it.

const WeaponCacheClass := preload("res://scripts/core/weapon_cache.gd")

## Owning player's cache the item is taken from.
var from_player_id: int = -1
var item_id: String = ""
var target_kind: int = WeaponCacheClass.TargetKind.SOLDIER
## player_id when target_kind=PLAYER; soldier_id when SOLDIER.
var target_id: int = -1
## Required when assigning to a soldier (soldiers are per-team).
var target_team_id: int = -1
