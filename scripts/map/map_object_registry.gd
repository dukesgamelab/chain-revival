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
			if type_id.begins_with("coc_"):
				return _coc_default_def(type_id)
			return null


static func _coc_default_def(type_id: String) -> MapObjectDef:
	## Fallback when family is unknown / not in map_asset_registry.json.
	## Authoritative CoC family gameplay lives in MapAssetRegistry; MapData prefers that.
	match type_id:
		"coc_window", "coc_door_wood", "coc_bush", "coc_cw01", "coc_cw02", "coc_swin", "coc_wh11", "coc_swal":
			## Low field walls (WH*) often save as coc_swal — climb/height-1 moderate, not opaque.
			return MapObjectDef.new(
				type_id, type_id, false, false, true, CoverSystem.CoverType.MODERATE, ""
			)
		"coc_tree", "coc_bush_cluster":
			return MapObjectDef.new(
				type_id, type_id, true, true, true, CoverSystem.CoverType.MODERATE, ""
			)
		"coc_blocker":
			return MapObjectDef.new(
				type_id, type_id, true, true, false, CoverSystem.CoverType.NONE, ""
			)
		_:
			return MapObjectDef.new(
				type_id, type_id, true, true, true, CoverSystem.CoverType.COMPLETE, ""
			)


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
