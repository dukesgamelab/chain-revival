extends Control
## Asset & Animation Editor — Animations + Map Assets modes.
##
## Animations: single source of truth UI for animation_database.json.
## Map Assets: map_asset_registry.json (shared gameplay + camera visuals).

const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"
const MapAssetEditorPanelScript := preload("res://scripts/editor/map_asset_editor_panel.gd")
const DIRECTIONS: PackedStringArray = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]

enum EditorMode { ANIMATIONS, MAP_ASSETS }

var _family_id: String = ""
var _anim_id: String = ""
var _direction: String = "n"
var _camera_deg: int = 0
var _world_facing: String = "n"
var _playing: bool = false
var _loop: bool = true
var _fps: float = 12.0
var _frame_index: int = 0
var _preview_frames: PackedStringArray = PackedStringArray()
var _dirty: bool = false
var _accum: float = 0.0
var _drag_frame_i: int = -1
var _drag_moved: bool = false
var _mode: int = EditorMode.ANIMATIONS
var _map_assets_panel: Control = null

@onready var _family_list: ItemList = %FamilyList
@onready var _anim_list: ItemList = %AnimList
@onready var _dir_list: ItemList = %DirList
@onready var _timeline: HBoxContainer = %Timeline
@onready var _preview: TextureRect = %Preview
@onready var _status: Label = %StatusLabel
@onready var _fps_slider: HSlider = %FpsSlider
@onready var _fps_value: Label = %FpsValue
@onready var _meta_loop: CheckBox = %MetaLoop
@onready var _meta_notes: TextEdit = %MetaNotes
@onready var _meta_sound: LineEdit = %MetaSound
@onready var _meta_muzzle: SpinBox = %MetaMuzzle
@onready var _meta_footstep: SpinBox = %MetaFootstep
@onready var _meta_move: SpinBox = %MetaMove
@onready var _cam_label: Label = %CamLabel
@onready var _world_facing_option: OptionButton = %WorldFacingOption
@onready var _zoom_slider: HSlider = %ZoomSlider
@onready var _frame_info: Label = %FrameInfo
@onready var _auto_folder: LineEdit = %AutoFolder
@onready var _auto_prefix: LineEdit = %AutoPrefix
@onready var _auto_anim_name: LineEdit = %AutoAnimName
@onready var _main_row: HBoxContainer = %MainRow


func _ready() -> void:
	AnimationDatabase.reload()
	_wire_signals()
	_populate_world_facing()
	_refresh_families()
	_fps_slider.value = 12.0
	_zoom_slider.value = 2.0
	_preview.custom_minimum_size = Vector2(200, 200)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status.text = "Loaded animation_database.json"
	_ensure_map_assets_panel()
	_set_mode(EditorMode.ANIMATIONS)
	set_process(true)


func _wire_signals() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	%SaveButton.pressed.connect(_on_save_pressed)
	%ModeAnimations.pressed.connect(_on_mode_animations)
	%ModeMapAssets.pressed.connect(_on_mode_map_assets)
	%NewFamilyButton.pressed.connect(_on_new_family_pressed)
	%NewAnimButton.pressed.connect(_on_new_anim_pressed)
	%AddFrameButton.pressed.connect(_on_add_frame_pressed)
	%PlayButton.pressed.connect(_on_play_pressed)
	%PauseButton.pressed.connect(_on_pause_pressed)
	%PrevButton.pressed.connect(_on_prev_pressed)
	%NextButton.pressed.connect(_on_next_pressed)
	%Cam0.pressed.connect(_on_cam_pressed.bind(0))
	%Cam90.pressed.connect(_on_cam_pressed.bind(90))
	%Cam180.pressed.connect(_on_cam_pressed.bind(180))
	%Cam270.pressed.connect(_on_cam_pressed.bind(270))
	%AutoDetectButton.pressed.connect(_on_auto_detect_pressed)
	_family_list.item_selected.connect(_on_family_selected)
	_anim_list.item_selected.connect(_on_anim_selected)
	_dir_list.item_selected.connect(_on_dir_selected)
	_fps_slider.value_changed.connect(_on_fps_changed)
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	_world_facing_option.item_selected.connect(_on_world_facing_selected)
	_meta_loop.toggled.connect(func(on: bool) -> void:
		_loop = on
		_mark_dirty()
	)
	_meta_notes.text_changed.connect(_on_meta_changed)
	_meta_sound.text_changed.connect(_on_meta_changed)
	_meta_muzzle.value_changed.connect(_on_meta_changed)
	_meta_footstep.value_changed.connect(_on_meta_changed)
	_meta_move.value_changed.connect(_on_meta_changed)


