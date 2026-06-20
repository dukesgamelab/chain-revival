class_name CommandContext
extends RefCounted
## Optional inputs the resolver cannot derive from GameState alone.
##
## In a networked build the server would not need view snap cells or a scene pathfinder;
## clients supply these locally today while everything runs on one machine.

## func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]
var find_path: Callable = Callable()

## Mid-movement grid cell per soldier key "team_id:soldier_id" (from presentation).
var soldier_snap_cells: Dictionary = {}

## Soldier ids included in a Fire At order (single or squad scope).
var shooter_ids: Array[int] = []
