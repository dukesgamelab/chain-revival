extends Control
## Chain Revival Editor — edits the same Fortress JSON the game loads.
## Uses MapWorldView (shared renderer). No duplicate facet/hotspot/projection code.

enum Tool {
	PLACE,
	RECT_FILL,
	FLOOD_FILL,
	ERASE,
	SELECT,
	EYEDROPPER,
	SPAWN_USA,
	SPAWN_GER,
	VICTORY,
	LABEL,
}

const EDITOR_SCENE := "res://scenes/editor/map_editor.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"
const MAP_WORLD_SCENE := preload("res://scenes/map/map_world.tscn")

@onready var _asset_tree: Tree = %AssetTree
@onready var _asset_context: PopupMenu = %AssetContextMenu
@onready var _rename_asset_button: Button = %RenameAssetButton
@onready var _rename_dialog: ConfirmationDialog = %RenameAssetDialog
@onready var _tool_option: OptionButton = %ToolOption
@onready var _status: Label = %StatusLabel
@onready var _coord_label: Label = %CoordLabel
@onready var _search: LineEdit = %SearchField
@onready var _viewport_host: SubViewportContainer = %MapViewportContainer
@onready var _subviewport: SubViewport = %MapViewport
@onready var _camera: MapCamera = %EditorCamera
@onready var _inspector: VBoxContainer = %InspectorFields
@onready var _grid_toggle: CheckButton = %GridToggle
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _validation_label: Label = %ValidationLabel
@onready var _back_button: Button = %BackButton
@onready var _new_button: Button = %NewButton
@onready var _open_button: Button = %OpenButton
@onready var _save_button: Button = %SaveButton
@onready var _save_as_button: Button = %SaveAsButton
@onready var _play_button: Button = %PlayButton

var _world: MapWorldView
var _map_data: MapData
var _map_path: String = MapData.DEV_MAP_FILE
var _history := EditorHistory.new()
var _tool: int = Tool.PLACE
var _brush: Dictionary = {} ## AssetBrowser item
var _selection: Array[Vector2i] = []
var _clipboard: Array[Dictionary] = []
var _rect_anchor: Vector2i = Vector2i(-1, -1)
var _painting: bool = false
var _dirty: bool = false
var _show_grid: bool = false
var _inspector_cell: Vector2i = Vector2i(-1, -1)
var _brush_direction: int = 0
var _rename_line: LineEdit
var _rename_family: String = ""
var _asset_rebuild_pending: bool = false
var _pending_asset_filter: String = ""


