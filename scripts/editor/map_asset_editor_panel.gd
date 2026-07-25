class_name MapAssetEditorPanel
extends HBoxContainer
## Map Assets mode for the Asset & Animation Editor.
## Edits map_asset_registry.json: shared gameplay + per-camera visuals.

signal status_message(text: String)
signal dirty_changed(is_dirty: bool)

const MapAssetRegistryClass := preload("res://scripts/map/map_asset_registry.gd")
const CocTileCatalogClass := preload("res://scripts/map/coc_tile_catalog.gd")
const CAMERA_DEGS: Array[int] = [0, 90, 180, 270]

var _dirty: bool = false
var _family: String = ""
var _category_filter: String = "All"
var _search: String = ""
var _loading_ui: bool = false
var _large_cam: int = 0
var _show_neighbors: bool = false

var _family_list: ItemList
var _search_edit: LineEdit
var _category_option: OptionButton
var _tab: TabContainer
var _display_name: LineEdit
var _category_edit: LineEdit
var _material_edit: LineEdit
var _height_band: LineEdit
var _notes: TextEdit
var _terrain_option: OptionButton
var _height_spin: SpinBox
var _blocks_move: CheckBox
var _blocks_los: CheckBox
var _blocks_bullets: CheckBox
var _provides_cover: CheckBox
var _cover_type: OptionButton
var _concealment: SpinBox
var _suppression: SpinBox
var _variant_facet_label: Dictionary = {} ## cam -> Label
var _variant_pick_btn: Dictionary = {} ## cam -> Button
var _variant_hot_x: Dictionary = {}
var _variant_hot_y: Dictionary = {}
var _variant_off_x: Dictionary = {}
var _variant_off_y: Dictionary = {}
var _variant_depth: Dictionary = {}
var _variant_preview: Dictionary = {} ## cam -> TextureRect
var _variant_warn: Dictionary = {} ## cam -> Label
var _variant_selection: Dictionary = {} ## cam -> {family, letter, facet, path, hotspot}
var _large_preview: TextureRect
var _large_cam_option: OptionButton
var _audit_label: Label
var _sprite_popup: PopupPanel
var _sprite_search: LineEdit
var _sprite_family_only: CheckBox
var _sprite_grid: GridContainer
var _sprite_status: Label
var _picker_cam: int = -1


func _ready() -> void:
	MapAssetRegistryClass.reload()
	CocTileCatalogClass.ensure_loaded()
	_build_ui()
	_refresh_family_list()
	_refresh_audit()


func is_dirty() -> bool:
	return _dirty


func save_registry() -> Error:
	var err := MapAssetRegistryClass.save()
	if err == OK:
		_set_dirty(false)
		status_message.emit(
			"Saved map_asset_registry.json (shared gameplay). Map placements inherit on load; use Map Editor → Refresh from Asset Registry to strip legacy source fields."
		)
	else:
		status_message.emit("Save failed for map_asset_registry.json")
	return err


func _build_ui() -> void:
	## This panel IS an HBoxContainer so children actually receive expand layout.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_theme_constant_override("separation", 6)
	add_child(left)

	var left_header := Label.new()
	left_header.text = "Farm Fight (FF) Families"
	left_header.add_theme_font_size_override("font_size", 16)
	left.add_child(left_header)

	var left_sub := Label.new()
	left_sub.text = "Static CoC map objects from ff_farm.json"
	left_sub.add_theme_font_size_override("font_size", 11)
	left_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(left_sub)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search FF family (WH00, WWAL…)"
	_search_edit.text_changed.connect(_on_search_changed)
	left.add_child(_search_edit)

	_category_option = OptionButton.new()
	_category_option.item_selected.connect(_on_category_selected)
	left.add_child(_category_option)

	_family_list = ItemList.new()
	_family_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_family_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_family_list.custom_minimum_size = Vector2(0, 280)
	_family_list.item_selected.connect(_on_family_selected)
	left.add_child(_family_list)

	var audit_btn := Button.new()
	audit_btn.text = "Registry Audit"
	audit_btn.pressed.connect(_refresh_audit)
	left.add_child(audit_btn)

	_audit_label = Label.new()
	_audit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_audit_label.add_theme_font_size_override("font_size", 11)
	left.add_child(_audit_label)

	_tab = TabContainer.new()
	_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tab)

	_tab.add_child(_build_visual_tab())
	_tab.set_tab_title(0, "Visual Variants")
	_tab.add_child(_build_gameplay_tab())
	_tab.set_tab_title(1, "Gameplay")
	_build_sprite_picker_popup()


