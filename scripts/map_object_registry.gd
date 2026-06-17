class_name MapObjectRegistry
extends RefCounted
## Lookup table for map object types. Extend here when adding walls, haybales, buildings, etc.

const TYPE_TREE := "tree"
const TYPE_WALL := "wall"
const TYPE_HAYBALE := "haybale"
const TYPE_BUILDING := "building"

const DEFAULT_BLOCKED_TYPE := TYPE_TREE


static func get_def(type_id: String) -> MapObjectDef:
	match type_id:
		TYPE_TREE:
			return MapObjectDef.new(TYPE_TREE, "tree", true, true, true, 0.30)
		TYPE_WALL:
			return MapObjectDef.new(TYPE_WALL, "wall", true, true, false, 0.0)
		TYPE_HAYBALE:
			return MapObjectDef.new(TYPE_HAYBALE, "haybale", true, false, true, 0.25)
		TYPE_BUILDING:
			return MapObjectDef.new(TYPE_BUILDING, "building", true, true, true, 0.40)
		_:
			return null
