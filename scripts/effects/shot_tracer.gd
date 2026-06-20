class_name ShotTracer
extends Line2D
## Brief red combat tracer from shooter to target (Chain of Command style).

const DURATION := 0.18


static func spawn(parent: Node2D, from_world: Vector2, to_world: Vector2) -> ShotTracer:
	var tracer := ShotTracer.new()
	tracer.points = PackedVector2Array([from_world, to_world])
	tracer.width = 2.0
	tracer.default_color = Color(0.95, 0.12, 0.08, 0.95)
	tracer.z_index = 8
	parent.add_child(tracer)
	tracer._fade_and_free()
	return tracer


func _fade_and_free() -> void:
	modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, DURATION)
	tween.tween_callback(queue_free)