func _build_visual_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	## Fit scroll width so the 4-camera row can expand instead of staying tiny.
	col.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scroll.add_child(col)
	scroll.resized.connect(func() -> void:
		col.custom_minimum_size.x = maxf(scroll.size.x - 8.0, 800.0)
	)

	var meta_row := HBoxContainer.new()
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(meta_row)
	_display_name = LineEdit.new()
	_display_name.placeholder_text = "Display name"
	_display_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display_name.text_changed.connect(func(_t: String) -> void: _on_meta_edited())
	meta_row.add_child(_display_name)

	var variants_label := Label.new()
	variants_label.text = "Camera variants (presentation only)"
	variants_label.add_theme_font_size_override("font_size", 14)
	col.add_child(variants_label)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	for cam in CAMERA_DEGS:
		row.add_child(_build_variant_card(cam))

	var large_box := VBoxContainer.new()
	large_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(large_box)
	var large_header := HBoxContainer.new()
	large_box.add_child(large_header)
	var large_label := Label.new()
	large_label.text = "Large preview"
	large_header.add_child(large_label)
	_large_cam_option = OptionButton.new()
	for cam in CAMERA_DEGS:
		_large_cam_option.add_item("Camera %d°" % cam, cam)
	_large_cam_option.item_selected.connect(_on_large_cam_selected)
	large_header.add_child(_large_cam_option)
	var neighbor_cb := CheckBox.new()
	neighbor_cb.text = "Neighbor tiles"
	neighbor_cb.toggled.connect(func(on: bool) -> void:
		_show_neighbors = on
		_refresh_large_preview()
	)
	large_header.add_child(neighbor_cb)

	_large_preview = TextureRect.new()
	_large_preview.custom_minimum_size = Vector2(420, 300)
	_large_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_large_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_large_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_large_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	large_box.add_child(_large_preview)

	return scroll


func _build_variant_card(cam: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(210, 440)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)

	var title := Label.new()
	title.text = "Camera %d° sprite" % cam
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	inner.add_child(title)

	var hint := Label.new()
	hint.text = "Pick sprite used at this angle"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	inner.add_child(hint)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(160, 150)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.tooltip_text = "Click to pick the sprite for Camera %d°" % cam
	preview.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	preview.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_open_sprite_picker(cam)
	)
	inner.add_child(preview)
	_variant_preview[cam] = preview

	var warn := Label.new()
	warn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	warn.add_theme_font_size_override("font_size", 11)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(warn)
	_variant_warn[cam] = warn

	var facet_label := Label.new()
	facet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	facet_label.add_theme_font_size_override("font_size", 12)
	facet_label.text = "(no sprite)"
	inner.add_child(facet_label)
	_variant_facet_label[cam] = facet_label

	var pick := Button.new()
	pick.text = "Change %d° sprite…" % cam
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.pressed.connect(_open_sprite_picker.bind(cam))
	inner.add_child(pick)
	_variant_pick_btn[cam] = pick

	inner.add_child(_spin_row("Hot X", cam, _variant_hot_x, -200, 200))
	inner.add_child(_spin_row("Hot Y", cam, _variant_hot_y, -200, 200))
	inner.add_child(_spin_row("Off X", cam, _variant_off_x, -64, 64))
	inner.add_child(_spin_row("Off Y", cam, _variant_off_y, -64, 64))
	inner.add_child(_spin_row("Depth", cam, _variant_depth, -16, 16))

	var reset := Button.new()
	reset.text = "Reset default"
	reset.pressed.connect(_on_reset_variant.bind(cam))
	inner.add_child(reset)
	return card


