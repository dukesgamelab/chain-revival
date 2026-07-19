extends Node2D
## Dev check: US vs German soldiers share walk/hit/fall/dead behavior; only art differs.
##
## Controls: Left/Right cycle direction · Space play hit→fall→dead · R reset · Esc quit

const UsSoldierSpriteFrames := preload("res://scripts/soldiers/us_soldier_sprite_frames.gd")
const DIRS: Array[String] = ["w", "sw", "s", "se", "e", "ne", "n", "nw"]

var _dir_index: int = 0
var _usa: AnimatedSprite2D
var _ger: AnimatedSprite2D
var _label: Label
var _phase: String = "walk"


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 16)
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)

	_usa = _make_soldier(UsSoldierSpriteFrames.get_usa_sprite_frames(), Vector2(420, 320))
	_ger = _make_soldier(UsSoldierSpriteFrames.get_germany_sprite_frames(), Vector2(860, 320))

	var help := Label.new()
	help.position = Vector2(24, 640)
	help.add_theme_font_size_override("font_size", 12)
	help.text = "Left/Right = direction | Space = death sequence | R = reset walk | Esc = quit"
	add_child(help)

	var usa_tag := Label.new()
	usa_tag.position = Vector2(380, 420)
	usa_tag.text = "USA (ASMOA)"
	add_child(usa_tag)
	var ger_tag := Label.new()
	ger_tag.position = Vector2(820, 420)
	ger_tag.text = "Germany (GSMOA)"
	add_child(ger_tag)

	_play_walk()


func _make_soldier(frames: SpriteFrames, pos: Vector2) -> AnimatedSprite2D:
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = frames
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = true
	spr.scale = Vector2(1.6, 1.6)
	spr.position = pos
	spr.animation_finished.connect(_on_finished.bind(spr))
	add_child(spr)
	return spr


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_LEFT:
			_dir_index = posmod(_dir_index - 1, DIRS.size())
			_play_walk()
		KEY_RIGHT:
			_dir_index = posmod(_dir_index + 1, DIRS.size())
			_play_walk()
		KEY_SPACE:
			_play_death()
		KEY_R:
			_play_walk()
		KEY_ESCAPE:
			get_tree().quit()


func _play_walk() -> void:
	_phase = "walk"
	var d := DIRS[_dir_index]
	var anim := "walk_%s" % d
	_usa.play(anim)
	_ger.play(anim)
	_label.text = (
		"Parity validation | direction=%s (digit mapping 1=W…8=NW) | phase=walk\n"
		+ "USA and Germany should match motion/scale/timing; only artwork differs."
	) % d


func _play_death() -> void:
	_phase = "hit"
	var d := DIRS[_dir_index]
	_usa.play("hit_%s" % d)
	_ger.play("hit_%s" % d)
	_label.text = "Parity validation | direction=%s | phase=hit→fall→dead" % d


func _on_finished(spr: AnimatedSprite2D) -> void:
	if spr != _usa:
		return
	var d := DIRS[_dir_index]
	if _phase == "hit":
		_phase = "fall"
		_usa.play("fall_%s" % d)
		_ger.play("fall_%s" % d)
	elif _phase == "fall":
		_phase = "dead"
		_usa.play("dead_%s" % d)
		_ger.play("dead_%s" % d)
		_usa.pause()
		_ger.pause()
		_usa.frame = 0
		_ger.frame = 0
		_label.text = "Parity validation | direction=%s | phase=dead corpse" % d
