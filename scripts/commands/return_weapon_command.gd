class_name ReturnWeaponCommand
extends RefCounted
## Plain data: return a soldier's weapon to a player's cache. ActionResolver applies it.

var to_player_id: int = -1
var team_id: int = -1
var soldier_id: int = -1
var item_id: String = ""