func _ready() -> void:
	MapCoordinateTransform.reset_candidate()
	IsometricGrid.reset_view_rotation()
	_setup_world()
	_setup_tools()
	_setup_asset_browser()
	_back_button.pressed.connect(_on_back_pressed)
	_new_button.pressed.connect(_on_new_pressed)
	_open_button.pressed.connect(_on_open_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_save_as_button.pressed.connect(_on_save_as_pressed)
	_play_button.pressed.connect(_on_play_pressed)
	_file_dialog.file_selected.connect(_on_file_selected)
	_search.text_changed.connect(_on_search_changed)
	_tool_option.item_selected.connect(_on_tool_selected)
	_grid_toggle.toggled.connect(_on_grid_toggled)
	_viewport_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_host.gui_input.connect(_on_viewport_gui_input)
	_load_map(_map_path)
	set_process_input(true)
	set_process_unhandled_input(true)


func _setup_asset_browser() -> void:
	AssetBrowserCatalog.reload()
	_asset_tree.item_selected.connect(_on_asset_selected)
	_asset_tree.item_mouse_selected.connect(_on_asset_mouse_selected)
	_asset_tree.allow_rmb_select = true
	## Mouse/wheel scroll only — arrow keys must not walk the asset list.
	_asset_tree.focus_mode = Control.FOCUS_NONE
	_asset_tree.gui_input.connect(_on_asset_tree_gui_input)
	## Do not mark items editable — click must select the brush, not rename.
	_asset_context.id_pressed.connect(_on_asset_context_id)
	_rename_asset_button.pressed.connect(_open_rename_dialog)
	_rename_line = LineEdit.new()
	_rename_line.placeholder_text = "Display name"
	_rename_dialog.add_child(_rename_line)
	_rename_dialog.confirmed.connect(_on_rename_dialog_confirmed)
	_populate_assets()


func _on_asset_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END:
				_asset_tree.accept_event()


func _on_viewport_gui_input(event: InputEvent) -> void:
	## Mouse paint/select against the shared MapWorldView (keys stay on unhandled_input).
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_handle_mouse_editor_input(event)
		_viewport_host.accept_event()


func _setup_world() -> void:
	_world = MAP_WORLD_SCENE.instantiate() as MapWorldView
	_subviewport.add_child(_world)
	# Camera is sibling under SubViewport for MapCamera pan/zoom.
	if _camera.get_parent() != _subviewport:
		_camera.reparent(_subviewport)
	_camera.make_current()


func _setup_tools() -> void:
	_tool_option.clear()
	for label in [
		"Place", "Rectangle Fill", "Flood Fill", "Erase", "Select",
		"Eyedropper", "USA Spawn", "Germany Spawn", "Victory Point", "Label",
	]:
		_tool_option.add_item(label)
	_tool_option.select(Tool.PLACE)


func _populate_assets(filter_text: String = "") -> void:
	## Defer rebuilds — clearing the Tree during search/edit callbacks can yield a null root.
	if not is_inside_tree() or _asset_tree == null:
		return
	_pending_asset_filter = filter_text
	if _asset_rebuild_pending:
		return
	_asset_rebuild_pending = true
	call_deferred("_populate_assets_now")


func _populate_assets_now() -> void:
	_asset_rebuild_pending = false
	if not is_instance_valid(_asset_tree) or not _asset_tree.is_inside_tree():
		return
	_asset_tree.clear()
	var root := _asset_tree.get_root()
	if root == null:
		root = _asset_tree.create_item()
	if root == null:
		push_warning("MapEditor: AssetTree root could not be created")
		return

	var categories := AssetBrowserCatalog.build_categories(_map_data)
	var filter := _pending_asset_filter.strip_edges().to_lower()
	var shown := 0
	for cat in AssetBrowserCatalog.category_order():
		var items: Array = categories.get(cat, [])
		if items.is_empty() and cat != "On This Map":
			continue
		var cat_item: TreeItem = null
		var child_count := 0
		for entry in items:
			var label := str(entry.get("label", ""))
			var family := str(entry.get("family", ""))
			if not filter.is_empty() and label.to_lower().find(filter) < 0 \
					and family.to_lower().find(filter) < 0 \
					and str(entry.get("edit_label", "")).to_lower().find(filter) < 0:
				continue
			if cat_item == null:
				cat_item = _asset_tree.create_item(root)
				if cat_item == null:
					continue
				cat_item.set_text(0, cat)
				cat_item.set_selectable(0, false)
				cat_item.set_collapsed(false)
			var item := _asset_tree.create_item(cat_item)
			if item == null:
				continue
			item.set_text(0, label)
			item.set_metadata(0, entry)
			item.set_editable(0, false)
			child_count += 1
			shown += 1
		if cat_item != null:
			cat_item.set_text(0, "%s (%d)" % [cat, child_count])
	if shown == 0 and not filter.is_empty():
		var empty := _asset_tree.create_item(root)
		if empty != null:
			empty.set_text(0, "(no matches)")
			empty.set_selectable(0, false)


func _load_map(path: String) -> void:
	_map_path = path
	_map_data = MapLoader.load_path(path)
	if _map_data == null:
		_map_data = MapLoader.create_blank()
	_history.clear()
	_world.apply_map_data(_map_data)
	_camera.set_map_size(_map_data.width, _map_data.height)
	var focus := Vector2i(_map_data.width / 2, _map_data.height / 2)
	if not _map_data.team_1_spawn_points.is_empty():
		focus = _map_data.team_1_spawn_points[0]
	_camera.reset_to_default_view(IsometricGrid.grid_to_world(focus))
	_dirty = false
	_selection.clear()
	## Rebuild browser so "On This Map" lists every family used by this map.
	_populate_assets(_search.text if _search else "")
	_refresh_validation()
	_status.text = "Loaded %s" % path.get_file()


func _save_map(path: String = "") -> void:
	if not path.is_empty():
		_map_path = path
	if MapData.save_to_file(_map_data, _map_path):
		_dirty = false
		_status.text = "Saved %s" % _map_path.get_file()
		_refresh_validation()
	else:
		_status.text = "Save failed: %s" % _map_path


func _push_history() -> void:
	_history.push(_map_data)


func _refresh_world() -> void:
	_world.refresh_presentation()
	_dirty = true
	_refresh_validation()


func _apply_history_map(next: MapData, status: String) -> void:
	## Undo/redo returns a new MapData — must re-bind the world, not just refresh.
	_map_data = next
	_world.apply_map_data(_map_data)
	_dirty = true
	_refresh_validation()
	_populate_assets(_search.text if _search else "")
	if _inspector_cell.x >= 0:
		_rebuild_inspector()
	_status.text = status


func _refresh_validation() -> void:
	var report := MapValidator.validate_and_log(_map_data)
	var warns: Array = report.get("warnings", [])
	var errs: Array = report.get("errors", [])
	_validation_label.text = "Validation: %d warnings, %d errors" % [warns.size(), errs.size()]


func _cell_at_mouse() -> Vector2i:
	var local := _subviewport.get_mouse_position()
	var world: Vector2 = _camera.position + (local - Vector2(_subviewport.size) * 0.5) / _camera.zoom.x
	return IsometricGrid.world_to_cell_at_point(world)


func _editor_dialogs_open() -> bool:
	return (
		(_rename_dialog != null and _rename_dialog.visible)
		or (_file_dialog != null and _file_dialog.visible)
		or (_asset_context != null and _asset_context.visible)
	)


func _input(event: InputEvent) -> void:
	## Handle map shortcuts before focused controls (Search/Tree) swallow them.
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _editor_dialogs_open():
		return
	var key := event as InputEventKey
	if key.ctrl_pressed and key.keycode == KEY_Z and not key.shift_pressed:
		var undone := _history.undo(_map_data)
		if undone != null:
			_apply_history_map(undone, "Undo")
		get_viewport().set_input_as_handled()
		return
	if key.ctrl_pressed and (key.keycode == KEY_Y or (key.keycode == KEY_Z and key.shift_pressed)):
		var redone := _history.redo(_map_data)
		if redone != null:
			_apply_history_map(redone, "Redo")
		get_viewport().set_input_as_handled()
		return
	if key.ctrl_pressed and key.keycode == KEY_S:
		_save_map()
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_C:
			_copy_selection()
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.keycode == KEY_V:
			_paste_at(_cell_at_mouse())
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selection()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R:
			_brush_direction = posmod(_brush_direction + 90, 360)
			_status.text = "Brush direction %d° (world)" % _brush_direction
			_refresh_placement_preview(_cell_at_mouse())
			if _inspector_cell.x >= 0:
				_rebuild_inspector()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			_open_rename_dialog()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("rotate_view_left"):
			_rotate_view(true)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("rotate_view_right"):
			_rotate_view(false)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F3:
			_world.toggle_debug_overlay()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F4:
			_world.toggle_handedness_overlay()
			_status.text = "Handedness overlay toggled (F5 cycles transform candidates)"
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5:
			var cand := _world.cycle_handedness_candidate()
			_status.text = (
				"Handedness: %s — compare OG at Cam 0° (Q/E). Default A needs 0 presses."
				% cand
			)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file(MODE_SELECT_SCENE)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_handle_mouse_editor_input(event)


func _handle_mouse_editor_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_at_mouse()
		_coord_label.text = "Cell %s  Cam %d°  BrushDir %d°" % [
			cell,
			IsometricGrid.camera_direction_degrees(),
			_brush_direction,
		]
		if _world != null:
			_world.set_handedness_selected_cell(cell)
		if _map_data != null and _map_data.is_in_bounds(cell):
			_world.set_hover_cell(cell)
			_refresh_placement_preview(cell)
		else:
			_world.clear_hover()
			_world.clear_placement_preview()
		if _painting and _tool in [Tool.PLACE, Tool.ERASE]:
			_apply_tool_at(cell, false)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var cell := _cell_at_mouse()
			if mb.pressed:
				_painting = true
				_apply_tool_at(cell, true)
			else:
				_painting = false
				_rect_anchor = Vector2i(-1, -1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_push_history()
			_map_data.erase_all_at(_cell_at_mouse(), _tool == Tool.ERASE)
			_refresh_world()


func _rotate_view(left: bool) -> void:
	var focus := IsometricGrid.world_to_logical_point(_camera.position)
	if left:
		IsometricGrid.rotate_view_left()
	else:
		IsometricGrid.rotate_view_right()
	## Shared MapWorldView rebuilds every object via CocSpriteResolver (no editor facet logic).
	_world.refresh_view_rotation()
	_camera.center_on_world(IsometricGrid.logical_point_to_world(focus))
	_refresh_placement_preview(_cell_at_mouse())
	if _inspector_cell.x >= 0:
		_rebuild_inspector()
	_status.text = "Camera %d° — facets re-resolved (world dirs unchanged)" % IsometricGrid.camera_direction_degrees()


func _apply_tool_at(cell: Vector2i, is_click: bool) -> void:
	if _map_data == null or not _map_data.is_in_bounds(cell):
		return
	match _tool:
		Tool.PLACE:
			_place_brush(cell, is_click)
		Tool.ERASE:
			if is_click:
				_push_history()
			_map_data.erase_all_at(cell, true)
			_refresh_world()
		Tool.RECT_FILL:
			_rect_fill(cell, is_click)
		Tool.FLOOD_FILL:
			if is_click:
				_flood_fill(cell)
		Tool.SELECT:
			_select_cell(cell, is_click)
		Tool.EYEDROPPER:
			if is_click:
				_eyedrop(cell)
		Tool.SPAWN_USA:
			if is_click:
				_push_history()
				if cell not in _map_data.team_1_spawn_points:
					_map_data.team_1_spawn_points.append(cell)
				_refresh_world()
		Tool.SPAWN_GER:
			if is_click:
				_push_history()
				if cell not in _map_data.team_2_spawn_points:
					_map_data.team_2_spawn_points.append(cell)
				_refresh_world()
		Tool.VICTORY:
			if is_click:
				_push_history()
				_map_data.victory_points.append({"x": cell.x, "y": cell.y, "name": "VP"})
				_refresh_world()
		Tool.LABEL:
			if is_click:
				_push_history()
				_map_data.labels.append({"x": cell.x, "y": cell.y, "text": "Label"})
				_refresh_world()
	if is_click and _tool in [Tool.PLACE, Tool.SELECT, Tool.EYEDROPPER]:
		_inspector_cell = cell
		_rebuild_inspector()


func _refresh_placement_preview(cell: Vector2i) -> void:
	if _world == null or _map_data == null or not _map_data.is_in_bounds(cell):
		if _world != null:
			_world.clear_placement_preview()
		return
	if _tool != Tool.PLACE and _tool != Tool.RECT_FILL and _tool != Tool.FLOOD_FILL:
		_world.clear_placement_preview()
		return
	var family := str(_brush.get("family", "")).to_upper()
	var kind := str(_brush.get("kind", ""))
	if family.is_empty() or kind in ["spawn_usa", "spawn_ger", "victory", "label", "terrain"]:
		_world.clear_placement_preview()
		return
	_world.set_placement_preview(family, _brush_direction, cell)


func _place_brush(cell: Vector2i, is_click: bool) -> void:
	if _brush.is_empty():
		return
	var kind := str(_brush.get("kind", ""))
	if kind == "spawn_usa":
		_tool = Tool.SPAWN_USA
		_apply_tool_at(cell, is_click)
		return
	if kind == "spawn_ger":
		_tool = Tool.SPAWN_GER
		_apply_tool_at(cell, is_click)
		return
	if kind == "victory":
		_tool = Tool.VICTORY
		_apply_tool_at(cell, is_click)
		return
	if kind == "label":
		_tool = Tool.LABEL
		_apply_tool_at(cell, is_click)
		return
	var family := str(_brush.get("family", "")).to_upper()
	if family.is_empty():
		return
	if is_click:
		_push_history()
	## Always replace existing authored content on the cell.
	if kind == "terrain" or family == "GRS":
		_map_data.place_ground_clear(cell)
	elif CocRenderRules.is_floor_family(family):
		_map_data.place_floor_tile(cell, family, _brush_direction)
	else:
		_map_data.place_family_object(cell, family, _brush_direction)
	_refresh_world()


func _rect_fill(cell: Vector2i, is_click: bool) -> void:
	if is_click and _rect_anchor.x < 0:
		_rect_anchor = cell
		_status.text = "Rect anchor %s — click opposite corner" % cell
		return
	if not is_click:
		return
	_push_history()
	var a := _rect_anchor
	var x0 := mini(a.x, cell.x)
	var x1 := maxi(a.x, cell.x)
	var y0 := mini(a.y, cell.y)
	var y1 := maxi(a.y, cell.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_place_brush(Vector2i(x, y), false)
	_rect_anchor = Vector2i(-1, -1)
	_refresh_world()


func _flood_fill(cell: Vector2i) -> void:
	if _brush.is_empty():
		return
	var family := str(_brush.get("family", "")).to_upper()
	if family.is_empty():
		return
	_push_history()
	var target_floor := _map_data.get_floor_at(cell)
	var target_obj := _map_data.get_visual_at(cell)
	var target_key := "%s|%s" % [
		str(target_floor.get("image", "")),
		str(target_obj.get("family", "")),
	]
	var stack: Array[Vector2i] = [cell]
	var seen: Dictionary = {}
	var count := 0
	while not stack.is_empty() and count < 4000:
		var c: Vector2i = stack.pop_back()
		if seen.has(c) or not _map_data.is_in_bounds(c):
			continue
		seen[c] = true
		var fl := _map_data.get_floor_at(c)
		var ob := _map_data.get_visual_at(c)
		var key := "%s|%s" % [str(fl.get("image", "")), str(ob.get("family", ""))]
		if key != target_key:
			continue
		if CocRenderRules.is_floor_family(family):
			_map_data.place_floor_tile(c, family, _brush_direction)
		else:
			_map_data.place_family_object(c, family, _brush_direction)
		count += 1
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))
	_refresh_world()
	_status.text = "Flood filled %d cells" % count


func _select_cell(cell: Vector2i, is_click: bool) -> void:
	if not is_click:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		if cell in _selection:
			_selection.erase(cell)
		else:
			_selection.append(cell)
	else:
		_selection = [cell]
	_inspector_cell = cell
	_rebuild_inspector()
	_status.text = "Selected %d cell(s)" % _selection.size()


func _eyedrop(cell: Vector2i) -> void:
	var vis := _map_data.get_visual_at(cell)
	if not vis.is_empty():
		_brush = {
			"family": str(vis.get("family", "")),
			"label": str(vis.get("family", "")),
			"kind": "family",
		}
		_brush_direction = int(vis.get("direction", 0))
		_tool = Tool.PLACE
		_tool_option.select(Tool.PLACE)
		_status.text = "Picked %s dir=%d" % [_brush["family"], _brush_direction]
		return
	var fl := _map_data.get_floor_at(cell)
	if not fl.is_empty():
		_brush = {
			"family": str(fl.get("image", "")),
			"label": str(fl.get("image", "")),
			"kind": "family",
		}
		_brush_direction = int(fl.get("direction", 0))
		_tool = Tool.PLACE
		_tool_option.select(Tool.PLACE)
		_status.text = "Picked floor %s" % _brush["family"]


func _copy_selection() -> void:
	_clipboard.clear()
	for cell in _selection:
		var vis := _map_data.get_visual_at(cell)
		var fl := _map_data.get_floor_at(cell)
		_clipboard.append({"cell": cell, "visual": vis.duplicate(true), "floor": fl.duplicate(true)})
	_status.text = "Copied %d" % _clipboard.size()


func _paste_at(origin: Vector2i) -> void:
	if _clipboard.is_empty():
		return
	_push_history()
	var base: Vector2i = _clipboard[0]["cell"]
	for entry in _clipboard:
		var src_cell: Vector2i = entry["cell"]
		var dest := origin + (src_cell - base)
		if not _map_data.is_in_bounds(dest):
			continue
		var fl: Dictionary = entry.get("floor", {})
		if not fl.is_empty():
			_map_data.place_floor_tile(dest, str(fl.get("image", "")), int(fl.get("direction", 0)))
		var vis: Dictionary = entry.get("visual", {})
		if not vis.is_empty():
			_map_data.place_family_object(
				dest,
				str(vis.get("family", "")),
				int(vis.get("direction", 0)),
				str(vis.get("image1", "")),
				int(vis.get("z", 0)),
			)
	_refresh_world()


func _delete_selection() -> void:
	if _selection.is_empty():
		return
	_push_history()
	for cell in _selection:
		_map_data.erase_all_at(cell, true)
	_selection.clear()
	_refresh_world()


func _rebuild_inspector() -> void:
	for child in _inspector.get_children():
		child.queue_free()
	if _inspector_cell.x < 0 or _map_data == null or not _map_data.is_in_bounds(_inspector_cell):
		_add_inspector_label("No selection")
		return
	var cell := _inspector_cell
	_add_inspector_label("Cell %s" % cell)
	var vis := _map_data.get_visual_at(cell)
	var fl := _map_data.get_floor_at(cell)
	var def := MapObjectDefinition.from_placement(vis) if not vis.is_empty() else MapObjectDefinition.new()
	if not fl.is_empty() and def.family.is_empty():
		def.family = str(fl.get("image", ""))
		def.direction = int(fl.get("direction", 0))
	_add_field("Family", def.family, func(v: String) -> void: _apply_inspector_family(cell, v))
	_add_int_field("Direction", def.direction, func(v: int) -> void: _apply_inspector_direction(cell, v))
	_add_field("Image1", def.image1, func(v: String) -> void: _apply_inspector_image1(cell, v))
	_add_int_field("Z", def.z, func(v: int) -> void: _apply_inspector_z(cell, v))
	_add_field("Material", def.material, func(v: String) -> void: _set_source_field(cell, "material", v))
	_add_field("Height", def.height_band, func(v: String) -> void: _set_source_field(cell, "height_band", v))
	_add_field("LOS", def.los_mode, func(v: String) -> void: _set_source_field(cell, "los_mode", v))
	_add_field("Penetration", def.bullet_penetration, func(v: String) -> void: _set_source_field(cell, "bullet_penetration", v))
	_add_field("Movement Cost", def.movement_cost, func(v: String) -> void: _set_source_field(cell, "movement_cost", v))
	_add_field("Comments", def.comments, func(v: String) -> void: _set_source_field(cell, "comments", v))
	if def.family.is_empty():
		_add_inspector_label("Resolved: (none)")
	else:
		var resolved := CocSpriteResolver.resolve_placement(def.family, def.direction, def.image1)
		_add_inspector_label(
			"Display letter @ cam %d°: %s"
			% [int(resolved.get("camera_direction", 0)), str(resolved.get("letter", "-"))]
		)
		_add_inspector_label("World direction: %d° (unchanged by camera)" % def.direction)
		_add_inspector_label("PNG: %s" % str(resolved.get("path", "-")).get_file())
		_add_inspector_label("Hotspot: %s" % str(resolved.get("hotspot", "-")))
		if not str(resolved.get("image1", "")).is_empty():
			var under: Dictionary = resolved.get("image1_resolve", {})
			_add_inspector_label("Image1 PNG: %s" % str(under.get("path", "-")).get_file())


func _add_inspector_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector.add_child(label)


func _add_field(title: String, value: String, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = title
	lab.custom_minimum_size = Vector2(96, 0)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = value
	edit.text_submitted.connect(func(t: String) -> void:
		_push_history()
		setter.call(t)
		_refresh_world()
		_rebuild_inspector()
	)
	row.add_child(lab)
	row.add_child(edit)
	_inspector.add_child(row)


func _add_int_field(title: String, value: int, setter: Callable) -> void:
	_add_field(title, str(value), func(t: String) -> void: setter.call(int(t)))


func _apply_inspector_family(cell: Vector2i, family: String) -> void:
	var vis := _map_data.get_visual_at(cell)
	var dir := int(vis.get("direction", 0))
	var image1 := str(vis.get("image1", ""))
	var z := int(vis.get("z", 0))
	if CocRenderRules.is_floor_family(family):
		_map_data.place_floor_tile(cell, family, dir)
	else:
		_map_data.place_family_object(cell, family, dir, image1, z)


func _apply_inspector_direction(cell: Vector2i, direction: int) -> void:
	var vis := _map_data.get_visual_at(cell)
	if vis.is_empty():
		var fl := _map_data.get_floor_at(cell)
		if not fl.is_empty():
			_map_data.place_floor_tile(cell, str(fl.get("image", "")), direction)
		return
	_map_data.place_family_object(
		cell,
		str(vis.get("family", "")),
		direction,
		str(vis.get("image1", "")),
		int(vis.get("z", 0)),
	)


func _apply_inspector_image1(cell: Vector2i, image1: String) -> void:
	var vis := _map_data.get_visual_at(cell)
	if vis.is_empty():
		return
	_map_data.place_family_object(
		cell,
		str(vis.get("family", "")),
		int(vis.get("direction", 0)),
		image1,
		int(vis.get("z", 0)),
	)


func _apply_inspector_z(cell: Vector2i, z: int) -> void:
	var vis := _map_data.get_visual_at(cell)
	if vis.is_empty():
		return
	_map_data.place_family_object(
		cell,
		str(vis.get("family", "")),
		int(vis.get("direction", 0)),
		str(vis.get("image1", "")),
		z,
	)


func _set_source_field(cell: Vector2i, key: String, value: String) -> void:
	var vis := _map_data.get_visual_at(cell)
	if vis.is_empty():
		return
	var gameplay := {key: value}
	_map_data.place_family_object(
		cell,
		str(vis.get("family", "")),
		int(vis.get("direction", 0)),
		str(vis.get("image1", "")),
		int(vis.get("z", 0)),
		gameplay,
	)


func _on_asset_selected() -> void:
	var item := _asset_tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta == null or not meta is Dictionary:
		return
	_brush = meta
	var kind := str(_brush.get("kind", ""))
	match kind:
		"spawn_usa":
			_tool = Tool.SPAWN_USA
			_tool_option.select(Tool.SPAWN_USA)
		"spawn_ger":
			_tool = Tool.SPAWN_GER
			_tool_option.select(Tool.SPAWN_GER)
		"victory":
			_tool = Tool.VICTORY
			_tool_option.select(Tool.VICTORY)
		"label":
			_tool = Tool.LABEL
			_tool_option.select(Tool.LABEL)
		_:
			_tool = Tool.PLACE
			_tool_option.select(Tool.PLACE)
	_status.text = "Brush: %s" % str(_brush.get("label", ""))


func _selected_renamable_meta() -> Dictionary:
	var item := _asset_tree.get_selected()
	if item == null:
		return {}
	var meta = item.get_metadata(0)
	if meta == null or not meta is Dictionary:
		return {}
	var kind := str(meta.get("kind", ""))
	if kind not in ["family", "terrain"]:
		return {}
	return meta


func _open_rename_dialog() -> void:
	var meta := _selected_renamable_meta()
	if meta.is_empty():
		_status.text = "Select a tile family first, then click Rename Selected"
		return
	_rename_family = str(meta.get("family", "")).to_upper()
	var current := str(meta.get("edit_label", meta.get("label", _rename_family)))
	var code_suffix := "  [%s]" % _rename_family
	if current.ends_with(code_suffix):
		current = current.substr(0, current.length() - code_suffix.length()).strip_edges()
	_rename_line.text = current
	_rename_dialog.title = "Rename %s" % _rename_family
	_rename_dialog.popup_centered(Vector2i(360, 120))
	_rename_line.grab_focus()
	_rename_line.select_all()


func _on_rename_dialog_confirmed() -> void:
	var typed := _rename_line.text.strip_edges()
	if _rename_family.is_empty() or typed.is_empty():
		return
	if AssetBrowserCatalog.rename_family(_rename_family, typed):
		_status.text = "Renamed %s → %s (saved to editor_asset_catalog.json)" % [_rename_family, typed]
		_brush["family"] = _rename_family
		_brush["edit_label"] = typed
		_brush["label"] = (
			"%s  [%s]" % [typed, _rename_family]
			if typed.to_upper().find(_rename_family) < 0
			else typed
		)
		_populate_assets(_search.text)
	else:
		_status.text = "Could not save rename for %s" % _rename_family


func _on_asset_mouse_selected(_mouse_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var meta := _selected_renamable_meta()
	if meta.is_empty():
		return
	_asset_context.clear()
	_asset_context.add_item("Rename…", 0)
	_asset_context.add_separator()
	var idx := 1
	for cat in AssetBrowserCatalog.category_order():
		if cat == "On This Map" or cat in ["Spawn Points", "Victory Points", "Labels"]:
			continue
		_asset_context.add_item("Move to %s" % cat, idx)
		_asset_context.set_item_metadata(idx, cat)
		idx += 1
	_asset_context.position = Vector2i(_asset_tree.get_global_mouse_position())
	_asset_context.reset_size()
	_asset_context.popup()


func _on_asset_context_id(id: int) -> void:
	var meta := _selected_renamable_meta()
	if meta.is_empty():
		return
	var family := str(meta.get("family", "")).to_upper()
	if id == 0:
		_open_rename_dialog()
		return
	var cat := str(_asset_context.get_item_metadata(id))
	if cat.is_empty():
		return
	if AssetBrowserCatalog.set_family_category(family, cat):
		_status.text = "Moved %s → %s" % [family, cat]
		_populate_assets(_search.text)


func _on_tool_selected(index: int) -> void:
	_tool = index
	_rect_anchor = Vector2i(-1, -1)


func _on_search_changed(text: String) -> void:
	_populate_assets(text)


func _on_grid_toggled(on: bool) -> void:
	_show_grid = on
	_world.set_grid_visible(on)


func _on_open_pressed() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.current_path = _map_path
	_file_dialog.popup_centered_ratio(0.6)


func _on_save_pressed() -> void:
	_save_map()


func _on_save_as_pressed() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_path = _map_path
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		_load_map(path)
	else:
		_save_map(path)


func _on_play_pressed() -> void:
	_save_map()
	EditorPlaySession.request_play(_map_path)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_new_pressed() -> void:
	_push_history()
	_map_data = MapLoader.create_blank(100, 100, "untitled")
	_map_path = "res://maps/untitled.json"
	_world.apply_map_data(_map_data)
	_populate_assets(_search.text if _search else "")
	_dirty = true
	_status.text = "New blank map"


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MODE_SELECT_SCENE)
