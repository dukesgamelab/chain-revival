class_name GrenadeExplosion
extends Node2D
## Simple procedural grenade puff (no sprite sheet). Presentation only.

const DURATION := 0.45

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
	var base_radius := TileSizeConfig.TILE_WIDTH * 0.35
	var radius := base_radius * (0.4 + t * 0.9)
	var alpha := (1.0 - t) * 0.55
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.55, 0.12, alpha))
	draw_circle(Vector2.ZERO, radius * 0.55, Color(1.0, 0.85, 0.35, alpha * 0.85))
	draw_circle(Vector2.ZERO, radius * 0.2, Color(1.0, 1.0, 0.9, alpha * 0.6))