func _build_sprite_picker_popup() -> void:
	_sprite_popup = PopupPanel.new()
	_sprite_popup.size = Vector2i(1100, 720)
	_sprite_popup.unresizable = false
	_sprite_popup.transparent = false
	_sprite_popup.transparent_bg = false
	add_child(_sprite_popup)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.13, 0.16, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite_popup.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_sprite_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := Label.new()
	header.name = "PickerHeader"
	header.text = "Pick sprite for this camera angle"
	header.add_theme_font_size_override("font_size", 15)
	root.add_child(header)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	root.add_child(filters)

	_sprite_search = LineEdit.new()
	_sprite_search.placeholder_text = "Search all CoC sprites (WWAL, WH00_e, bush…)"
	_sprite_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sprite_search.text_changed.connect(func(_t: String) -> void: _rebuild_sprite_grid())
	filters.add_child(_sprite_search)

	_sprite_family_only = CheckBox.new()
	_sprite_family_only.text = "Limit to this family"
	## Default OFF — show the full coc_tiles catalog.
	_sprite_family_only.button_pressed = false
	_sprite_family_only.toggled.connect(func(_on: bool) -> void: _rebuild_sprite_grid())
	filters.add_child(_sprite_family_only)

	var close_btn := Button.new()
	close_btn.text = "Cancel"
	close_btn.pressed.connect(func() -> void: _sprite_popup.hide())
	filters.add_child(close_btn)

	_sprite_status = Label.new()
	_sprite_status.add_theme_font_size_override("font_size", 11)
	root.add_child(_sprite_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_sprite_grid = GridContainer.new()
	_sprite_grid.columns = 8
	_sprite_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sprite_grid.add_theme_constant_override("h_separation", 8)
	_sprite_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_sprite_grid)

func _spin_row(label: String, cam: int, store: Dictionary, mn: float, mx: float) -> Control:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label
	lab.custom_minimum_size = Vector2(48, 0)
	row.add_child(lab)
	var spin := SpinBox.new()
	spin.min_value = mn
	spin.max_value = mx
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(_v: float) -> void: _on_variant_edited(cam))
	row.add_child(spin)
	store[cam] = spin
	return row


func _build_gameplay_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	scroll.resized.connect(func() -> void:
		col.custom_minimum_size.x = maxf(scroll.size.x - 8.0, 400.0)
	)

	var note := Label.new()
	note.text = "Shared across all four camera variants (presentation-only rotation)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)

	_terrain_option = OptionButton.new()
	_terrain_option.add_item("Even", 0)
	_terrain_option.add_item("Climb", 1)
	_terrain_option.add_item("NoPass", 2)
	_terrain_option.item_selected.connect(func(_i: int) -> void: _on_gameplay_edited())
	col.add_child(_labeled("Terrain class", _terrain_option))

	_height_spin = SpinBox.new()
	_height_spin.min_value = 0
	_height_spin.max_value = 2
	_height_spin.step = 1
	_height_spin.value_changed.connect(func(_v: float) -> void: _on_gameplay_edited())
	col.add_child(_labeled("Terrain height (0/1/2)", _height_spin))

	_blocks_move = CheckBox.new()
	_blocks_move.text = "Blocks movement"
	_blocks_move.toggled.connect(func(_on: bool) -> void: _on_gameplay_edited())
	col.add_child(_blocks_move)

	_blocks_los = CheckBox.new()
	_blocks_los.text = "Blocks LOS"
	_blocks_los.toggled.connect(func(_on: bool) -> void: _on_gameplay_edited())
	col.add_child(_blocks_los)

	_blocks_bullets = CheckBox.new()
	_blocks_bullets.text = "Blocks bullets"
	_blocks_bullets.toggled.connect(func(_on: bool) -> void: _on_gameplay_edited())
	col.add_child(_blocks_bullets)

	_provides_cover = CheckBox.new()
	_provides_cover.text = "Provides cover"
	_provides_cover.toggled.connect(func(_on: bool) -> void: _on_gameplay_edited())
	col.add_child(_provides_cover)

	_cover_type = OptionButton.new()
	_cover_type.add_item("None (0)", 0)
	_cover_type.add_item("Moderate (1)", 1)
	_cover_type.add_item("Complete (2)", 2)
	_cover_type.item_selected.connect(func(_i: int) -> void: _on_gameplay_edited())
	col.add_child(_labeled("Cover type", _cover_type))

	_category_edit = LineEdit.new()
	_category_edit.text_changed.connect(func(_t: String) -> void: _on_meta_edited())
	col.add_child(_labeled("Category", _category_edit))

	_material_edit = LineEdit.new()
	_material_edit.text_changed.connect(func(_t: String) -> void: _on_meta_edited())
	col.add_child(_labeled("Material", _material_edit))

	_height_band = LineEdit.new()
	_height_band.placeholder_text = "Descriptive metadata (gameplay uses terrain_height)"
	_height_band.text_changed.connect(func(_t: String) -> void: _on_meta_edited())
	col.add_child(_labeled("Height band", _height_band))

	_concealment = SpinBox.new()
	_concealment.min_value = 0
	_concealment.max_value = 1
	_concealment.step = 0.05
	_concealment.value_changed.connect(func(_v: float) -> void: _on_gameplay_edited())
	col.add_child(_labeled("Concealment", _concealment))

	_suppression = SpinBox.new()
	_suppression.min_value = -1
	_suppression.max_value = 1
	_suppression.step = 0.05
	_suppression.value_changed.connect(func(_v: float) -> void: _on_gameplay_edited())
	col.add_child(_labeled("Suppression modifier", _suppression))

	_notes = TextEdit.new()
	_notes.custom_minimum_size = Vector2(0, 80)
	_notes.text_changed.connect(_on_meta_edited)
	col.add_child(_labeled("Notes / tags", _notes))

	return scroll


