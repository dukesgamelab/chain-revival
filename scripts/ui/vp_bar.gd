class_name VpBar
extends PanelContainer
## Small HUD panel showing VP zone names with colored holder indicators
## and capture progress bars.

var _vbox: VBoxContainer
var _rows: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CocUiTheme.panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 2)
	add_child(margin)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	margin.add_child(_vbox)
	visible = false


func set_vp_data(vp_entries: Array) -> void:
	if vp_entries.is_empty():
		visible = false
		return

	var valid_entries: Array[Dictionary] = []
	for entry in vp_entries:
		if entry is Dictionary:
			valid_entries.append(entry)

	while _rows.size() < valid_entries.size():
		_add_row()
	while _rows.size() > valid_entries.size():
		var row_data: Dictionary = _rows.pop_back()
		row_data["col"].queue_free()

	for i in valid_entries.size():
		_update_row(i, valid_entries[i])

	visible = true


func _add_row() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	row.add_child(dot)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	row.add_child(label)

	col.add_child(row)

	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(100, 4)
	bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	bar_bg.visible = false
	col.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.custom_minimum_size = Vector2(0, 4)
	bar_fill.position = Vector2.ZERO
	bar_bg.add_child(bar_fill)

	_vbox.add_child(col)
	_rows.append({
		"col": col,
		"dot": dot,
		"label": label,
		"bar_bg": bar_bg,
		"bar_fill": bar_fill,
	})


func _update_row(idx: int, entry: Dictionary) -> void:
	var row_data: Dictionary = _rows[idx]
	var vp_name: String = str(entry.get("name", "")).strip_edges()
	if vp_name.is_empty():
		vp_name = "VP"
	var holder := str(entry.get("holder", entry.get("initial_holder", "Germany"))).strip_edges()
	var is_usa := VictoryPointLayer._holder_is_usa(holder)
	var progress := float(entry.get("capture_progress", 0.0))
	var capturing_side := str(entry.get("capturing_side", ""))

	row_data["dot"].color = Color(0.15, 0.28, 0.85) if is_usa else Color(0.6, 0.1, 0.1)
	row_data["label"].text = vp_name

	if progress > 0.0 and not capturing_side.is_empty():
		var cap_is_usa := VictoryPointLayer._holder_is_usa(capturing_side)
		row_data["bar_fill"].color = Color(0.3, 0.5, 1.0) if cap_is_usa else Color(0.8, 0.2, 0.2)
		row_data["bar_fill"].custom_minimum_size.x = progress * 100.0
		row_data["bar_bg"].visible = true
	else:
		row_data["bar_bg"].visible = false
