class_name CombatShotResult
extends RefCounted
## Outcome of one shot resolved by CombatSystem.

var fired: bool = false
var hit: bool = false
var killed: bool = false
var blocked: bool = false
var no_ammo: bool = false
var had_cover: bool = false
var cover_value: float = 0.0
var shooter_team_id: int = Team.BLUE
var shooter_id: int = 1
var target_team_id: int = Team.RED
var target_id: int = 1
var messages: Array[String] = []
