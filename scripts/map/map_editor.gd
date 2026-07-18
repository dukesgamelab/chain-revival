class_name MapEditor
extends RefCounted
## Legacy in-game palette helper (main.tscn Map Edit mode).
## The full Chain Revival Editor lives at scenes/editor/map_editor.tscn.

enum Palette { TREE, HAYBAIL, WALL, ERASE }


static func palette_type_id(palette: Palette) -> String:
	match palette:
		Palette.TREE:
			return MapObjectRegistry.TYPE_TREE
		Palette.HAYBAIL:
			return MapObjectRegistry.TYPE_HAYBAIL
		Palette.WALL:
			return MapObjectRegistry.TYPE_WALL_STRAIGHT
		_:
			return ""


static func palette_label(palette: Palette) -> String:
	match palette:
		Palette.TREE:
			return "Tree"
		Palette.HAYBAIL:
			return "Haybail"
		Palette.WALL:
			return "Wall"
		Palette.ERASE:
			return "Erase"
		_:
			return ""