func _ensure_map_assets_panel() -> void:
	if _map_assets_panel != null:
		return
	var root: VBoxContainer = _main_row.get_parent() as VBoxContainer
	_map_assets_panel = MapAssetEditorPanelScript.new()
	_map_assets_panel.name = "MapAssetsPanel"
	_map_assets_panel.visible = false
	_map_assets_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_assets_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_map_assets_panel)
	_map_assets_panel.status_message.connect(func(text: String) -> void:
		_status.text = text
	)
	_map_assets_panel.dirty_changed.connect(func(is_dirty: bool) -> void:
		if is_dirty and _mode == EditorMode.MAP_ASSETS:
			_status.text = "Unsaved map asset registry changes"
	)


func _on_mode_animations() -> void:
	_set_mode(EditorMode.ANIMATIONS)


func _on_mode_map_assets() -> void:
	_set_mode(EditorMode.MAP_ASSETS)


func _set_mode(mode: int) -> void:
	_mode = mode
	_ensure_map_assets_panel()
	var anim_mode := mode == EditorMode.ANIMATIONS
	_main_row.visible = anim_mode
	_map_assets_panel.visible = not anim_mode
	%ModeAnimations.button_pressed = anim_mode
	%ModeMapAssets.button_pressed = not anim_mode
	if anim_mode:
		_status.text = "Animations mode"
	else:
		_status.text = "Map Assets mode — family registry"


func _process(delta: float) -> void:
	if not _playing or _preview_frames.is_empty():
		return
	var fps := maxf(_fps, 0.1)
	_accum += delta
	var step := 1.0 / fps
	while _accum >= step:
		_accum -= step
		_frame_index += 1
		if _frame_index >= _preview_frames.size():
			if _loop:
				_frame_index = 0
			else:
				_frame_index = _preview_frames.size() - 1
				_playing = false
		_show_preview_frame()


func _populate_world_facing() -> void:
	_world_facing_option.clear()
	for d in DIRECTIONS:
		_world_facing_option.add_item(d.to_upper())
	_world_facing_option.select(0)
	_world_facing = "n"


func _refresh_families() -> void:
	_family_list.clear()
	for fid in AnimationDatabase.family_ids():
		var fam := AnimationDatabase.get_family(fid)
		var label := str(fam.get("label", fid))
		var cat := str(fam.get("category", "soldiers"))
		_family_list.add_item("%s  [%s] · %s" % [label, fid, cat])
		_family_list.set_item_metadata(_family_list.item_count - 1, fid)


func _refresh_anims() -> void:
	_anim_list.clear()
	if _family_id.is_empty():
		return
	var fam := AnimationDatabase.get_family(_family_id)
	var anims: Dictionary = fam.get("animations", {})
	var keys: Array = anims.keys()
	keys.sort()
	for aid in keys:
		var anim: Dictionary = anims[aid]
		_anim_list.add_item(str(anim.get("label", aid)))
		_anim_list.set_item_metadata(_anim_list.item_count - 1, str(aid))


func _refresh_dirs() -> void:
	_dir_list.clear()
	for d in DIRECTIONS:
		var count := AnimationDatabase.get_direction_frames(_family_id, _anim_id, d).size()
		_dir_list.add_item("%s  (%d)" % [d.to_upper(), count])
		_dir_list.set_item_metadata(_dir_list.item_count - 1, d)
	for i in _dir_list.item_count:
		if str(_dir_list.get_item_metadata(i)) == _direction:
			_dir_list.select(i)
			break


