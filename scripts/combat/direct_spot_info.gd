class_name DirectSpotInfo
extends RefCounted

const SoldierStateClass := preload("res://scripts/soldiers/soldier_state.gd")

var enemy: SoldierStateClass = null
var observer: SoldierStateClass = null
var score: float = -1.0
