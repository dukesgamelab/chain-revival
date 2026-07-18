class_name MapWorldView
extends Node2D
## Authoritative map presentation for gameplay and the Chain Revival Editor.
## Owns the shared CoC layer stack — do not duplicate these nodes elsewhere.

signal map_applied(map_data: MapData)

@onready var map_background: Node2D = $MapBackground
@onready var grass_layer: GrassTerrainLayer = $GrassTerrainLayer
@onready var original_ground_layer: OriginalGroundLayer = $OriginalGroundLayer
@onready var floor_layer: OriginalFloorLayer = $OriginalFloorLayer
@onready var underlay_layer: OriginalUnderlayLayer = $OriginalUnderlayLayer
@onready var iso_map: IsometricMap = $IsometricMap
@onready var depth_sorted: DepthSortedLayer = $DepthSorted
@onready var label_layer: OriginalLabelLayer = $OriginalLabelLayer
@onready var placement_preview: CocPlacementPreviewLayer = $CocPlacementPreviewLayer
@onready var debug_overlay: CocTileDebugOverlay = $CocTileDebugOverlay

var map_data: MapData = null
var show_grid_fill: bool = false
var _grass_visible: bool = true


func _ready() -> void:
	if debug_overlay != null:
		debug_overlay.visible = false


func apply_map_data(data: MapData) -> void:
	map_data = data
	IsometricGrid.set_original_projection_enabled(
		map_data != null and map_data.uses_original_projection
	)
	if map_data != null:
		IsometricGrid.set_view_pivot_for_map(map_data.width, map_data.height)
	iso_map.apply_map_data(map_data)
	grass_layer.apply_map_data(map_data)
	original_ground_layer.apply_map_data(map_data)
	floor_layer.apply_map_data(map_data)
	underlay_layer.apply_map_data(map_data)
	depth_sorted.apply_map_data(map_data)
	label_layer.apply_map_data(map_data)
	if debug_overlay != null:
		debug_overlay.apply_map_data(map_data)
	_sync_grid_fill()
	map_applied.emit(map_data)


## Lightweight refresh after local edits (same pipeline, shared caches).
func refresh_presentation() -> void:
	apply_map_data(map_data)


func refresh_view_rotation() -> void:
	if map_data == null:
		return
	iso_map.refresh_view_rotation()
	grass_layer.refresh_view_rotation()
	original_ground_layer.refresh_view_rotation()
	floor_layer.refresh_view_rotation()
	underlay_layer.refresh_view_rotation()
	depth_sorted.refresh_view_rotation()
	label_layer.refresh_view_rotation()
	if placement_preview != null:
		placement_preview.refresh_view_rotation()
	if debug_overlay != null:
		debug_overlay.refresh_view_rotation()


func set_grass_visible(visible_on: bool) -> void:
	_grass_visible = visible_on
	grass_layer.set_layer_visible(visible_on)
	original_ground_layer.set_layer_visible(visible_on)
	_sync_grid_fill()


func set_grid_visible(visible_on: bool) -> void:
	show_grid_fill = visible_on
	_sync_grid_fill()


func set_hover_cell(cell: Vector2i) -> void:
	iso_map.set_map_edit_hover(cell)


func clear_hover() -> void:
	iso_map.clear_map_edit_hover()


## Ghost placement preview — resolves via CocSpriteResolver (camera-relative).
func set_placement_preview(family: String, world_direction_degrees: int, cell: Vector2i) -> void:
	if placement_preview == null:
		return
	if family.is_empty():
		placement_preview.clear_preview()
		return
	placement_preview.set_preview(family, world_direction_degrees, cell)


func clear_placement_preview() -> void:
	if placement_preview != null:
		placement_preview.clear_preview()


func toggle_debug_overlay() -> void:
	if debug_overlay != null:
		debug_overlay.toggle()


func set_center_cell(cell: Vector2i) -> void:
	if map_background != null and map_background.has_method("set_center_cell"):
		map_background.call("set_center_cell", cell)


func _sync_grid_fill() -> void:
	## Original maps keep diamond fills off so CoC ground/floors show through.
	if map_data != null and map_data.is_original_visual_map() and not show_grid_fill:
		iso_map.set_show_tile_fill(false)
		return
	iso_map.set_show_tile_fill(show_grid_fill)
