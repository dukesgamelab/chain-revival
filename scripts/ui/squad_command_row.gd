class_name SquadCommandRow
extends HBoxContainer
## Top command row: squad-wide orders aligned with per-soldier columns.

signal fire_at_toggled(is_pressed: bool)
signal move_mode_toggled(movement_mode: int, is_pressed: bool)
signal face_toggled(is_pressed: bool)
signal position_toggled(is_down: bool)
signal grenade_toggled(is_pressed: bool)
signal fire_control_selected(fire_control_state: int)

@onready var _fire_at_button: Button = %FireAtButton
@onready var _run_to_button: Button = %RunToButton
@onready var _crawl_to_button: Button = %CrawlToButton
@onready var _face_button: Button = %FaceButton
@onready var _position_button: Button = %PositionButton
@onready var _grenade_button: Button = %GrenadeButton
@onready var _assault_button: Button = %AssaultButton
@onready var _fire_at_will_button: Button = %FireAtWillButton
@onready var _hold_fire_button: Button = %HoldFireButton

var _move_buttons: Dictionary = {}
## Stance for Down/Up label; button itself stays momentary (not latched).
var _position_is_down: bool = false
const _ACTION_FLASH_SEC := 0.1


func _ready() -> void:
	_move_buttons = {
		MovementMode.RUN: _run_to_button,
		MovementMode.CRAWL: _crawl_to_button,
	}
	CocUiTheme.style_grenade_button(_grenade_button)
	_grenade_button.text = ""
	_fire_at_button.tooltip_text = "Fireteam Fire At — click an enemy; all available soldiers engage."
	_run_to_button.tooltip_text = "Fireteam Run To — click tiles to move the squad."
	_crawl_to_button.tooltip_text = "Fireteam Crawl To — click tiles to crawl the squad."
	_face_button.tooltip_text = "Fireteam Face — click a tile or enemy; all soldiers face that way."
	_position_button.tooltip_text = "Set the whole fireteam prone (Down) or standing (Up)."
	_grenade_button.tooltip_text = "Fireteam Grenade — click a tile; all soldiers with grenades throw."
	_assault_button.tooltip_text = "Assault — coming soon."
	_hold_fire_button.tooltip_text = "Hold Fire for the whole fireteam — cease auto-fire."
	_fire_at_will_button.tooltip_text = "Fire At Will for the whole fireteam — fire on sight."

	_fire_at_button.toggled.connect(_on_fire_at_toggled)
	_run_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.RUN))
	_crawl_to_button.toggled.connect(_on_move_toggled.bind(MovementMode.CRAWL))
	_face_button.toggled.connect(_on_face_toggled)
	_position_button.toggled.connect(_on_position_toggled)
	_grenade_button.toggled.connect(_on_grenade_toggled)
	_hold_fire_button.pressed.connect(_on_hold_fire_pressed)
	_fire_at_will_button.pressed.connect(_on_fire_at_will_pressed)
	set_position_state(PositionState.UP)


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
	_flash_release_button(_grenade_button, func() -> void: _grenade_button.modulate = Color.WHITE)


func flash_position() -> void:
	_flash_release_button(_position_button)


func set_fire_at_pressed(is_pressed: bool) -> void:
	_fire_at_button.set_pressed_no_signal(is_pressed)
	_update_fire_at_highlight(is_pressed)


func set_face_pressed(is_pressed: bool) -> void:
	_face_button.set_pressed_no_signal(is_pressed)
	_face_button.modulate = CocUiTheme.selected_modulate(is_pressed)


func set_grenade_pressed(is_pressed: bool) -> void:
	_grenade_button.set_pressed_no_signal(is_pressed)
	_grenade_button.modulate = CocUiTheme.selected_modulate(is_pressed)


func set_position_state(position_state: int) -> void:
	_position_is_down = position_state == PositionState.DOWN
	## Momentary control — never latch pressed; label is the next action.
	_position_button.set_pressed_no_signal(false)
	_position_button.text = "Up" if _position_is_down else "Down"
	_position_button.modulate = Color.WHITE


func apply_coc_inset_wells(inset: StyleBox) -> void:
	for panel_name in ["DotSpacer", "WeaponAmmoSpacer", "StatusHeader", "StressHeader", "HitHeader"]:
		var panel := get_node_or_null(panel_name) as PanelContainer
		if panel != null:
			panel.add_theme_stylebox_override("panel", inset)


func _on_move_toggled(is_pressed: bool, movement_mode: int) -> void:
	move_mode_toggled.emit(movement_mode, is_pressed)


func _on_fire_at_toggled(is_pressed: bool) -> void:
	_update_fire_at_highlight(is_pressed)
	fire_at_toggled.emit(is_pressed)


func _on_face_toggled(is_pressed: bool) -> void:
	_face_button.modulate = CocUiTheme.selected_modulate(is_pressed)
	face_toggled.emit(is_pressed)


func _on_grenade_toggled(is_pressed: bool) -> void:
	_grenade_button.modulate = CocUiTheme.selected_modulate(is_pressed)
	grenade_toggled.emit(is_pressed)


func _on_position_toggled(is_pressed: bool) -> void:
	## Ignore our own unpress; click means "do the labeled next stance".
	if not is_pressed:
		return
	var want_down := not _position_is_down
	_position_is_down = want_down
	_position_button.text = "Up" if want_down else "Down"
	_position_button.modulate = Color.WHITE
	flash_position()
	position_toggled.emit(want_down)


func _flash_release_button(button: Button, on_release: Callable = Callable()) -> void:
	if button == null:
		return
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
	fire_control_selected.emit(FireControlState.HOLD_FIRE)


func _on_fire_at_will_pressed() -> void:
	fire_control_selected.emit(FireControlState.FIRE_AT_WILL)


func _update_fire_at_highlight(is_active: bool) -> void:
	_fire_at_button.modulate = CocUiTheme.selected_modulate(is_active)
