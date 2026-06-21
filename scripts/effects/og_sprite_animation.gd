class_name OgSpriteAnimation
extends Node2D
## Plays an OG letter-suffixed PNG sequence on a centered canvas. Presentation only.

var _sprite: Sprite2D
var _frames: Array[Texture2D] = []
var _elapsed: float = 0.0
var _duration: float = 1.0
var _display_scale: Vector2 = Vector2.ONE
var _frame_index: int = -1


static func play(
	parent: Node2D,
	world_pos: Vector2,
	frames: Array[Texture2D],
	duration_sec: float,
	display_scale: Vector2 = Vector2.ONE,
	z_index_value: int = 7,
) -> OgSpriteAnimation:
	var anim := OgSpriteAnimation.new()
	anim.position = world_pos
	anim.z_index = z_index_value
	anim._frames = frames
	anim._duration = maxf(duration_sec, 0.001)
	anim._display_scale = display_scale
	parent.add_child(anim)
	return anim


func _ready() -> void:
	if _frames.is_empty():
		queue_free()
		return

	_sprite = Sprite2D.new()
	_sprite.texture = _frames[0]
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	_sprite.scale = _display_scale
	add_child(_sprite)
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return

	var progress := clampf(_elapsed / _duration, 0.0, 1.0)
	var index := mini(int(progress * float(_frames.size())), _frames.size() - 1)
	if index != _frame_index:
		_frame_index = index
		_sprite.texture = _frames[_frame_index]