func _refresh_timeline() -> void:
	for child in _timeline.get_children():
		child.queue_free()
	var frames := AnimationDatabase.get_direction_frames(_family_id, _anim_id, _direction)
	for i in frames.size():
		var path := frames[i]
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(88, 110)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var thumb := TextureRect.new()
		thumb.custom_minimum_size = Vector2(80, 80)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			thumb.texture = load(path) as Texture2D
		var name_lbl := Label.new()
		name_lbl.text = path.get_file()
		name_lbl.clip_text = true
		name_lbl.custom_minimum_size = Vector2(80, 0)
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var idx_lbl := Label.new()
		idx_lbl.text = "#%d" % i
		idx_lbl.add_theme_font_size_override("font_size", 10)
		idx_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(idx_lbl)
		cell.add_child(thumb)
		cell.add_child(name_lbl)
		cell.gui_input.connect(_on_timeline_cell_gui.bind(i))
		_timeline.add_child(cell)
	_reload_preview_frames()


func _reload_preview_frames() -> void:
	var anim := AnimationDatabase.get_animation(_family_id, _anim_id)
	_loop = bool(anim.get("loop", true))
	_fps = float(anim.get("fps", 12.0))
	_fps_slider.value = _fps
	_fps_value.text = "%.0f" % _fps
	_meta_loop.button_pressed = _loop
	var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	_meta_notes.text = str(meta.get("notes", ""))
	_meta_sound.text = str(meta.get("sound_effect", ""))
	_meta_muzzle.value = int(meta.get("muzzle_flash_frame", -1))
	_meta_footstep.value = int(meta.get("footstep_frame", -1))
	_meta_move.value = float(meta.get("movement_per_cycle", 0.0))
	_apply_preview_source()


func _apply_preview_source() -> void:
	var display := AnimationDatabase.display_direction(_world_facing, _camera_deg)
	_preview_frames = AnimationDatabase.get_direction_frames(_family_id, _anim_id, display)
	_frame_index = clampi(_frame_index, 0, maxi(_preview_frames.size() - 1, 0))
	_cam_label.text = "Cam %d° · world %s → display %s" % [
		_camera_deg, _world_facing.to_upper(), display.to_upper()
	]
	_show_preview_frame()


func _show_preview_frame() -> void:
	if _preview_frames.is_empty():
		_preview.texture = null
		_frame_info.text = "No frames"
		return
	_frame_index = clampi(_frame_index, 0, _preview_frames.size() - 1)
	var path := _preview_frames[_frame_index]
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		_preview.texture = load(path) as Texture2D
	_frame_info.text = "Frame %d / %d — %s" % [
		_frame_index + 1, _preview_frames.size(), path.get_file()
	]


func _mark_dirty() -> void:
	_dirty = true
	_status.text = "Unsaved changes"


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MODE_SELECT_SCENE)


func _on_save_pressed() -> void:
	if _mode == EditorMode.MAP_ASSETS:
		if _map_assets_panel != null:
			_map_assets_panel.save_registry()
		return
	_flush_meta_to_db()
	if AnimationDatabase.save():
		_dirty = false
		UsSoldierSpriteFrames.reload_cached_frames()
		_status.text = "Saved animation_database.json (+ soldier frame cache cleared)"
	else:
		_status.text = "Save failed — check write permissions"


func _flush_meta_to_db() -> void:
	if _family_id.is_empty() or _anim_id.is_empty():
		return
	var anim := AnimationDatabase.get_animation(_family_id, _anim_id)
	if anim.is_empty():
		return
	anim["loop"] = _meta_loop.button_pressed
	anim["fps"] = _fps_slider.value
	var meta: Dictionary = anim.get("metadata", {}) if anim.get("metadata", {}) is Dictionary else {}
	meta["notes"] = _meta_notes.text
	meta["sound_effect"] = _meta_sound.text.strip_edges()
	meta["muzzle_flash_frame"] = int(_meta_muzzle.value)
	meta["footstep_frame"] = int(_meta_footstep.value)
	meta["movement_per_cycle"] = float(_meta_move.value)
	anim["metadata"] = meta
	AnimationDatabase.set_animation(_family_id, _anim_id, anim)


