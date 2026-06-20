class_name GrenadeExplosion
extends Node2D
## Brief expanding-ring explosion marker (presentation only).

const DURATION := 0.45
const MAX_RADIUS := 52.0

var _elapsed: float = 0.0


static func spawn(parent: Node2D, world_pos: Vector2) -> GrenadeExplosion:
	var fx := GrenadeExplosion.new()
	fx.position = world_pos
	fx.z_index = 7
	parent.add_child(fx)
	return fx


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= DURATION:
		queue_free()


func _draw() -> void:
	var t := clampf(_elapsed / DURATION, 0.0, 1.0)
	var fade := 1.0 - t
	var base_radius := MAX_RADIUS * t

	draw_circle(Vector2.ZERO, base_radius * 0.35, Color(1.0, 0.92, 0.75, fade * 0.35))

	for ring in range(3):
		var ring_delay := float(ring) * 0.1
		var ring_t := clampf((t - ring_delay) / (1.0 - ring_delay), 0.0, 1.0)
		if ring_t <= 0.0:
			continue
		var radius := base_radius * (0.55 + ring_t * 0.45)
		var alpha := fade * (0.85 - float(ring) * 0.2)
		var ring_color := Color(0.95, 0.55, 0.15, alpha) if ring == 0 else Color(0.85, 0.85, 0.88, alpha * 0.75)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, ring_color, 2.5 + float(ring), true)
