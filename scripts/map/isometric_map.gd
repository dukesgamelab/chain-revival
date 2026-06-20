class_name IsometricMap
extends Node2D
## Renders map tiles from MapData and runs grid pathfinding.
##
## MapData holds gameplay facts; this node draws them and owns AStarGrid2D.

const COVER_TYPE_MODERATE := 1

@export var tile_color_a := Color(0.28, 0.48, 0.22, 1.0)
@export var tile_color_b := Color(0.24, 0.42, 0.19, 1.0)
@export var tile_outline := Color(0.12, 0.22, 0.10, 0.6)
@export var blocked_color := Color(0.35, 0.35, 0.38, 1.0)
@export var blocked_outline := Color(0.18, 0.18, 0.20, 0.9)

@export var path_color := Color(0.95, 0.85, 0.20, 0.55)
@export var target_color := Color(0.90, 0.15, 0.15, 0.75)
@export var team_1_spawn_color := Color(0.35, 0.72, 0.38, 0.70)
@export var team_2_spawn_color := Color(0.58, 0.58, 0.62, 0.70)

var map_data: MapData = null

var _astar := AStarGrid2D.new()
var _path_overlay: IsometricPathOverlay
var _map_edit_hover_overlay: MapEditHoverOverlay
## When false, walkable tiles draw outlines only so GrassTerrainLayer shows through.
var _show_tile_fill: bool = true


func _ready() -> void:
	_path_overlay = IsometricPathOverlay.new()
	_path_overlay.z_index = 2
	_path_overlay.path_color = path_color
	_path_overlay.target_color = target_color
	add_child(_path_overlay)
	_map_edit_hover_overlay = MapEditHoverOverlay.new()
	_map_edit_hover_overlay.z_index = 3
	add_child(_map_edit_hover_overlay)
	queue_redraw()


## Apply authoritative map data and rebuild walkability.
func apply_map_data(data: MapData) -> void:
	map_data = data
	rebuild_pathfinding()
	_path_overlay.configure_bounds_check(func(cell: Vector2i) -> bool: return is_walkable(cell))
	queue_redraw()


## Map object sprites are drawn on DepthSortedLayer (Y-sorted with soldiers).


func set_show_tile_fill(show_fill: bool) -> void:
	_show_tile_fill = show_fill
	queue_redraw()


func set_map_edit_hover(cell: Vector2i) -> void:
	if _map_edit_hover_overlay != null:
		_map_edit_hover_overlay.set_hover_cell(cell)


func clear_map_edit_hover() -> void:
	if _map_edit_hover_overlay != null:
		_map_edit_hover_overlay.clear_hover()


func rebuild_pathfinding() -> void:
	if map_data == null:
		return

	_astar.region = Rect2i(0, 0, map_data.width, map_data.height)
	_astar.cell_size = Vector2(1.0, 1.0)
	# 8-direction movement; block diagonals that would cut through a blocked corner.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()

	for cell in map_data.blocked_tiles:
		if map_data.is_in_bounds(cell):
			_astar.set_point_solid(cell, true)


func is_in_bounds(cell: Vector2i) -> bool:
	if map_data == null:
		return false
	return map_data.is_in_bounds(cell)


func is_walkable(cell: Vector2i) -> bool:
	if map_data == null:
		return false
	return map_data.is_walkable(cell)


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not is_walkable(from_cell) or not is_walkable(to_cell):
		return []
	if _astar.is_point_solid(to_cell):
		return []

	var raw_path := _astar.get_id_path(from_cell, to_cell)
	var path: Array[Vector2i] = []
	for cell in raw_path:
		path.append(Vector2i(cell))
	return path


func show_path(cells: Array[Vector2i], target: Vector2i) -> void:
	_path_overlay.path_color = path_color
	_path_overlay.target_color = target_color
	_path_overlay.set_path(cells, target)


func clear_path() -> void:
	_path_overlay.clear_path()


## Redraw tiles and any active path overlay after a presentation-only view rotation.
func refresh_view_rotation() -> void:
	queue_redraw()
	if _path_overlay != null:
		_path_overlay.queue_redraw()
	if _map_edit_hover_overlay != null:
		_map_edit_hover_overlay.queue_redraw()


func _draw() -> void:
	if map_data == null:
		return
	if _show_tile_fill:
		_draw_grass_border()
	_draw_tiles()
	if _show_tile_fill:
		_draw_spawn_markers()


## Decorative grass diamonds outside the playable map (not used for pathfinding).
func _draw_grass_border() -> void:
	var border := IsometricGrid.MAP_VISUAL_BORDER
	for ring in range(1, border + 1):
		var x_min := -ring
		var x_max := map_data.width - 1 + ring
		var y_min := -ring
		var y_max := map_data.height - 1 + ring
		for x in range(x_min, x_max + 1):
			_draw_grass_cell(Vector2i(x, y_min))
			if y_max != y_min:
				_draw_grass_cell(Vector2i(x, y_max))
		for y in range(y_min + 1, y_max):
			_draw_grass_cell(Vector2i(x_min, y))
			if x_max != x_min:
				_draw_grass_cell(Vector2i(x_max, y))


func _draw_grass_cell(cell: Vector2i) -> void:
	if map_data.is_in_bounds(cell):
		return
	var center := IsometricGrid.grid_to_world(cell)
	var corners := IsometricGrid.diamond_corners(center)
	var fill := tile_color_a if (cell.x + cell.y) % 2 == 0 else tile_color_b
	draw_colored_polygon(corners, fill)
	draw_polyline(corners, tile_outline, 1.0, true)


func _draw_tiles() -> void:
	for y in range(map_data.height):
		for x in range(map_data.width):
			var cell := Vector2i(x, y)
			var center := IsometricGrid.grid_to_world(cell)
			var corners := IsometricGrid.diamond_corners(center)

			if map_data.is_blocked(cell):
				if _show_tile_fill:
					var object_def := map_data.get_object_def(cell)
					var fill := blocked_color
					if object_def != null and object_def.cover_type == COVER_TYPE_MODERATE:
						fill = blocked_color.lerp(Color(0.22, 0.48, 0.18, 1.0), 0.25)
					draw_colored_polygon(corners, fill)
					draw_polyline(corners, blocked_outline, 1.0, true)
			else:
				if _show_tile_fill:
					var fill := tile_color_a if (x + y) % 2 == 0 else tile_color_b
					draw_colored_polygon(corners, fill)
					draw_polyline(corners, tile_outline, 1.0, true)


func _draw_spawn_markers() -> void:
	for cell in map_data.team_1_spawn_points:
		_draw_spawn_diamond(cell, team_1_spawn_color)
	for cell in map_data.team_2_spawn_points:
		_draw_spawn_diamond(cell, team_2_spawn_color)


func _draw_spawn_diamond(cell: Vector2i, color: Color) -> void:
	if not map_data.is_in_bounds(cell):
		return
	var center := IsometricGrid.grid_to_world(cell)
	var corners := IsometricGrid.diamond_corners(center)
	var inset := PackedVector2Array()
	for point in corners:
		inset.append(center + (point - center) * 0.72)
	draw_colored_polygon(inset, color)
