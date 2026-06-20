class_name FireAtPreviewResult
extends RefCounted

const LOSSystemClass := preload("res://scripts/combat/los_system.gd")
const SoldierStateClass := preload("res://scripts/soldiers/soldier_state.gd")

var enemy_in_cone: bool = false
var targetable: bool = false
var target: SoldierStateClass = null
var los: LOSSystemClass.LossResult = null
var aim_to_world: Vector2 = Vector2.ZERO
var click_cell: Vector2i = Vector2i.ZERO