func _on_family_selected(index: int) -> void:
	_flush_meta_to_db()
	_family_id = str(_family_list.get_item_metadata(index))
	_anim_id = ""
	_refresh_anims()
	_dir_list.clear()
	for child in _timeline.get_children():
		child.queue_free()


func _on_anim_selected(index: int) -> void:
	_flush_meta_to_db()
	_anim_id = str(_anim_list.get_item_metadata(index))
	_direction = "n"
	_refresh_dirs()
	_refresh_timeline()


func _on_dir_selected(index: int) -> void:
	_direction = str(_dir_list.get_item_metadata(index))
	_world_facing = _direction
	for i in DIRECTIONS.size():
		if DIRECTIONS[i] == _direction:
			_world_facing_option.select(i)
			break
	_refresh_timeline()


func _timeline_context(frame_i: int) -> void:
	var menu := PopupMenu.new()
	add_child(menu)
	menu.add_item("Delete frame", 0)
	menu.add_item("Duplicate frame", 1)
	menu.add_item("Move left", 2)
	menu.add_item("Move right", 3)
	menu.add_item("Insert frame(s) after…", 4)
	menu.id_pressed.connect(func(id: int) -> void:
		_edit_frame(frame_i, id)
		menu.queue_free()
	)
	menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _edit_frame(frame_i: int, action: int) -> void:
	var frames := Array(AnimationDatabase.get_direction_frames(_family_id, _anim_id, _direction))
	if frame_i < 0 or frame_i >= frames.size():
		return
	match action:
		0:
			frames.remove_at(frame_i)
		1:
			frames.insert(frame_i + 1, frames[frame_i])
		2:
			if frame_i > 0:
				var tmp = frames[frame_i - 1]
				frames[frame_i - 1] = frames[frame_i]
				frames[frame_i] = tmp
		3:
			if frame_i < frames.size() - 1:
				var tmp2 = frames[frame_i + 1]
				frames[frame_i + 1] = frames[frame_i]
				frames[frame_i] = tmp2
		4:
			_insert_frames_at(frame_i + 1)
			return
	_commit_frames(frames)


func _commit_frames(frames: Array) -> void:
	var packed := PackedStringArray()
	for f in frames:
		packed.append(str(f))
	AnimationDatabase.set_direction_frames(_family_id, _anim_id, _direction, packed)
	_mark_dirty()
	_refresh_dirs()
	_refresh_timeline()


func _insert_frames_at(at_index: int) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = PackedStringArray(["*.png ; PNG Images"])
	dialog.title = "Insert frame(s)"
	add_child(dialog)
	dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		var frames := Array(AnimationDatabase.get_direction_frames(_family_id, _anim_id, _direction))
		var insert_at := clampi(at_index, 0, frames.size())
		for i in paths.size():
			frames.insert(insert_at + i, paths[i])
		_commit_frames(frames)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.6)


func _on_add_frame_pressed() -> void:
	if _family_id.is_empty() or _anim_id.is_empty():
		return
	var frames := AnimationDatabase.get_direction_frames(_family_id, _anim_id, _direction)
	_insert_frames_at(frames.size())


func _on_timeline_cell_gui(event: InputEvent, frame_i: int) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_frame_index = frame_i
			_drag_frame_i = frame_i
			_drag_moved = false
			_show_preview_frame()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _drag_moved:
				_refresh_dirs()
				_refresh_timeline()
			_drag_frame_i = -1
			_drag_moved = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_timeline_context(frame_i)
	elif event is InputEventMouseMotion and _drag_frame_i >= 0 and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var local_x := _timeline.get_local_mouse_position().x
		var target := _frame_index_at_x(local_x)
		if target >= 0 and target != _drag_frame_i:
			var frames := Array(AnimationDatabase.get_direction_frames(_family_id, _anim_id, _direction))
			if _drag_frame_i < frames.size() and target < frames.size():
				var item = frames[_drag_frame_i]
				frames.remove_at(_drag_frame_i)
				frames.insert(target, item)
				var packed := PackedStringArray()
				for f in frames:
					packed.append(str(f))
				AnimationDatabase.set_direction_frames(_family_id, _anim_id, _direction, packed)
				_timeline.move_child(_timeline.get_child(_drag_frame_i), target)
				_drag_frame_i = target
				_drag_moved = true
				_mark_dirty()
				_frame_index = target
				_show_preview_frame()


