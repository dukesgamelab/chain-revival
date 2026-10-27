extends Control
## Auth screen with two modes: Sign In (default) and Sign Up.
##
## Builds UI in code. The .tscn scene wraps this on a bare Control node.

const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"

var _is_sign_up_mode := false

# Sign-up only fields
var _name_label: Label
var _display_name_field: LineEdit

# Shared fields
var _subtitle: Label
var _email_field: LineEdit
var _password_field: LineEdit
var _primary_button: Button
var _toggle_button: Button
var _status_label: Label
var _back_button: Button


func _ready() -> void:
	CocUiTheme.apply_to(self)
	_build_ui()
	_connect_signals()
	_apply_mode()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Chain Revival"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_subtitle)

	_add_spacer(vbox, 8)

	# Display Name (sign-up only)
	_name_label = Label.new()
	_name_label.text = "Display Name"
	_name_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_name_label)

	_display_name_field = LineEdit.new()
	_display_name_field.placeholder_text = "Your username"
	_display_name_field.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(_display_name_field)

	# Email
	var email_label := Label.new()
	email_label.text = "Email"
	email_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(email_label)

	_email_field = LineEdit.new()
	_email_field.placeholder_text = "you@example.com"
	_email_field.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(_email_field)

	# Password
	var pw_label := Label.new()
	pw_label.text = "Password"
	pw_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(pw_label)

	_password_field = LineEdit.new()
	_password_field.placeholder_text = "Password"
	_password_field.secret = true
	_password_field.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(_password_field)

	_add_spacer(vbox, 4)

	# Primary action button
	_primary_button = Button.new()
	_primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_button.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(_primary_button)

	# Status
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_status_label)

	# Toggle mode link
	_toggle_button = Button.new()
	_toggle_button.flat = true
	_toggle_button.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_toggle_button)

	# Back
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_back_button)


func _add_spacer(parent: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)


func _apply_mode() -> void:
	if _is_sign_up_mode:
		_subtitle.text = "Create a new account"
		_name_label.visible = true
		_display_name_field.visible = true
		_primary_button.text = "Sign Up"
		_toggle_button.text = "Already have an account? Sign In"
	else:
		_subtitle.text = "Sign in to play online"
		_name_label.visible = false
		_display_name_field.visible = false
		_primary_button.text = "Sign In"
		_toggle_button.text = "Don't have an account? Sign Up"
	_status_label.text = ""


func _connect_signals() -> void:
	_primary_button.pressed.connect(_on_primary_pressed)
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_password_field.text_submitted.connect(_on_password_submitted)

	SupabaseAuth.sign_in_succeeded.connect(_on_sign_in_succeeded)
	SupabaseAuth.sign_in_failed.connect(_on_sign_in_failed)
	SupabaseAuth.sign_up_succeeded.connect(_on_sign_up_succeeded)
	SupabaseAuth.sign_up_failed.connect(_on_sign_up_failed)


func _on_toggle_pressed() -> void:
	_is_sign_up_mode = not _is_sign_up_mode
	_apply_mode()


func _on_primary_pressed() -> void:
	if _is_sign_up_mode:
		_do_sign_up()
	else:
		_do_sign_in()


func _on_password_submitted(_text: String) -> void:
	if _is_sign_up_mode:
		_do_sign_up()
	else:
		_do_sign_in()


func _do_sign_in() -> void:
	var email := _email_field.text.strip_edges()
	var password := _password_field.text
	if email.is_empty() or password.is_empty():
		_set_status("Enter your email and password.", Color.ORANGE)
		return
	_set_buttons_enabled(false)
	_set_status("Signing in...", Color.WHITE)
	SupabaseAuth.sign_in(email, password)


func _do_sign_up() -> void:
	var display_name := _display_name_field.text.strip_edges()
	var email := _email_field.text.strip_edges()
	var password := _password_field.text
	if display_name.is_empty():
		_set_status("Enter a display name.", Color.ORANGE)
		return
	if email.is_empty() or password.is_empty():
		_set_status("Enter an email and password.", Color.ORANGE)
		return
	if password.length() < 6:
		_set_status("Password must be at least 6 characters.", Color.ORANGE)
		return
	_set_buttons_enabled(false)
	_set_status("Creating account...", Color.WHITE)
	SupabaseAuth.sign_up(email, password, display_name)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MODE_SELECT_SCENE)


# ─────────────────────────────────────────────────────────────────────────
# Auth callbacks
# ─────────────────────────────────────────────────────────────────────────

func _on_sign_in_succeeded(_user: Dictionary) -> void:
	_set_status("Signed in!", Color.GREEN)
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file(MODE_SELECT_SCENE)


func _on_sign_in_failed(reason: String) -> void:
	_set_status(reason, Color.RED)
	_set_buttons_enabled(true)


func _on_sign_up_succeeded(_user: Dictionary) -> void:
	if SupabaseAuth.is_signed_in:
		_set_status("Account created! Signing you in...", Color.GREEN)
		await get_tree().create_timer(0.5).timeout
		get_tree().change_scene_to_file(MODE_SELECT_SCENE)
	else:
		_set_status("Account created! Check your email to confirm, then sign in.", Color.GREEN)
		_is_sign_up_mode = false
		_apply_mode()
		_set_buttons_enabled(true)


func _on_sign_up_failed(reason: String) -> void:
	_set_status(reason, Color.RED)
	_set_buttons_enabled(true)


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _set_buttons_enabled(enabled: bool) -> void:
	_primary_button.disabled = not enabled
	_toggle_button.disabled = not enabled
	_back_button.disabled = not enabled
