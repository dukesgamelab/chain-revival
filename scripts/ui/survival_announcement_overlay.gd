class_name SurvivalAnnouncementOverlay
extends Control
## Brief centered fade announcement for Survival Mode reinforcements.

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
	if _label != null:
		_label.text = MESSAGE
		_label.add_theme_color_override("font_color", CocUiTheme.TEXT_STATUS_RED)


func show_deployment_announcement() -> void:
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
