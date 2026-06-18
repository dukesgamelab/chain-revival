class_name MapObjectDef
extends RefCounted
## Gameplay properties for one map object type (tree, haybail, wall corner, …).

var type_id: String = ""
var display_name: String = ""
var sprite_path: String = ""
var blocks_movement: bool = false
var blocks_los: bool = false
var provides_cover: bool = false
var cover_type: int = 0


func _init(
	p_type_id: String,
	p_display_name: String,
	p_blocks_movement: bool,
	p_blocks_los: bool,
	p_provides_cover: bool,
	p_cover_type: int,
	p_sprite_path: String = "",
) -> void:
	type_id = p_type_id
	display_name = p_display_name
	blocks_movement = p_blocks_movement
	blocks_los = p_blocks_los
	provides_cover = p_provides_cover
	cover_type = p_cover_type
	sprite_path = p_sprite_path
