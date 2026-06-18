class_name MapObjectRegistry
extends RefCounted
## Lookup table for map object types and their cover / LOS properties.

const TYPE_TREE := "tree"
const TYPE_HAYBAIL := "haybail"
const TYPE_WALL_CORNER := "wall_corner"
## Legacy aliases kept for older maps and saves.
const TYPE_HAYBALE := "haybale"
const TYPE_WALL := "wall"
const TYPE_BUILDING := "building"

const DEFAULT_BLOCKED_TYPE := TYPE_TREE

const SPRITE_TREE := "res://assets/sprites/tree-1.png"
const SPRITE_HAYBAIL := "res://assets/sprites/haybail-1.png"
const SPRITE_WALL_CORNER := "res://assets/sprites/wall-corner-1.png"


static func get_def(type_id: String) -> MapObjectDef:
	match type_id:
		TYPE_TREE:
			return MapObjectDef.new(
				TYPE_TREE,
				"tree",
				true,
				true,
				true,
				CoverSystem.CoverType.MODERATE,
				SPRITE_TREE,
			)
		TYPE_HAYBAIL, TYPE_HAYBALE:
			return MapObjectDef.new(
				TYPE_HAYBAIL,
				"haybail",
				true,
				false,
				true,
				CoverSystem.CoverType.MODERATE,
				SPRITE_HAYBAIL,
			)
		TYPE_WALL_CORNER, TYPE_WALL:
			return MapObjectDef.new(
				TYPE_WALL_CORNER,
				"wall",
				true,
				true,
				true,
				CoverSystem.CoverType.COMPLETE,
				SPRITE_WALL_CORNER,
			)
		TYPE_BUILDING:
			return MapObjectDef.new(
				TYPE_BUILDING,
				"building",
				true,
				true,
				true,
				CoverSystem.CoverType.COMPLETE,
				"",
			)
		_:
			return null
