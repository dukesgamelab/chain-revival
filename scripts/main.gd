extends Node2D

const SoldierScene := preload("res://scenes/soldier.tscn")


func _ready() -> void:
	spawn_soldier(Vector2.ZERO)


func spawn_soldier(world_position: Vector2) -> Node2D:
	var soldier: Node2D = SoldierScene.instantiate()
	soldier.position = world_position
	add_child(soldier)
	return soldier
