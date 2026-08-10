class_name SoldierCommandRow
extends HBoxContainer
## One soldier row: weapon, ammo, commands, status, stress, and hit chance.

signal move_mode_toggled(soldier_id: int, movement_mode: int, is_pressed: bool)
signal fire_at_toggled(soldier_id: int, is_pressed: bool)
signal face_toggled(soldier_id: int, is_pressed: bool)
signal position_toggled(soldier_id: int, is_down: bool)
signal fire_control_selected(soldier_id: int, fire_control_state: int)
signal grenade_toggled(soldier_id: int, is_pressed: bool)
signal ammo_adjust_requested(soldier_id: int, delta: int)

@export var soldier_id: int = 1

@onready var _dots_label: Label = %DotsLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _ammo_up_button: Button = %AmmoUpButton
@onready var _ammo_down_button: Button = %AmmoDownButton
@onready var _fire_at_button: Button = %FireAtButton
@onready var _run_to_button: Button = %RunToButton
@onready var _crawl_to_button: Button = %CrawlToButton
@onready var _face_button: Button = %FaceButton
@onready var _position_button: Button = %PositionButton
@onready var _grenade_button: Button = %GrenadeButton
@onready var _assault_button: Button = %AssaultButton
@onready var _fire_at_will_button: Button = %FireAtWillButton
@onready var _hold_fire_button: Button = %HoldFireButton
@onready var _status_label: Label = %StatusLabel
@onready var _stress_label: Label = %StressLabel
@onready var _hit_label: Label = %HitLabel

var _row_enabled: bool = true
var _move_buttons: Dictionary = {}
var _team_id: int = Team.USA
## Stance for Down/Up label; button itself stays momentary (not latched).
var _position_is_down: bool = false
const _ACTION_FLASH_SEC := 0.1


func _ready() -> void:
	_dots_label.text = _make_dots(soldier_id)
	_move_buttons = {
		MovementMode.RUN: _run_to_button,
		MovementMode.CRAWL: _crawl_to_button,
	}
	CocUiTheme.style_grenade_button(_grenade_button)
	_fire_at_button.tooltip_text = "Enter targeting mode — click an enemy to shoot."
	_run_to_button.tooltip_text = "Run to a tile — click the map."
	_crawl_to_button.tooltip_text = "Crawl to a tile — click the map."
	_face_button.tooltip_text = "Face a direction — click a tile or enemy (no firing)."
	_position_button.tooltip_text = "Go prone (Down) or stand up (Up)."
	_grenade_button.tooltip_text = "Throw a grenade — click a tile within 7 tiles."
	_assault_button.tooltip_text = "Assault — coming soon."
	_hold_fire_button.tooltip_text = "Hold Fire — cease auto-fire; move/face freely; manual Fire At only."
	_fire_at_will_button.tooltip_text = "Fire At Will — fire on sight at visible enemies until Hold Fire or they leave."
	_fire_at_button.toggled.connect(_on_fire_at_toggled)
	_hold_fire_button.pressed.connect(_on_hold_fire_pressed)
	_fire_at_will_button.pressed.connect(_on_fire_at_will_pressed)
	_run_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.RUN))
	_crawl_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.CRAWL))
	_face_button.toggled.connect(_on_face_toggled)
	_grenade_button.toggled.connect(_on_grenade_toggled)
	_position_button.toggled.connect(_on_position_toggled)
	## Ammo ▲/▼ removed — match OG toolbar; ammo changes via Assign Weapons.
	if _ammo_up_button != null:
		_ammo_up_button.visible = false
	if _ammo_down_button != null:
		_ammo_down_button.visible = false
	var ammo_col := get_node_or_null("WeaponAmmoPanel/WeaponAmmoRow/AmmoAdjustCol")
	if ammo_col != null:
		ammo_col.visible = false
	set_position_state(PositionState.UP)
	set_fire_control_state(FireControlState.FIRE_AT_WILL)
	set_grenade_count(5)
	_status_label.add_theme_color_override("font_color", CocUiTheme.TEXT_STATUS_RED)


func set_move_mode_pressed(movement_mode: int, is_pressed: bool) -> void:
	var button: Button = _move_buttons.get(movement_mode) as Button
	if button != null:
		button.set_pressed_no_signal(is_pressed)


