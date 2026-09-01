class_name SurvivalAnnouncementOverlay
extends Control
## Brief fade announcement for Survival Mode reinforcements, under the map tools.

const MESSAGE := "New enemy fireteam has been deployed"
const FADE_IN_SEC := 0.35
const HOLD_SEC := 1.25
const FADE_OUT_SEC := 0.45

@onready var _label: Label = %AnnouncementLabel
@onready var _panel: PanelContainer = %AnnouncementPanel

var _active_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false
	CocUiTheme.apply_to(self)
	if _panel != null:
		_panel.add_theme_stylebox_override("panel", CocUiTheme.panel_style())
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _label != null:
		_label.text = MESSAGE
		_label.add_theme_color_override("font_color", CocUiTheme.TEXT_STATUS_RED)
		_label.add_theme_font_size_override("font_size", CocUiTheme.FONT_SIZE)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	call_deferred("place_under_map_tools")


func place_under_map_tools() -> void:
	var ui := get_parent()
	if ui == null:
		return
	var cmd := ui.get_node_or_null("CommandBar") as Control
	if cmd == null or not cmd.has_method("get_top_left_tools_rect"):
		return
	var tools: Rect2 = cmd.get_top_left_tools_rect()
	const GAP := 4.0
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var height := 24.0
	if _panel != null:
		height = maxf(_panel.get_combined_minimum_size().y, 22.0)
	offset_left = tools.position.x
	offset_top = tools.end.y + GAP
	offset_right = tools.end.x
	offset_bottom = offset_top + height


func show_deployment_announcement() -> void:
	place_under_map_tools()
	if _label != null:
		_label.text = MESSAGE
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	visible = true
	modulate.a = 0.0
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_SEC)
	_active_tween.tween_interval(HOLD_SEC)
	_active_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC)
	_active_tween.tween_callback(_hide_after_fade)


func _hide_after_fade() -> void:
	visible = false
	modulate.a = 0.0
