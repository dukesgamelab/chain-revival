class_name ObjectId
extends RefCounted
## Stable string IDs for gameplay objects (never node paths).


static func soldier(team_id: int, soldier_id: int) -> String:
	return "soldier:%d:%d" % [team_id, soldier_id]


static func map_object(cell: Vector2i) -> String:
	return "map:%d:%d" % [cell.x, cell.y]


static func grenade(team_id: int, soldier_id: int) -> String:
	return "grenade:%d:%d" % [team_id, soldier_id]


## Compact team+slot key for combat snaps, spotting overrides, and view dicts.
static func team_soldier_key(team_id: int, soldier_id: int) -> String:
	return "%d:%d" % [team_id, soldier_id]