func clear_move_modes() -> void:
	for button in _move_buttons.values():
		(button as Button).set_pressed_no_signal(false)


## Brief pressed flash then release — mode stays active in CommandBar.
func flash_move_mode(movement_mode: int) -> void:
	_flash_release_button(_move_buttons.get(movement_mode) as Button)


func flash_fire_at() -> void:
	_flash_release_button(_fire_at_button, func() -> void: _update_fire_at_highlight(false))


func flash_face() -> void:
	_flash_release_button(_face_button, func() -> void: _face_button.modulate = Color.WHITE)


func flash_grenade() -> void:
	_flash_release_button(_grenade_button, func() -> void: _update_grenade_highlight(false))


func flash_position() -> void:
	_flash_release_button(_position_button)


func set_fire_at_pressed(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_fire_at_button.set_pressed_no_signal(is_pressed)
	_update_fire_at_highlight(is_pressed)


func set_face_pressed(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_face_button.set_pressed_no_signal(is_pressed)
	_face_button.modulate = CocUiTheme.selected_modulate(is_pressed)


func set_weapon_info(state: SoldierState) -> void:
	_team_id = state.team_id
	var type_code := WeaponType.short_code(state.weapon_type)
	if state.weapon_name.is_empty():
		_weapon_label.text = type_code
	else:
		_weapon_label.text = "%s %s" % [type_code, state.weapon_name]
	var status_line := "%s Soldier %d — Weapon: %s" % [
		Team.display_name(state.team_id),
		state.soldier_id,
		state.weapon_name if not state.weapon_name.is_empty() else "—",
	]
	_weapon_label.tooltip_text = status_line
	_ammo_label.tooltip_text = "%s\nAmmo %d (start load %d)" % [
		status_line,
		state.ammo_current,
		state.ammo_max,
	]


func set_ammo(ammo_current: int, _ammo_max: int) -> void:
	_ammo_label.text = "%d" % ammo_current


func set_grenade_count(count: int, action_blocked: bool = false) -> void:
	## White count on the recovered grenade chrome (right of the icon).
	_grenade_button.text = str(maxi(0, count))
	_grenade_button.disabled = not _row_enabled or count <= 0 or action_blocked


func set_grenade_pressed(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_grenade_button.set_pressed_no_signal(is_pressed)
	_update_grenade_highlight(is_pressed)


func set_activity_status(text: String) -> void:
	if _status_label.text != text:
		_status_label.text = text
	## Stunned must read clearly — greyed buttons alone are easy to miss.
	if text == "Stunned":
		_status_label.modulate = Color(1.0, 0.85, 0.35, 1.0)
	else:
		_status_label.modulate = Color.WHITE


func set_stress(stress: float) -> void:
	_stress_label.text = "%d%%" % int(round(clampf(stress, 0.0, 100.0)))


func set_hit_pct(hit_pct: float) -> void:
	var text := "—" if hit_pct < 0.0 else "%d%%" % int(round(clampf(hit_pct, 0.0, 100.0)))
	if _hit_label.text == text:
		return
	_hit_label.text = text


func set_row_enabled(enabled: bool) -> void:
	if not enabled:
		_fire_at_button.set_block_signals(true)
		_fire_at_button.set_pressed_no_signal(false)
		_update_fire_at_highlight(false)
		_fire_at_button.set_block_signals(false)
	_row_enabled = enabled
	_fire_at_button.disabled = not enabled
	_run_to_button.disabled = not enabled
	_crawl_to_button.disabled = not enabled
	_hold_fire_button.disabled = not enabled
	_fire_at_will_button.disabled = not enabled
	_face_button.disabled = not enabled
	_position_button.disabled = not enabled
	_grenade_button.disabled = not enabled
	if _ammo_up_button != null:
		_ammo_up_button.disabled = not enabled
	if _ammo_down_button != null:
		_ammo_down_button.disabled = not enabled
	modulate = Color.WHITE if enabled else Color(0.75, 0.75, 0.75, 1.0)


func apply_coc_inset_wells(inset: StyleBox) -> void:
	for panel_name in ["DotPanel", "WeaponAmmoPanel", "StatusPanel", "StressPanel", "HitPanel"]:
		var panel := get_node_or_null(panel_name) as PanelContainer
		if panel != null:
			panel.add_theme_stylebox_override("panel", inset)


func set_move_button_enabled(movement_mode: int, enabled: bool) -> void:
	var button: Button = _move_buttons.get(movement_mode) as Button
	if button == null:
		return
	button.disabled = not _row_enabled or not enabled
	if not enabled and button.button_pressed:
		button.set_pressed_no_signal(false)


func set_position_state(position_state: int) -> void:
	_position_is_down = position_state == PositionState.DOWN
	## Momentary control — never latch pressed; label is the next action.
	_position_button.set_pressed_no_signal(false)
	_position_button.text = "Up" if _position_is_down else "Down"
	_position_button.modulate = Color.WHITE


func set_fire_control_state(fire_control_state: int) -> void:
	## Sunken/raised chrome via toggle pressed state (OG Hold Fire / Fire At Will).
	var is_hold := fire_control_state == FireControlState.HOLD_FIRE
	_hold_fire_button.set_pressed_no_signal(is_hold)
	_fire_at_will_button.set_pressed_no_signal(not is_hold)


func is_interactive() -> bool:
	return _row_enabled


func is_move_mode_pressed(movement_mode: int) -> bool:
	var button: Button = _move_buttons.get(movement_mode) as Button
	return button != null and button.button_pressed


func is_fire_at_pressed() -> bool:
	return _fire_at_button.button_pressed


func is_face_pressed() -> bool:
	return _face_button.button_pressed


func is_grenade_pressed() -> bool:
	return _grenade_button.button_pressed


func _on_move_toggled(is_pressed: bool, movement_mode: int) -> void:
	if not _row_enabled:
		return
	move_mode_toggled.emit(soldier_id, movement_mode, is_pressed)


func _on_fire_at_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_update_fire_at_highlight(is_pressed)
	fire_at_toggled.emit(soldier_id, is_pressed)


func _on_face_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_face_button.modulate = CocUiTheme.selected_modulate(is_pressed)
	face_toggled.emit(soldier_id, is_pressed)


func _on_grenade_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	_update_grenade_highlight(is_pressed)
	grenade_toggled.emit(soldier_id, is_pressed)


func _on_position_toggled(is_pressed: bool) -> void:
	if not _row_enabled:
		return
	## Ignore our own unpress; click means "do the labeled next stance".
	if not is_pressed:
		return
	var want_down := not _position_is_down
	_position_is_down = want_down
	_position_button.text = "Up" if want_down else "Down"
	_position_button.modulate = Color.WHITE
	flash_position()
	position_toggled.emit(soldier_id, want_down)


func _flash_release_button(button: Button, on_release: Callable = Callable()) -> void:
	if button == null:
		return
	## Click already pressed the toggle; release shortly so it reads as a click.
	var tree := get_tree()
	if tree == null:
		button.set_pressed_no_signal(false)
		if on_release.is_valid():
			on_release.call()
		return
	tree.create_timer(_ACTION_FLASH_SEC).timeout.connect(
		func() -> void:
			if not is_instance_valid(button):
				return
			button.set_pressed_no_signal(false)
			if on_release.is_valid():
				on_release.call()
	)


func _on_hold_fire_pressed() -> void:
	if not _row_enabled:
		return
	## Keep one depressed (re-clicking the active button must not raise both).
	set_fire_control_state(FireControlState.HOLD_FIRE)
	fire_control_selected.emit(soldier_id, FireControlState.HOLD_FIRE)


func _on_fire_at_will_pressed() -> void:
	if not _row_enabled:
		return
	set_fire_control_state(FireControlState.FIRE_AT_WILL)
	fire_control_selected.emit(soldier_id, FireControlState.FIRE_AT_WILL)


func _update_fire_at_highlight(is_active: bool) -> void:
	_fire_at_button.modulate = CocUiTheme.selected_modulate(is_active)


func _update_grenade_highlight(is_active: bool) -> void:
	_grenade_button.modulate = CocUiTheme.selected_modulate(is_active)


func _make_dots(count: int) -> String:
	var dots := ""
	for i in range(count):
		if i > 0:
			dots += " "
		dots += "•"
	return dots