func _frame_index_at_x(x: float) -> int:
	var acc := 0.0
	for i in _timeline.get_child_count():
		var child := _timeline.get_child(i) as Control
		if child == null:
			continue
		var w := maxf(child.size.x, child.custom_minimum_size.x) + 6.0
		if x >= acc and x < acc + w:
			return i
		acc += w
	return -1


func _on_play_pressed() -> void:
	_playing = true
	_accum = 0.0


func _on_pause_pressed() -> void:
	_playing = false


func _on_prev_pressed() -> void:
	_playing = false
	_frame_index = maxi(_frame_index - 1, 0)
	_show_preview_frame()


func _on_next_pressed() -> void:
	_playing = false
	if _preview_frames.is_empty():
		return
	_frame_index = mini(_frame_index + 1, _preview_frames.size() - 1)
	_show_preview_frame()


func _on_fps_changed(value: float) -> void:
	_fps = value
	_fps_value.text = "%.0f" % value
	_mark_dirty()


func _on_zoom_changed(value: float) -> void:
	_preview.custom_minimum_size = Vector2(100, 100) * value


func _on_cam_pressed(degrees: int) -> void:
	_camera_deg = degrees
	_apply_preview_source()


func _on_world_facing_selected(index: int) -> void:
	_world_facing = DIRECTIONS[index]
	_apply_preview_source()


func _on_new_family_pressed() -> void:
	var id := "new_family_%d" % (AnimationDatabase.family_ids().size() + 1)
	var fam := AnimationDatabase.make_empty_family(id, "New Family")
	fam["animations"]["idle"] = AnimationDatabase.make_empty_animation("Idle", true, 1.0)
	AnimationDatabase.upsert_family(fam)
	_mark_dirty()
	_refresh_families()


func _on_new_anim_pressed() -> void:
	if _family_id.is_empty():
		_status.text = "Select a family first"
		return
	var id := "anim_%d" % (Time.get_ticks_msec() % 100000)
	AnimationDatabase.set_animation(
		_family_id, id, AnimationDatabase.make_empty_animation(id.capitalize(), true, 12.0)
	)
	_mark_dirty()
	_refresh_anims()


func _on_auto_detect_pressed() -> void:
	if _family_id.is_empty():
		_status.text = "Select a family first"
		return
	var folder := _auto_folder.text.strip_edges()
	if folder.is_empty():
		folder = "res://assets/sprites/us_soldier/walk"
	var prefix := _auto_prefix.text.strip_edges()
	var anim_name := _auto_anim_name.text.strip_edges()
	if anim_name.is_empty():
		anim_name = "walk"
	AnimationDatabase.ensure_loaded()
	var detected := AnimationDatabase.auto_detect_from_folder(folder, prefix)
	if detected.is_empty():
		_status.text = "Auto Detect found nothing in %s" % folder
		return
	var use_prefix := prefix.to_upper()
	if use_prefix.is_empty():
		use_prefix = str(detected.keys()[0])
	if not detected.has(use_prefix):
		_status.text = "Prefix %s not found (have: %s)" % [use_prefix, ", ".join(detected.keys())]
		return
	var by_dir: Dictionary = detected[use_prefix]
	var anim := AnimationDatabase.get_animation(_family_id, anim_name)
	if anim.is_empty():
		anim = AnimationDatabase.make_empty_animation(anim_name.capitalize(), true, 12.0)
	var dirs: Dictionary = anim.get("directions", {})
	for d in DIRECTIONS:
		var paths: Array = by_dir.get(d, [])
		dirs[d] = {"frames": paths}
	anim["directions"] = dirs
	AnimationDatabase.set_animation(_family_id, anim_name, anim)
	_anim_id = anim_name
	_mark_dirty()
	_refresh_anims()
	_refresh_dirs()
	_refresh_timeline()
	_status.text = "Auto Detect imported %s → %s/%s" % [use_prefix, _family_id, anim_name]


func _on_meta_changed(_v: Variant = null) -> void:
	_mark_dirty()
