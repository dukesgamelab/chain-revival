extends Node


func _ready() -> void:
	UsSoldierSpriteFrames.reload_cached_frames()
	var sf: SpriteFrames = UsSoldierSpriteFrames.get_usa_sprite_frames()
	var dirs := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
	var missing: Array[String] = []
	var ok := 0
	for semantic in ["hit_standing", "hit_prone"]:
		for d in dirs:
			var anim_name := "%s_%s" % [semantic, d]
			if not sf.has_animation(anim_name):
				missing.append("%s MISSING" % anim_name)
				continue
			var count := sf.get_frame_count(anim_name)
			var fps := sf.get_animation_speed(anim_name)
			var loop := sf.get_animation_loop(anim_name)
			print("%s frames=%d fps=%.1f loop=%s" % [anim_name, count, fps, loop])
			if count <= 0:
				missing.append("%s EMPTY" % anim_name)
			else:
				ok += 1
	print("OK=%d missing=%d" % [ok, missing.size()])
	for m in missing:
		print("FAIL ", m)
	get_tree().quit(1 if missing.size() > 0 else 0)
