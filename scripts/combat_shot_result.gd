class_name CombatShotResult
extends RefCounted
## Outcome of one shot resolved by CombatSystem.

var fired: bool = false
var hit: bool = false
var killed: bool = false
var blocked: bool = false
var no_ammo: bool = false
var messages: Array[String] = []
