class_name GrenadeExplosion
extends Node2D
## OG grenade puff animation (GREXA frames). Presentation only.

const FRAME_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/og/GREXA1A.png"),
	preload("res://assets/sprites/og/GREXA1B.png"),
	preload("res://assets/sprites/og/GREXA1C.png"),
]
const DURATION := 0.6
const OG_CANVAS_SIZE := 100.0

var _elapsed: float = 0.0
var _sprite: Sprite2D


static func spawn(parent: Node2D, world_pos: Vector2) -> GrenadeExplosion:
	var fx := GrenadeExplosion.new()
	fx.position = world_pos
	fx.z_index = 7
	parent.add_child(fx)
	return fx


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = FRAME_TEXTURES[0]
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	var scale_factor := TileSizeConfig.TILE_WIDTH / OG_CANVAS_SIZE
	_sprite.scale = Vector2(scale_factor, scale_factor)
	add_child(_sprite)
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	var frame_index := mini(
		int((_elapsed / DURATION) * float(FRAME_TEXTURES.size())),
		FRAME_TEXTURES.size() - 1,
	)
	_sprite.texture = FRAME_TEXTURES[frame_index]
	if _elapsed >= DURATION:
		queue_free()
