class_name CommandContext
extends RefCounted
## Optional inputs the resolver cannot derive from GameState alone.
##
## find_path is supplied by the local map view. soldier_snap_cells is retained for
## compatibility but gameplay no longer reads interpolated presentation positions —
## mid-move commands use SoldierState.grid_position.

## func(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]
var find_path: Callable = Callable()

## Deprecated for gameplay authority. Prefer SoldierState.grid_position.
var soldier_snap_cells: Dictionary = {}

## Soldier ids included in a Fire At order (single or squad scope).
var shooter_ids: Array[int] = []

## When > 0, authorize Move/Face/etc. for this player's owned soldiers (AI / MP).
## When <= 0, fall back to local human ownership checks.
var acting_player_id: int = -1
