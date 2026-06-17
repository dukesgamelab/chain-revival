class_name MapObjectDef
extends RefCounted
## Gameplay properties for one map object type (tree, wall, haybale, building, …).

var type_id: String = ""
var display_name: String = ""
var blocks_movement: bool = false
var blocks_los: bool = false
var provides_cover: bool = false
var cover_value: float = 0.0


func _init(
	p_type_id: String,
	p_display_name: String,
	p_blocks_movement: bool,
	p_blocks_los: bool,
	p_provides_cover: bool,
	p_cover_value: float,
) -> void:
	type_id = p_type_id
	display_name = p_display_name
	blocks_movement = p_blocks_movement
	blocks_los = p_blocks_los
	provides_cover = p_provides_cover
	cover_value = p_cover_value
