class_name IsometricPathOverlay
extends Node2D
## Draws movement path and destination highlight without redrawing the full map.
## Drawing is gated by debug_visible for the yellow path only (test overlay; toggle with T).
## Red destination markers always draw when targets are set (flashing, with roster DOT icons).

const DOT_TEXTURE_PATHS := [
	"res://assets/sprites/id_markers/DOT1.png",
	"res://assets/sprites/id_markers/DOT2.png",
	"res://assets/sprites/id_markers/DOT3.png",
	"res://assets/sprites/id_markers/DOT4.png",
]

@export var path_color := Color(0.95, 0.85, 0.20, 0.55)
@export var target_color := Color(0.90, 0.15, 0.15, 0.75)

## When false, yellow path tiles are hidden; red destinations still draw.
var debug_visible: bool = false

## Flash period for destination diamonds (matches OG blink cadence).
const FLASH_HZ := 2.5
const DOT_DRAW_SCALE := 2.0

var _path_cells: Array[Vector2i] = []
## Each entry: {"cell": Vector2i, "soldier_id": int}
var _markers: Array[Dictionary] = []
var _map_bounds_check: Callable = Callable()
var _flash_t: float = 0.0
var _dot_textures: Array[Texture2D] = []


func _ready() -> void:
	_load_dot_textures()
	set_process(false)


func _load_dot_textures() -> void:
	_dot_textures.clear()
	for path in DOT_TEXTURE_PATHS:
		_dot_textures.append(load(path) as Texture2D)


func configure_bounds_check(check: Callable) -> void:
	_map_bounds_check = check


func set_debug_visible(enabled: bool) -> void:
	if debug_visible == enabled:
		return
	debug_visible = enabled
	queue_redraw()


func set_path(cells: Array[Vector2i], target: Vector2i, markers: Array = []) -> void:
	_path_cells = cells.duplicate()
	_markers.clear()
	if not markers.is_empty():
		for entry in markers:
			if entry is Dictionary and entry.has("cell"):
				_markers.append({
					"cell": Vector2i(entry.cell),
					"soldier_id": int(entry.get("soldier_id", 1)),
				})
	elif target != Vector2i(-999, -999):
		_markers.append({"cell": target, "soldier_id": 1})
	_flash_t = 0.0
	set_process(not _markers.is_empty())
	queue_redraw()


func clear_path() -> void:
	if _path_cells.is_empty() and _markers.is_empty():
		return
	_path_cells.clear()
	_markers.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if _markers.is_empty():
		set_process(false)
		return
	_flash_t += delta
	queue_redraw()


func _draw() -> void:
	## Yellow path tiles are test-only (T toggle). Red destinations always show.
	if debug_visible:
		for i in range(_path_cells.size()):
			if i == 0:
				continue
			var cell := _path_cells[i]
			var center := IsometricGrid.grid_to_world(cell)
			draw_colored_polygon(IsometricGrid.diamond_corners(center), path_color)

	if _markers.is_empty():
		return

	## Square-wave flash: bright ↔ dim (OG-style blink) — red tile only, not overhead icons.
	var flash_on := int(floor(_flash_t * FLASH_HZ * 2.0)) % 2 == 0
	var fill := target_color
	if flash_on:
		fill = Color(
			minf(target_color.r * 1.15, 1.0),
			minf(target_color.g * 1.15, 1.0),
			minf(target_color.b * 1.15, 1.0),
			minf(target_color.a + 0.15, 1.0),
		)
	else:
		fill = Color(target_color.r, target_color.g, target_color.b, target_color.a * 0.35)

	## Merge soldiers that share a destination cell.
	var by_cell: Dictionary = {}
	for marker in _markers:
		var cell: Vector2i = marker.cell
		if _map_bounds_check.is_valid() and not _map_bounds_check.call(cell):
			continue
		if not by_cell.has(cell):
			by_cell[cell] = [] as Array
		(by_cell[cell] as Array).append(int(marker.soldier_id))

	for cell in by_cell.keys():
		var center := IsometricGrid.grid_to_world(cell)
		draw_colored_polygon(IsometricGrid.diamond_corners(center), fill)
		if not flash_on:
			continue
		var ids: Array = by_cell[cell]
		ids.sort()
		if ids.size() == 1:
			_draw_soldier_dot_sprite(center, int(ids[0]))
		else:
			var n := ids.size()
			var start_y := -float(n - 1) * 6.0
			for i in range(n):
				var cluster_center := center + Vector2(0.0, start_y + float(i) * 12.0)
				_draw_soldier_dot_sprite(cluster_center, int(ids[i]), 0.75)


@warning_ignore("shadowed_variable_base_class")
func _draw_soldier_dot_sprite(center: Vector2, soldier_id: int, scale: float = 1.0) -> void:
	if _dot_textures.is_empty():
		_load_dot_textures()
	var idx := Soldier.roster_marker_index(soldier_id)
	if idx < 0 or idx >= _dot_textures.size():
		return
	var tex: Texture2D = _dot_textures[idx]
	if tex == null:
		return
	var size := tex.get_size() * DOT_DRAW_SCALE * scale
	var dest := Rect2(center - size * 0.5, size)
	draw_texture_rect(tex, dest, false)