func _labeled(title: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	var lab := Label.new()
	lab.text = title
	box.add_child(lab)
	box.add_child(control)
	return box


func _refresh_family_list() -> void:
	_rebuild_category_options()
	_family_list.clear()
	var ids := MapAssetRegistryClass.family_ids()
	for fam in ids:
		var entry := MapAssetRegistryClass.get_entry(fam)
		var cat := str(entry.get("category", ""))
		if _category_filter != "All" and cat != _category_filter:
			continue
		var display := str(entry.get("display_name", fam))
		var hay := ("%s %s %s" % [fam, display, cat]).to_lower()
		if not _search.is_empty() and hay.find(_search.to_lower()) < 0:
			continue
		var usage := MapAssetRegistryClass.usage_count(fam)
		var warn := " ⚠" if MapAssetRegistryClass.has_unresolved_variants(fam) else ""
		var idx := _family_list.add_item("FF · %s — %s (%d)%s" % [fam, display, usage, warn])
		_family_list.set_item_metadata(idx, fam)
	if _family_list.item_count > 0:
		_family_list.select(0)
		_on_family_selected(0)


func _rebuild_category_options() -> void:
	var cats: Dictionary = {"All": true}
	for fam in MapAssetRegistryClass.family_ids():
		cats[str(MapAssetRegistryClass.get_entry(fam).get("category", "prop"))] = true
	var keys: Array = cats.keys()
	keys.sort()
	var previous := _category_filter
	_category_option.clear()
	var select_i := 0
	for i in range(keys.size()):
		_category_option.add_item(str(keys[i]))
		if str(keys[i]) == previous:
			select_i = i
	_category_option.select(select_i)
	_category_filter = str(keys[select_i])


func _on_search_changed(text: String) -> void:
	_search = text
	_refresh_family_list()


func _on_category_selected(index: int) -> void:
	_category_filter = _category_option.get_item_text(index)
	_refresh_family_list()


func _on_family_selected(index: int) -> void:
	_family = str(_family_list.get_item_metadata(index))
	_load_family_into_ui()


func _load_family_into_ui() -> void:
	if _family.is_empty():
		return
	_loading_ui = true
	var entry := MapAssetRegistryClass.get_entry(_family)
	var gp: Dictionary = entry.get("gameplay", {}) if entry.get("gameplay", {}) is Dictionary else {}
	_display_name.text = str(entry.get("display_name", _family))
	_category_edit.text = str(entry.get("category", ""))
	_material_edit.text = str(entry.get("material", ""))
	_height_band.text = str(entry.get("height_band", ""))
	_notes.text = str(entry.get("notes", ""))

	var terrain := str(gp.get("terrain", "_HG_EVEN"))
	match terrain:
		"_HG_Climb":
			_terrain_option.select(1)
		"_HG_NoPass":
			_terrain_option.select(2)
		_:
			_terrain_option.select(0)
	_height_spin.value = int(gp.get("terrain_height", 0))
	_blocks_move.button_pressed = bool(gp.get("blocks_movement", false))
	_blocks_los.button_pressed = bool(gp.get("blocks_los", false))
	_blocks_bullets.button_pressed = bool(gp.get("blocks_bullets", false))
	_provides_cover.button_pressed = bool(gp.get("provides_cover", false))
	_cover_type.select(clampi(int(gp.get("cover_type", 0)), 0, 2))
	_concealment.value = float(gp.get("concealment", 0.0))
	_suppression.value = float(gp.get("suppression_modifier", 0.0))

	for cam in CAMERA_DEGS:
		var variant := MapAssetRegistryClass.camera_variant(_family, cam)
		_set_variant_selection_from_dict(cam, variant)
		var hs: Variant = variant.get("hotspot", [-50, -73])
		if hs is Array and (hs as Array).size() >= 2:
			(_variant_hot_x[cam] as SpinBox).value = float(hs[0])
			(_variant_hot_y[cam] as SpinBox).value = float(hs[1])
		var ro: Variant = variant.get("render_offset", [0, 0])
		if ro is Array and (ro as Array).size() >= 2:
			(_variant_off_x[cam] as SpinBox).value = float(ro[0])
			(_variant_off_y[cam] as SpinBox).value = float(ro[1])
		(_variant_depth[cam] as SpinBox).value = float(variant.get("depth_offset", 0))
		(_variant_warn[cam] as Label).text = "fallback / unresolved" if bool(variant.get("fallback", false)) else ""
		_refresh_variant_preview(cam)
	_refresh_large_preview()
	_loading_ui = false


func _set_variant_selection_from_dict(cam: int, variant: Dictionary) -> void:
	var facet := str(variant.get("facet", ""))
	var letter := str(variant.get("letter", "e")).to_lower()
	var src_fam := str(variant.get("source_family", "")).to_upper()
	if src_fam.is_empty() and facet.contains("_"):
		src_fam = facet.get_slice("_", 0).to_upper()
	if src_fam.is_empty():
		src_fam = _family
	if letter.is_empty() and facet.contains("_"):
		letter = facet.get_slice("_", 1).to_lower()
	if facet.is_empty():
		facet = "%s_%s" % [src_fam, letter]
	var path := str(variant.get("path", "sprites/coc_tiles/%s_%s.png" % [src_fam, letter]))
	_variant_selection[cam] = {
		"family": src_fam,
		"letter": letter,
		"facet": facet,
		"path": path,
	}
	(_variant_facet_label[cam] as Label).text = facet


func _open_sprite_picker(cam: int) -> void:
	if _family.is_empty():
		return
	_picker_cam = cam
	_sprite_search.text = ""
	## Always open on the full catalog; optional filter is opt-in.
	_sprite_family_only.button_pressed = false
	var header := _sprite_popup.find_child("PickerHeader", true, false) as Label
	if header != null:
		header.text = "Pick sprite for Camera %d° — all CoC tiles (assigning to %s)" % [cam, _family]
	_rebuild_sprite_grid()
	_sprite_popup.popup_centered(Vector2i(1100, 720))
	_sprite_search.grab_focus()


func _rebuild_sprite_grid() -> void:
	for child in _sprite_grid.get_children():
		child.queue_free()
	var fam_filter := _family if _sprite_family_only.button_pressed else ""
	var query := _sprite_search.text.strip_edges().to_lower()
	var sprites: Array = CocTileCatalogClass.list_sprites(fam_filter)
	var shown := 0
	for rec_v in sprites:
		if not rec_v is Dictionary:
			continue
		var rec: Dictionary = rec_v
		var facet := str(rec.get("facet", "")).to_lower()
		var fam := str(rec.get("family", "")).to_lower()
		if not query.is_empty() and facet.find(query) < 0 and fam.find(query) < 0:
			continue
		_sprite_grid.add_child(_make_sprite_thumb(rec))
		shown += 1
	var scope := "family %s" % _family if _sprite_family_only.button_pressed else "all CoC tiles"
	_sprite_status.text = "%d sprites (%s) — click a thumbnail to assign to Camera %d°" % [
		shown, scope, _picker_cam
	]


func _make_sprite_thumb(rec: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(108, 128)
	btn.text = str(rec.get("facet", ""))
	btn.tooltip_text = str(rec.get("path", rec.get("facet", "")))
	btn.expand_icon = true
	btn.clip_text = true
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var path := str(rec.get("path", ""))
	if not path.is_empty() and (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
		btn.icon = load(path) as Texture2D
	btn.pressed.connect(_on_sprite_picked.bind(rec.duplicate(true)))
	return btn


func _on_sprite_picked(rec: Dictionary) -> void:
	if _picker_cam < 0 or _family.is_empty():
		return
	var cam := _picker_cam
	var src_fam := str(rec.get("family", _family)).to_upper()
	var letter := str(rec.get("letter", "e")).to_lower()
	var facet := str(rec.get("facet", "%s_%s" % [src_fam, letter]))
	var path := str(rec.get("rel_path", rec.get("path", "")))
	if path.begins_with("res://assets/"):
		path = path.trim_prefix("res://assets/")
	elif path.begins_with("res://"):
		path = path.trim_prefix("res://")
	var hs: Variant = rec.get("hotspot", [-50, -73])
	_loading_ui = true
	if hs is Array and (hs as Array).size() >= 2:
		(_variant_hot_x[cam] as SpinBox).value = float(hs[0])
		(_variant_hot_y[cam] as SpinBox).value = float(hs[1])
	_loading_ui = false
	_variant_selection[cam] = {
		"family": src_fam,
		"letter": letter,
		"facet": facet,
		"path": path,
	}
	(_variant_facet_label[cam] as Label).text = facet
	(_variant_warn[cam] as Label).text = ""
	_commit_variant(cam)
	_sprite_popup.hide()
	status_message.emit("Assigned %s to Camera %d°" % [facet, cam])


func _on_variant_edited(cam: int) -> void:
	if _loading_ui or _family.is_empty():
		return
	_commit_variant(cam)


func _commit_variant(cam: int) -> void:
	var sel: Dictionary = _variant_selection.get(cam, {})
	if sel.is_empty():
		return
	var src_fam := str(sel.get("family", _family)).to_upper()
	var letter := str(sel.get("letter", "e")).to_lower()
	var facet := str(sel.get("facet", "%s_%s" % [src_fam, letter]))
	var path := str(sel.get("path", "sprites/coc_tiles/%s_%s.png" % [src_fam, letter]))
	MapAssetRegistryClass.set_camera_variant(
		_family,
		cam,
		{
			"letter": letter,
			"facet": facet,
			"path": path,
			"source_family": src_fam,
			"hotspot": [
				int((_variant_hot_x[cam] as SpinBox).value),
				int((_variant_hot_y[cam] as SpinBox).value),
			],
			"render_offset": [
				int((_variant_off_x[cam] as SpinBox).value),
				int((_variant_off_y[cam] as SpinBox).value),
			],
			"depth_offset": int((_variant_depth[cam] as SpinBox).value),
			"fallback": false,
		}
	)
	_refresh_variant_preview(cam)
	if cam == _large_cam:
		_refresh_large_preview()
	_set_dirty(true)
	_refresh_family_list_labels()


func _on_reset_variant(cam: int) -> void:
	if _family.is_empty():
		return
	## Re-detect via CocFacetSelector at world dir 0.
	var letter := CocFacetSelector.select_letter_at_camera(_family, 0, cam)
	var path := "res://assets/sprites/coc_tiles/%s_%s.png" % [_family, letter]
	var fallback := not FileAccess.file_exists(path)
	if fallback:
		letter = "e"
		path = "res://assets/sprites/coc_tiles/%s_%s.png" % [_family, letter]
		fallback = not FileAccess.file_exists(path)
	MapAssetRegistryClass.set_camera_variant(
		_family,
		cam,
		{
			"letter": letter,
			"facet": "%s_%s" % [_family, letter],
			"path": "sprites/coc_tiles/%s_%s.png" % [_family, letter],
			"hotspot": [-50, -73],
			"render_offset": [0, 0],
			"depth_offset": 0,
			"fallback": fallback,
		}
	)
	_load_family_into_ui()
	_set_dirty(true)


func _on_gameplay_edited() -> void:
	if _loading_ui or _family.is_empty():
		return
	var terrain_token := "_HG_EVEN"
	match _terrain_option.selected:
		1:
			terrain_token = "_HG_Climb"
		2:
			terrain_token = "_HG_NoPass"
	MapAssetRegistryClass.set_gameplay(
		_family,
		{
			"terrain": terrain_token,
			"terrain_height": int(_height_spin.value),
			"blocks_movement": _blocks_move.button_pressed,
			"blocks_los": _blocks_los.button_pressed,
			"blocks_bullets": _blocks_bullets.button_pressed,
			"provides_cover": _provides_cover.button_pressed,
			"cover_type": _cover_type.selected,
			"concealment": float(_concealment.value),
			"suppression_modifier": float(_suppression.value),
		}
	)
	_set_dirty(true)


func _on_meta_edited(_arg: Variant = null) -> void:
	if _loading_ui or _family.is_empty():
		return
	MapAssetRegistryClass.set_display_meta(
		_family,
		_display_name.text.strip_edges(),
		_category_edit.text.strip_edges(),
		_material_edit.text.strip_edges(),
		_height_band.text.strip_edges(),
		_notes.text.strip_edges(),
	)
	_set_dirty(true)
	_refresh_family_list_labels()


func _refresh_family_list_labels() -> void:
	## Soft refresh of selected row text without losing selection.
	for i in range(_family_list.item_count):
		var fam := str(_family_list.get_item_metadata(i))
		var entry := MapAssetRegistryClass.get_entry(fam)
		var display := str(entry.get("display_name", fam))
		var usage := MapAssetRegistryClass.usage_count(fam)
		var warn := " ⚠" if MapAssetRegistryClass.has_unresolved_variants(fam) else ""
		_family_list.set_item_text(i, "FF · %s — %s (%d)%s" % [fam, display, usage, warn])


func _refresh_variant_preview(cam: int) -> void:
	var sel: Dictionary = _variant_selection.get(cam, {})
	var rel := str(sel.get("path", ""))
	if rel.is_empty():
		var variant := MapAssetRegistryClass.camera_variant(_family, cam)
		rel = str(variant.get("path", ""))
	var path := rel
	if not path.begins_with("res://"):
		path = "res://assets/%s" % rel if not rel.begins_with("assets/") else "res://%s" % rel
	var preview: TextureRect = _variant_preview[cam]
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		preview.texture = load(path) as Texture2D
	else:
		preview.texture = null


func _on_large_cam_selected(index: int) -> void:
	_large_cam = int(_large_cam_option.get_item_id(index))
	_refresh_large_preview()


func _refresh_large_preview() -> void:
	if _family.is_empty():
		return
	_refresh_variant_preview(_large_cam)
	_large_preview.texture = (_variant_preview[_large_cam] as TextureRect).texture
	## Neighbor hint is informational only (no separate renderer).
	if _show_neighbors:
		status_message.emit("Neighbor preview: use map editor for wall connections")


func _refresh_audit() -> void:
	var audit := MapAssetRegistryClass.audit_farm_fight()
	_audit_label.text = (
		"Farm Fight unique: %d\nRegistered: %d\nMissing: %d\nIncomplete cams: %d\nFallback GP: %d"
		% [
			int(audit.get("farm_unique_families", 0)),
			int(audit.get("registered_families", 0)),
			(audit.get("missing_families", []) as Array).size(),
			(audit.get("incomplete_camera_variants", []) as Array).size(),
			(audit.get("fallback_gameplay", []) as Array).size(),
		]
	)
	status_message.emit("Registry audit refreshed")


func _set_dirty(value: bool) -> void:
	_dirty = value
	dirty_changed.emit(_dirty)
