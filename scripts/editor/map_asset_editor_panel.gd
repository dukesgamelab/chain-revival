class_name MapAssetEditorPanel
extends Control
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
var _variant_facet: Dictionary = {} ## cam -> OptionButton
var _variant_hot_x: Dictionary = {}
var _variant_hot_y: Dictionary = {}
var _variant_off_x: Dictionary = {}
var _variant_off_y: Dictionary = {}
var _variant_depth: Dictionary = {}
var _variant_preview: Dictionary = {} ## cam -> TextureRect
var _variant_warn: Dictionary = {} ## cam -> Label
var _large_preview: TextureRect
var _large_cam_option: OptionButton
var _audit_label: Label


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
		status_message.emit("Saved map_asset_registry.json")
	else:
		status_message.emit("Save failed for map_asset_registry.json")
	return err


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left)

	var left_header := Label.new()
	left_header.text = "Map Asset Families"
	left.add_child(left_header)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search family…"
	_search_edit.text_changed.connect(_on_search_changed)
	left.add_child(_search_edit)

	_category_option = OptionButton.new()
	_category_option.item_selected.connect(_on_category_selected)
	left.add_child(_category_option)

	_family_list = ItemList.new()
	_family_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	root.add_child(_tab)

	_tab.add_child(_build_visual_tab())
	_tab.set_tab_title(0, "Visual Variants")
	_tab.add_child(_build_gameplay_tab())
	_tab.set_tab_title(1, "Gameplay")


func _build_visual_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var meta_row := HBoxContainer.new()
	col.add_child(meta_row)
	_display_name = LineEdit.new()
	_display_name.placeholder_text = "Display name"
	_display_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display_name.text_changed.connect(func(_t: String) -> void: _on_meta_edited())
	meta_row.add_child(_display_name)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)

	for cam in CAMERA_DEGS:
		grid.add_child(_build_variant_card(cam))

	var large_box := VBoxContainer.new()
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
	_large_preview.custom_minimum_size = Vector2(320, 240)
	_large_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_large_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_large_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	large_box.add_child(_large_preview)

	return scroll


func _build_variant_card(cam: int) -> Control:
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(200, 0)
	var title := Label.new()
	title.text = "Camera %d°" % cam
	card.add_child(title)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(120, 100)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.add_child(preview)
	_variant_preview[cam] = preview

	var warn := Label.new()
	warn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	warn.add_theme_font_size_override("font_size", 11)
	card.add_child(warn)
	_variant_warn[cam] = warn

	var facet := OptionButton.new()
	facet.item_selected.connect(func(_i: int) -> void: _on_variant_edited(cam))
	card.add_child(facet)
	_variant_facet[cam] = facet

	card.add_child(_spin_row("Hot X", cam, _variant_hot_x, -200, 200))
	card.add_child(_spin_row("Hot Y", cam, _variant_hot_y, -200, 200))
	card.add_child(_spin_row("Off X", cam, _variant_off_x, -64, 64))
	card.add_child(_spin_row("Off Y", cam, _variant_off_y, -64, 64))
	card.add_child(_spin_row("Depth", cam, _variant_depth, -16, 16))

	var reset := Button.new()
	reset.text = "Reset default"
	reset.pressed.connect(_on_reset_variant.bind(cam))
	card.add_child(reset)
	return card


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
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

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
		var idx := _family_list.add_item("%s — %s (%d)%s" % [fam, display, usage, warn])
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

	_populate_facet_options()
	for cam in CAMERA_DEGS:
		var variant := MapAssetRegistryClass.camera_variant(_family, cam)
		_select_facet_option(cam, str(variant.get("letter", "e")), str(variant.get("facet", "")))
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


func _populate_facet_options() -> void:
	## Prefer authored/existing letters; fall back to known variant letters.
	var entry := MapAssetRegistryClass.get_entry(_family)
	var variants: Variant = entry.get("camera_variants", {})
	var seen: Dictionary = {}
	if variants is Dictionary:
		for key in variants.keys():
			var v: Variant = variants[key]
			if v is Dictionary:
				var let := str(v.get("letter", "")).to_lower()
				if not let.is_empty():
					seen[let] = true
	for let in ["e", "s", "w", "n", "ne", "se", "sw", "nw"]:
		var path := "res://assets/sprites/coc_tiles/%s_%s.png" % [_family, let]
		if FileAccess.file_exists(path) or seen.has(let):
			seen[let] = true
	var keys: Array = seen.keys()
	keys.sort()
	for cam in CAMERA_DEGS:
		var opt: OptionButton = _variant_facet[cam]
		opt.clear()
		for let in keys:
			opt.add_item("%s_%s" % [_family, let])
			opt.set_item_metadata(opt.item_count - 1, str(let))
		if opt.item_count == 0:
			opt.add_item("%s_e" % _family)
			opt.set_item_metadata(0, "e")


func _select_facet_option(cam: int, letter: String, facet: String) -> void:
	var opt: OptionButton = _variant_facet[cam]
	var target := letter.to_lower()
	if target.is_empty() and facet.contains("_"):
		target = facet.get_slice("_", 1).to_lower()
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == target:
			opt.select(i)
			return
	if opt.item_count > 0:
		opt.select(0)


func _on_variant_edited(cam: int) -> void:
	if _loading_ui or _family.is_empty():
		return
	var opt: OptionButton = _variant_facet[cam]
	var letter := str(opt.get_item_metadata(opt.selected))
	var path := "sprites/coc_tiles/%s_%s.png" % [_family, letter]
	MapAssetRegistryClass.set_camera_variant(
		_family,
		cam,
		{
			"letter": letter,
			"facet": "%s_%s" % [_family, letter],
			"path": path,
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
	(_variant_warn[cam] as Label).text = ""
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
		_family_list.set_item_text(i, "%s — %s (%d)%s" % [fam, display, usage, warn])


func _refresh_variant_preview(cam: int) -> void:
	var variant := MapAssetRegistryClass.camera_variant(_family, cam)
	var rel := str(variant.get("path", ""))
	var path := "res://assets/%s" % rel if not rel.begins_with("res://") else rel
	var preview: TextureRect = _variant_preview[cam]
	if FileAccess.file_exists(path):
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
