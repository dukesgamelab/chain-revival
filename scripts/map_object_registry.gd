class_name MapObjectRegistry
extends RefCounted
## Lookup table for map object types and their cover / LOS properties.

const TYPE_TREE := "tree"
const TYPE_HAYBAIL := "haybail"
const TYPE_WALL_STRAIGHT := "wall_straight"
const TYPE_WALL_CORNER := "wall_corner"
## Legacy aliases kept for older maps and saves.
const TYPE_HAYBALE := "haybale"
const TYPE_WALL := "wall"
const TYPE_WALL_STRAIGHT_LONG_NE := "wall_straight_long_ne"
const TYPE_BUILDING := "building"

const DEFAULT_BLOCKED_TYPE := TYPE_TREE

const SPRITE_TREE := "res://assets/sprites/tree-1-transparent-game-sized.png"
const SPRITE_HAYBAIL := "res://assets/sprites/haybail-1-transparent-game-sized.png"
const SPRITE_WALL_STRAIGHT := "res://assets/sprites/wall-straight-1-tile.png"
const SPRITE_WALL_CORNER := "res://assets/sprites/wall-corner-1.png"


static func get_def(type_id: String) -> MapObjectDef:
	match normalize_type_id(type_id):
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
		TYPE_HAYBAIL:
			return MapObjectDef.new(
				TYPE_HAYBAIL,
				"haybail",
				true,
				false,
				true,
				CoverSystem.CoverType.MODERATE,
				SPRITE_HAYBAIL,
			)
		TYPE_WALL_STRAIGHT:
			return MapObjectDef.new(
				TYPE_WALL_STRAIGHT,
				"wall",
				true,
				true,
				true,
				CoverSystem.CoverType.COMPLETE,
				SPRITE_WALL_STRAIGHT,
			)
		TYPE_WALL_CORNER:
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


static func cover_type_name(cover_type: int) -> String:
	match cover_type:
		CoverSystem.CoverType.MODERATE:
			return "MODERATE"
		CoverSystem.CoverType.COMPLETE:
			return "COMPLETE"
		_:
			return "NONE"


## Map legacy saved types to current gameplay types.
static func normalize_type_id(type_id: String) -> String:
	match type_id:
		TYPE_WALL_STRAIGHT_LONG_NE, TYPE_WALL:
			return TYPE_WALL_STRAIGHT
		TYPE_HAYBALE:
			return TYPE_HAYBAIL
		_:
			return type_id
