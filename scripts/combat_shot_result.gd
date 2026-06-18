class_name CombatShotResult
extends RefCounted
## Outcome of one shot resolved by CombatSystem.

var fired: bool = false
var hit: bool = false
var killed: bool = false
var blocked: bool = false
var no_ammo: bool = false
var had_cover: bool = false
var cover_type: int = 0
var out_of_range: bool = false
var on_cooldown: bool = false
var weapon_name: String = ""
var tracer_count: int = 0
var shooter_team_id: int = Team.USA
var shooter_id: int = 1
var target_team_id: int = Team.GERMANY
var target_id: int = 1
var messages: Array[String] = []
