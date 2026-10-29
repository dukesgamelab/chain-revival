extends Control
## Regiment browser and management screen for Chain Revival.
##
## Tabs:
##   - Browse: list active regiments, request to join, apply to create
##   - My Regiment: roster, join requests, manage members (CO/XO)
##   - Admin: approve/reject regiment applications (admins only)

const LOBBY_BROWSER_SCENE := "res://scenes/lobby_browser.tscn"
const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"
const RegimentClientClass := preload("res://scripts/network/regiment_client.gd")
const RANK_LABELS := ["PVT", "PFC", "CPL", "SGT", "SSG", "SFC", "MSG", "2LT", "1LT", "CPT"]

var _regiment_client: Node  # RegimentClientClass instance
var _tab_bar: TabBar
var _content_stack: Control
var _browse_panel: Control
var _my_regiment_panel: Control
var _admin_panel: Control
var _status_label: Label
var _back_button: Button

# Browse tab
var _regiment_list_container: VBoxContainer
var _create_button: Button

# Create form
var _create_form: PanelContainer
var _name_input: LineEdit
var _tag_input: LineEdit
var _desc_input: TextEdit
var _submit_create_button: Button
var _cancel_create_button: Button

# My Regiment tab
var _my_reg_container: VBoxContainer
var _my_reg_info_label: Label
var _roster_container: VBoxContainer
var _join_requests_container: VBoxContainer
var _edit_container: VBoxContainer
var _edit_desc_input: TextEdit
var _edit_website_input: LineEdit
var _leave_button: Button

# Admin tab
var _admin_container: VBoxContainer
var _admin_tab_bar: TabBar
var _admin_apps_section: VBoxContainer
var _admin_regiments_section: VBoxContainer
var _admin_reg_container: VBoxContainer

# State
var _current_regiment: Dictionary = {}
var _is_co := false
var _is_xo := false

## Which scene to return to.
static var return_scene: String = ""


func _ready() -> void:
	CocUiTheme.apply_to(self)
	_setup_client()
	_build_ui()
	_refresh_browse()
	if SupabaseAuth.regiment_id != "":
		_refresh_my_regiment()


func _setup_client() -> void:
	_regiment_client = RegimentClientClass.new()
	add_child(_regiment_client)
	_regiment_client.regiment_list_loaded.connect(_on_regiment_list)
	_regiment_client.regiment_loaded.connect(_on_regiment_loaded)
	_regiment_client.regiment_members_loaded.connect(_on_members_loaded)
	_regiment_client.regiment_error.connect(_on_error)
	_regiment_client.application_submitted.connect(_on_application_submitted)
	_regiment_client.application_list_loaded.connect(_on_app_list_loaded)
	_regiment_client.application_resolved.connect(_on_app_resolved)
	_regiment_client.join_request_submitted.connect(_on_join_submitted)
	_regiment_client.join_requests_loaded.connect(_on_join_requests_loaded)
	_regiment_client.join_request_resolved.connect(_on_join_resolved)
	_regiment_client.member_kicked.connect(_on_member_kicked)
	_regiment_client.rank_assigned.connect(_on_rank_assigned)
	_regiment_client.xo_set.connect(_on_xo_set)
	_regiment_client.details_updated.connect(_on_details_updated)


# ─────────────────────────────────────────────────────────────────────────
# UI Construction
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Use a margin container instead of center to leave room for the chat panel
	var wrapper := MarginContainer.new()
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_theme_constant_override("margin_right", 280)  # chat panel width + padding
	wrapper.add_theme_constant_override("margin_left", 20)
	wrapper.add_theme_constant_override("margin_top", 20)
	wrapper.add_theme_constant_override("margin_bottom", 20)
	add_child(wrapper)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(center)

	var outer_panel := PanelContainer.new()
	outer_panel.custom_minimum_size = Vector2(700, 520)
	center.add_child(outer_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	outer_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Regiments"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Status
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_status_label)

	# Tabs
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Browse")
	if SupabaseAuth.is_signed_in:
		_tab_bar.add_tab("My Regiment")
	if SupabaseAuth.is_admin:
		_tab_bar.add_tab("Admin")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tab_bar)

	# Content
	_content_stack = Control.new()
	_content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_stack)

	_browse_panel = _build_browse_panel()
	_content_stack.add_child(_browse_panel)

	_my_regiment_panel = _build_my_regiment_panel()
	_my_regiment_panel.visible = false
	_content_stack.add_child(_my_regiment_panel)

	if SupabaseAuth.is_admin:
		_admin_panel = _build_admin_panel()
		_admin_panel.visible = false
		_content_stack.add_child(_admin_panel)

	# Bottom buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.custom_minimum_size = Vector2(0, 34)
	_back_button.pressed.connect(_on_back_pressed)
	btn_row.add_child(_back_button)


func _build_browse_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 4)

	# Header row
	var header := _make_regiment_row("Name", "Tag", "CO", "Members", true)
	panel.add_child(header)

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_regiment_list_container = VBoxContainer.new()
	_regiment_list_container.add_theme_constant_override("separation", 2)
	_regiment_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_regiment_list_container)

	# Create regiment button (only if signed in and not already in a regiment)
	if SupabaseAuth.is_signed_in and SupabaseAuth.regiment_id == "":
		_create_button = Button.new()
		_create_button.text = "Apply to Create Regiment"
		_create_button.custom_minimum_size = Vector2(0, 30)
		_create_button.pressed.connect(_show_create_form)
		panel.add_child(_create_button)

	# Create form (hidden by default)
	_create_form = _build_create_form()
	_create_form.visible = false
	panel.add_child(_create_form)

	return panel


func _build_create_form() -> PanelContainer:
	var form_panel := PanelContainer.new()
	var form_margin := MarginContainer.new()
	form_margin.add_theme_constant_override("margin_left", 12)
	form_margin.add_theme_constant_override("margin_top", 8)
	form_margin.add_theme_constant_override("margin_right", 12)
	form_margin.add_theme_constant_override("margin_bottom", 8)
	form_panel.add_child(form_margin)

	var form_vbox := VBoxContainer.new()
	form_vbox.add_theme_constant_override("separation", 6)
	form_margin.add_child(form_vbox)

	var form_title := Label.new()
	form_title.text = "Create Regiment Application"
	form_title.add_theme_font_size_override("font_size", 14)
	form_vbox.add_child(form_title)

	# Name
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	form_vbox.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size = Vector2(80, 0)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_row.add_child(name_lbl)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Regiment name"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.add_theme_font_size_override("font_size", 13)
	_name_input.add_theme_color_override("font_color", Color.WHITE)
	name_row.add_child(_name_input)

	# Tag
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	form_vbox.add_child(tag_row)
	var tag_lbl := Label.new()
	tag_lbl.text = "Tag:"
	tag_lbl.custom_minimum_size = Vector2(80, 0)
	tag_lbl.add_theme_font_size_override("font_size", 13)
	tag_row.add_child(tag_lbl)
	_tag_input = LineEdit.new()
	_tag_input.placeholder_text = "Short tag (e.g. WOLF)"
	_tag_input.max_length = 6
	_tag_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_input.add_theme_font_size_override("font_size", 13)
	_tag_input.add_theme_color_override("font_color", Color.WHITE)
	tag_row.add_child(_tag_input)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = "Description:"
	desc_lbl.add_theme_font_size_override("font_size", 13)
	form_vbox.add_child(desc_lbl)
	_desc_input = TextEdit.new()
	_desc_input.placeholder_text = "Describe your regiment..."
	_desc_input.custom_minimum_size = Vector2(0, 60)
	_desc_input.add_theme_font_size_override("font_size", 12)
	_desc_input.add_theme_color_override("font_color", Color.WHITE)
	form_vbox.add_child(_desc_input)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	form_vbox.add_child(btn_row)
	_submit_create_button = Button.new()
	_submit_create_button.text = "Submit Application"
	_submit_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submit_create_button.pressed.connect(_on_submit_create)
	btn_row.add_child(_submit_create_button)
	_cancel_create_button = Button.new()
	_cancel_create_button.text = "Cancel"
	_cancel_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_create_button.pressed.connect(_hide_create_form)
	btn_row.add_child(_cancel_create_button)

	return form_panel


func _build_my_regiment_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 6)

	_my_reg_info_label = Label.new()
	_my_reg_info_label.text = "Not in a regiment"
	_my_reg_info_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_my_reg_info_label)

	# Roster section
	var roster_title := Label.new()
	roster_title.text = "Roster"
	roster_title.add_theme_font_size_override("font_size", 13)
	roster_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	panel.add_child(roster_title)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(roster_scroll)

	_roster_container = VBoxContainer.new()
	_roster_container.add_theme_constant_override("separation", 2)
	_roster_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(_roster_container)

	# Edit section (CO only, shown dynamically)
	_edit_container = VBoxContainer.new()
	_edit_container.add_theme_constant_override("separation", 4)
	_edit_container.visible = false
	panel.add_child(_edit_container)

	# Join requests section (CO/XO only, populated dynamically)
	_join_requests_container = VBoxContainer.new()
	_join_requests_container.add_theme_constant_override("separation", 2)
	_join_requests_container.visible = false
	panel.add_child(_join_requests_container)

	# Leave button
	_leave_button = Button.new()
	_leave_button.text = "Leave Regiment"
	_leave_button.custom_minimum_size = Vector2(0, 30)
	_leave_button.pressed.connect(_on_leave_pressed)
	panel.add_child(_leave_button)

	return panel


func _build_admin_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 4)

	# Admin sub-tabs
	_admin_tab_bar = TabBar.new()
	_admin_tab_bar.add_tab("Applications")
	_admin_tab_bar.add_tab("Manage Regiments")
	_admin_tab_bar.tab_changed.connect(_on_admin_tab_changed)
	panel.add_child(_admin_tab_bar)

	# Applications section
	_admin_apps_section = VBoxContainer.new()
	_admin_apps_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_admin_apps_section)

	var apps_scroll := ScrollContainer.new()
	apps_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	apps_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_admin_apps_section.add_child(apps_scroll)

	_admin_container = VBoxContainer.new()
	_admin_container.add_theme_constant_override("separation", 4)
	_admin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apps_scroll.add_child(_admin_container)

	# Manage Regiments section
	_admin_regiments_section = VBoxContainer.new()
	_admin_regiments_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_admin_regiments_section.visible = false
	panel.add_child(_admin_regiments_section)

	var reg_scroll := ScrollContainer.new()
	reg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reg_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_admin_regiments_section.add_child(reg_scroll)

	_admin_reg_container = VBoxContainer.new()
	_admin_reg_container.add_theme_constant_override("separation", 4)
	_admin_reg_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reg_scroll.add_child(_admin_reg_container)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(0, 30)
	refresh_btn.pressed.connect(_refresh_admin)
	panel.add_child(refresh_btn)

	return panel


func _on_admin_tab_changed(tab_idx: int) -> void:
	_admin_apps_section.visible = (tab_idx == 0)
	_admin_regiments_section.visible = (tab_idx == 1)
	if tab_idx == 1:
		_fetch_all_regiments_admin()


# ─────────────────────────────────────────────────────────────────────────
# Row builders
# ─────────────────────────────────────────────────────────────────────────

func _make_regiment_row(name_text: String, tag_text: String, co_text: String,
		members_text: String, is_header: bool, regiment_id: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var font_size := 12 if is_header else 13
	var color := Color(0.7, 0.7, 0.7) if is_header else Color.WHITE

	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", color)
	row.add_child(name_label)

	var tag_label := Label.new()
	tag_label.text = tag_text
	tag_label.custom_minimum_size = Vector2(60, 0)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override("font_size", font_size)
	tag_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0) if not is_header else color)
	row.add_child(tag_label)

	var co_label := Label.new()
	co_label.text = co_text
	co_label.custom_minimum_size = Vector2(120, 0)
	co_label.add_theme_font_size_override("font_size", font_size)
	co_label.add_theme_color_override("font_color", color)
	row.add_child(co_label)

	var members_label := Label.new()
	members_label.text = members_text
	members_label.custom_minimum_size = Vector2(70, 0)
	members_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	members_label.add_theme_font_size_override("font_size", font_size)
	members_label.add_theme_color_override("font_color", color)
	row.add_child(members_label)

	# Join button (only on data rows, only if signed in and not in a regiment)
	if not is_header and SupabaseAuth.is_signed_in and SupabaseAuth.regiment_id == "":
		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.custom_minimum_size = Vector2(50, 0)
		join_btn.pressed.connect(_on_request_join.bind(regiment_id))
		row.add_child(join_btn)
	elif not is_header:
		# Spacer to keep alignment
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(50, 0)
		row.add_child(spacer)

	return row


func _make_member_row(display_name: String, rank_text: String, assigned_rank: String,
		role_text: String, player_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var display_rank := assigned_rank if assigned_rank != "" else rank_text
	var name_btn := Button.new()
	name_btn.text = "%s %s" % [display_rank, display_name]
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.add_theme_font_size_override("font_size", 13)
	name_btn.flat = true
	name_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	name_btn.pressed.connect(_on_view_player_stats.bind(player_id, display_name))
	row.add_child(name_btn)

	if role_text != "":
		var role_label := Label.new()
		role_label.text = role_text
		role_label.custom_minimum_size = Vector2(40, 0)
		role_label.add_theme_font_size_override("font_size", 11)
		role_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		row.add_child(role_label)

	# CO/XO management buttons (never show Kick for the CO)
	if (_is_co or _is_xo) and player_id != SupabaseAuth.user_id and role_text != "CO":
		var kick_btn := Button.new()
		kick_btn.text = "Kick"
		kick_btn.custom_minimum_size = Vector2(45, 0)
		kick_btn.add_theme_font_size_override("font_size", 11)
		kick_btn.pressed.connect(_on_kick_member.bind(player_id))
		row.add_child(kick_btn)

	# CO-only: set/remove XO button
	if _is_co and player_id != SupabaseAuth.user_id:
		if role_text == "XO":
			var remove_xo_btn := Button.new()
			remove_xo_btn.text = "Remove XO"
			remove_xo_btn.custom_minimum_size = Vector2(75, 0)
			remove_xo_btn.add_theme_font_size_override("font_size", 11)
			remove_xo_btn.pressed.connect(_on_remove_xo)
			row.add_child(remove_xo_btn)
		else:
			var xo_btn := Button.new()
			xo_btn.text = "Set XO"
			xo_btn.custom_minimum_size = Vector2(55, 0)
			xo_btn.add_theme_font_size_override("font_size", 11)
			xo_btn.pressed.connect(_on_set_xo.bind(player_id))
			row.add_child(xo_btn)

	# CO/XO: rank assignment (only for 2LT+ members, not CO/XO themselves)
	if (_is_co or _is_xo) and player_id != SupabaseAuth.user_id and role_text == "":
		var pp_rank_idx := 0
		var profile = {}
		# Find this member's PP rank from the roster data
		for child in _roster_container.get_children():
			pass  # rank is already in rank_text param
		# Only show rank button if player is 2LT+ (rank index 7+)
		if rank_text in ["2LT", "1LT", "CPT"]:
			var rank_btn := OptionButton.new()
			rank_btn.add_theme_font_size_override("font_size", 11)
			rank_btn.custom_minimum_size = Vector2(75, 0)
			rank_btn.add_item("No Rank", 0)
			rank_btn.add_item("1LT", 1)
			rank_btn.add_item("CPT", 2)
			rank_btn.add_item("MAJ", 3)
			rank_btn.add_item("LT COL", 4)
			rank_btn.add_item("COL", 5)
			# Select current assigned rank
			var rank_names := ["", "1LT", "CPT", "MAJ", "LT COL", "COL"]
			for ri in range(rank_names.size()):
				if rank_names[ri] == assigned_rank:
					rank_btn.select(ri)
					break
			rank_btn.item_selected.connect(_on_rank_selected.bind(player_id, rank_btn))
			row.add_child(rank_btn)

	return row


# ─────────────────────────────────────────────────────────────────────────
# Tab switching
# ─────────────────────────────────────────────────────────────────────────

func _on_tab_changed(tab_idx: int) -> void:
	_browse_panel.visible = (tab_idx == 0)
	_my_regiment_panel.visible = (tab_idx == 1)
	if _admin_panel != null:
		var admin_tab_idx := 2 if SupabaseAuth.is_signed_in else 1
		_admin_panel.visible = (tab_idx == admin_tab_idx)
		if tab_idx == admin_tab_idx:
			_refresh_admin()
	if tab_idx == 1 and SupabaseAuth.is_signed_in:
		_refresh_my_regiment()


# ─────────────────────────────────────────────────────────────────────────
# Data loading
# ─────────────────────────────────────────────────────────────────────────

func _refresh_browse() -> void:
	_status_label.text = "Loading regiments..."
	_regiment_client.list_regiments()


func _refresh_my_regiment() -> void:
	if SupabaseAuth.regiment_id == "":
		_my_reg_info_label.text = "You are not in a regiment."
		_clear_container(_roster_container)
		_join_requests_container.visible = false
		_leave_button.visible = false
		return
	_regiment_client.load_regiment(SupabaseAuth.regiment_id)
	_regiment_client.load_members(SupabaseAuth.regiment_id)


func _refresh_admin() -> void:
	if not SupabaseAuth.is_admin:
		return
	_regiment_client.list_pending_applications()


# ─────────────────────────────────────────────────────────────────────────
# Signal handlers: data loaded
# ─────────────────────────────────────────────────────────────────────────

func _on_regiment_list(regiments: Array) -> void:
	# Route to admin panel if that's what triggered the fetch
	if _admin_reg_fetch_pending:
		_admin_reg_fetch_pending = false
		_admin_all_regiments = regiments
		_resolve_admin_regiment_names(regiments)
		return

	_clear_container(_regiment_list_container)
	_status_label.text = "%d regiment%s" % [regiments.size(), "" if regiments.size() == 1 else "s"]

	if regiments.is_empty():
		var empty := Label.new()
		empty.text = "No active regiments yet"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_regiment_list_container.add_child(empty)
		return

	# We need CO display names. Fetch them.
	var co_ids: Array[String] = []
	for reg in regiments:
		var co_id: String = str(reg.get("co_id", ""))
		if co_id != "" and co_id not in co_ids:
			co_ids.append(co_id)

	# For now, show regiments with CO ID placeholder; then resolve names
	for reg in regiments:
		var reg_name: String = reg.get("name", "???")
		var reg_tag: String = reg.get("tag", "?")
		var reg_id: String = reg.get("id", "")
		var co_id: String = str(reg.get("co_id", ""))
		# Members count: we'd need a separate query. Show "?" for now.
		var row := _make_regiment_row(reg_name, reg_tag, co_id.left(8) + "...", "?", false, reg_id)
		_regiment_list_container.add_child(row)

	# Resolve CO names
	_fetch_co_names(regiments)


func _on_regiment_loaded(regiment: Dictionary) -> void:
	_current_regiment = regiment
	var name_text: String = regiment.get("name", "?")
	var tag_text: String = regiment.get("tag", "?")
	var desc_text: String = regiment.get("description", "")
	var raw_website = regiment.get("website_url", null)
	var website: String = str(raw_website) if raw_website != null else ""

	_is_co = (str(regiment.get("co_id", "")) == SupabaseAuth.user_id)
	_is_xo = (str(regiment.get("xo_id", "")) == SupabaseAuth.user_id)

	var info_parts: Array[String] = ["[%s] %s" % [tag_text, name_text]]
	if desc_text != "":
		info_parts.append(desc_text)
	if website != "":
		info_parts.append("Web: %s" % website)
	var role := " (CO)" if _is_co else (" (XO)" if _is_xo else "")
	info_parts.append("Your role: Member%s" % role)
	_my_reg_info_label.text = "\n".join(info_parts)

	_leave_button.visible = not _is_co  # CO cannot leave (must disband)

	# Show edit button for CO
	_show_edit_controls(_is_co, desc_text, website)

	# Load join requests if CO/XO
	if _is_co or _is_xo:
		_join_requests_container.visible = true
		_regiment_client.list_join_requests(str(regiment.get("id", "")))
	else:
		_join_requests_container.visible = false


func _on_members_loaded(members: Array) -> void:
	_clear_container(_roster_container)

	if members.is_empty():
		var empty := Label.new()
		empty.text = "No members"
		empty.add_theme_font_size_override("font_size", 13)
		_roster_container.add_child(empty)
		return

	for m in members:
		var player_id: String = str(m.get("player_id", ""))
		var raw_rank = m.get("assigned_rank", null)
		var assigned: String = str(raw_rank) if raw_rank != null else ""
		if assigned == "null" or assigned == "<null>":
			assigned = ""
		var profile = m.get("player_profiles", {})
		var display_name: String = "???"
		var pp_rank: int = 0
		if profile is Dictionary:
			display_name = str(profile.get("display_name", "???"))
			pp_rank = int(profile.get("rank", 0))
		var rank_text: String = RANK_LABELS[clampi(pp_rank, 0, RANK_LABELS.size() - 1)]

		# Determine role label
		var role := ""
		if not _current_regiment.is_empty():
			if player_id == str(_current_regiment.get("co_id", "")):
				role = "CO"
			elif player_id == str(_current_regiment.get("xo_id", "")):
				role = "XO"

		var row := _make_member_row(display_name, rank_text, assigned, role, player_id)
		_roster_container.add_child(row)


var _pending_join_requests: Array = []
var _join_names_http: HTTPRequest

func _on_join_requests_loaded(requests: Array) -> void:
	_pending_join_requests = requests
	_clear_container(_join_requests_container)

	if requests.is_empty():
		var title := Label.new()
		title.text = "Pending Join Requests: none"
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_join_requests_container.add_child(title)
		return

	# Resolve player names before displaying
	var player_ids: Array[String] = []
	for req in requests:
		var pid: String = str(req.get("player_id", ""))
		if pid != "" and pid not in player_ids:
			player_ids.append(pid)

	if _join_names_http != null:
		_join_names_http.queue_free()
	_join_names_http = HTTPRequest.new()
	add_child(_join_names_http)
	_join_names_http.request_completed.connect(_on_join_names_response)

	var id_filter := "(" + ",".join(player_ids) + ")"
	var url := "%s/rest/v1/player_profiles?id=in.%s&select=id,display_name" % [SupabaseAuth.SUPABASE_URL, id_filter]
	var hdrs := PackedStringArray([
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])
	_join_names_http.request(url, hdrs, HTTPClient.METHOD_GET)


func _on_join_names_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	var name_map: Dictionary = {}
	if response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
			for p in json.data:
				name_map[str(p.get("id", ""))] = str(p.get("display_name", "???"))

	_populate_join_requests(_pending_join_requests, name_map)


func _populate_join_requests(requests: Array, name_map: Dictionary) -> void:
	_clear_container(_join_requests_container)

	var title := Label.new()
	title.text = "Pending Join Requests:"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_join_requests_container.add_child(title)

	for req in requests:
		var req_id: String = str(req.get("id", ""))
		var player_id: String = str(req.get("player_id", ""))
		var direction: String = str(req.get("direction", ""))
		var player_name: String = name_map.get(player_id, player_id.left(8) + "...")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var info_label := Label.new()
		info_label.text = "%s (%s)" % [player_name, direction]
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_label.add_theme_font_size_override("font_size", 12)
		row.add_child(info_label)

		if direction == "request":
			var accept_btn := Button.new()
			accept_btn.text = "Accept"
			accept_btn.custom_minimum_size = Vector2(60, 0)
			accept_btn.add_theme_font_size_override("font_size", 11)
			accept_btn.pressed.connect(_on_accept_join.bind(req_id))
			row.add_child(accept_btn)

			var reject_btn := Button.new()
			reject_btn.text = "Reject"
			reject_btn.custom_minimum_size = Vector2(60, 0)
			reject_btn.add_theme_font_size_override("font_size", 11)
			reject_btn.pressed.connect(_on_reject_join.bind(req_id))
			row.add_child(reject_btn)

		_join_requests_container.add_child(row)


func _on_app_list_loaded(applications: Array) -> void:
	_clear_container(_admin_container)

	if applications.is_empty():
		var empty := Label.new()
		empty.text = "No pending applications"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_admin_container.add_child(empty)
		return

	for app in applications:
		var app_id: String = str(app.get("id", ""))
		var app_type: String = str(app.get("type", ""))
		var app_name: String = str(app.get("regiment_name", ""))
		var app_tag: String = str(app.get("regiment_tag", ""))
		var app_desc: String = str(app.get("description", ""))

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)

		var header_text := ""
		if app_type == "create":
			header_text = "CREATE: [%s] %s" % [app_tag, app_name]
		else:
			header_text = "DISBAND: %s" % app_name

		var header_label := Label.new()
		header_label.text = header_text
		header_label.add_theme_font_size_override("font_size", 14)
		header_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		card.add_child(header_label)

		if app_desc != "":
			var desc_label := Label.new()
			desc_label.text = app_desc
			desc_label.add_theme_font_size_override("font_size", 12)
			desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			card.add_child(desc_label)

		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)
		card.add_child(btn_row)

		var approve_btn := Button.new()
		approve_btn.text = "Approve"
		approve_btn.custom_minimum_size = Vector2(80, 28)
		approve_btn.pressed.connect(_on_approve_app.bind(app_id))
		btn_row.add_child(approve_btn)

		var reject_btn := Button.new()
		reject_btn.text = "Reject"
		reject_btn.custom_minimum_size = Vector2(80, 28)
		reject_btn.pressed.connect(_on_reject_app.bind(app_id))
		btn_row.add_child(reject_btn)

		# Separator
		var sep := HSeparator.new()
		card.add_child(sep)

		_admin_container.add_child(card)


# ─────────────────────────────────────────────────────────────────────────
# Signal handlers: actions
# ─────────────────────────────────────────────────────────────────────────

func _on_application_submitted() -> void:
	_status_label.text = "Application submitted! Awaiting admin approval."
	_hide_create_form()


func _on_app_resolved() -> void:
	_status_label.text = "Application resolved."
	# Re-fetch profile so regiment_id updates if we just approved our own
	SupabaseAuth.fetch_profile()
	await get_tree().create_timer(0.5).timeout
	_refresh_admin()
	_refresh_browse()
	_refresh_my_regiment()


func _on_join_submitted() -> void:
	_status_label.text = "Join request sent!"


func _on_join_resolved() -> void:
	_status_label.text = "Done."
	# Re-fetch profile to update regiment_id
	SupabaseAuth.fetch_profile()
	# Small delay then refresh
	await get_tree().create_timer(0.5).timeout
	_refresh_my_regiment()
	_refresh_browse()


func _on_member_kicked() -> void:
	_status_label.text = "Member kicked."
	_refresh_my_regiment()


func _on_rank_assigned() -> void:
	_status_label.text = "Rank assigned."
	_refresh_my_regiment()


func _on_xo_set() -> void:
	_status_label.text = "XO updated."
	_refresh_my_regiment()


func _on_details_updated() -> void:
	_status_label.text = "Details updated."
	_refresh_my_regiment()


func _on_error(msg: String) -> void:
	_status_label.text = "Error: %s" % msg


# ─────────────────────────────────────────────────────────────────────────
# Button handlers
# ─────────────────────────────────────────────────────────────────────────

func _show_create_form() -> void:
	_create_form.visible = true
	if _create_button != null:
		_create_button.visible = false


func _hide_create_form() -> void:
	_create_form.visible = false
	if _create_button != null:
		_create_button.visible = true
	_name_input.text = ""
	_tag_input.text = ""
	_desc_input.text = ""


func _on_submit_create() -> void:
	var reg_name := _name_input.text.strip_edges()
	var reg_tag := _tag_input.text.strip_edges().to_upper()
	var reg_desc := _desc_input.text.strip_edges()

	if reg_name.is_empty():
		_status_label.text = "Regiment name is required."
		return
	if reg_tag.is_empty():
		_status_label.text = "Regiment tag is required."
		return

	_regiment_client.apply_create_regiment(reg_name, reg_tag, reg_desc)


func _on_request_join(regiment_id: String) -> void:
	_regiment_client.request_join(regiment_id)


func _on_accept_join(request_id: String) -> void:
	_regiment_client.accept_join(request_id)


func _on_reject_join(request_id: String) -> void:
	_regiment_client.reject_join(request_id)


func _on_approve_app(app_id: String) -> void:
	_regiment_client.approve_application(app_id)


func _on_reject_app(app_id: String) -> void:
	_regiment_client.reject_application(app_id)


func _on_kick_member(player_id: String) -> void:
	if _current_regiment.is_empty():
		return
	_regiment_client.kick_member(str(_current_regiment.get("id", "")), player_id)


func _on_set_xo(player_id: String) -> void:
	if _current_regiment.is_empty():
		return
	_regiment_client.set_xo(str(_current_regiment.get("id", "")), player_id)


func _on_remove_xo() -> void:
	if _current_regiment.is_empty():
		return
	_regiment_client.set_xo(str(_current_regiment.get("id", "")), "")


# ─────────────────────────────────────────────────────────────────────────
# Player stats popup
# ─────────────────────────────────────────────────────────────────────────

var _stats_popup: AcceptDialog
var _stats_http_profile: HTTPRequest
var _stats_http_history: HTTPRequest
var _stats_container: VBoxContainer
var _stats_player_name: String = ""

func _on_view_player_stats(player_id: String, display_name: String) -> void:
	_stats_player_name = display_name
	_show_stats_popup(display_name)
	_fetch_player_stats(player_id)
	_fetch_player_history(player_id)


func _show_stats_popup(display_name: String) -> void:
	if _stats_popup != null:
		_stats_popup.queue_free()

	_stats_popup = AcceptDialog.new()
	_stats_popup.title = "Player Stats"
	_stats_popup.size = Vector2i(450, 350)
	_stats_popup.unresizable = false
	add_child(_stats_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	_stats_popup.add_child(margin)

	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 6)
	margin.add_child(_stats_container)

	var loading := Label.new()
	loading.text = "Loading stats for %s..." % display_name
	loading.add_theme_font_size_override("font_size", 13)
	_stats_container.add_child(loading)

	_stats_popup.popup_centered()


func _fetch_player_stats(player_id: String) -> void:
	if _stats_http_profile != null:
		_stats_http_profile.queue_free()
	_stats_http_profile = HTTPRequest.new()
	add_child(_stats_http_profile)
	_stats_http_profile.request_completed.connect(_on_stats_profile_response)

	var url := "%s/rest/v1/player_profiles?id=eq.%s&select=display_name,games_played,games_won,total_kills,rank,prestige_points" % [SupabaseAuth.SUPABASE_URL, player_id]
	var hdrs := PackedStringArray([
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])
	_stats_http_profile.request(url, hdrs, HTTPClient.METHOD_GET)


func _fetch_player_history(player_id: String) -> void:
	if _stats_http_history != null:
		_stats_http_history.queue_free()
	_stats_http_history = HTTPRequest.new()
	add_child(_stats_http_history)
	_stats_http_history.request_completed.connect(_on_stats_history_response)

	var url := "%s/rest/v1/match_history?player_id=eq.%s&order=played_at.desc&limit=10" % [SupabaseAuth.SUPABASE_URL, player_id]
	var hdrs := PackedStringArray([
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])
	_stats_http_history.request(url, hdrs, HTTPClient.METHOD_GET)


func _on_stats_profile_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if _stats_container == null:
		return
	if response_code != 200:
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	if not json.data is Array or json.data.is_empty():
		return

	var p: Dictionary = json.data[0]
	var display_name: String = p.get("display_name", "???")
	var played: int = int(p.get("games_played", 0))
	var wins: int = int(p.get("games_won", 0))
	var kills: int = int(p.get("total_kills", 0))
	var pp: int = int(p.get("prestige_points", 0))
	var player_rank: int = int(p.get("rank", 0))
	var rank_label: String = RANK_LABELS[clampi(player_rank, 0, RANK_LABELS.size() - 1)]
	var winrate := 0.0
	if played > 0:
		winrate = float(wins) / float(played) * 100.0

	# Clear loading text and show stats
	_clear_container(_stats_container)

	var title := Label.new()
	title.text = "%s %s" % [rank_label, display_name]
	title.add_theme_font_size_override("font_size", 16)
	_stats_container.add_child(title)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 4)
	_stats_container.add_child(stats_grid)

	var stat_pairs := [
		["Prestige Points", str(pp)],
		["Games Played", str(played)],
		["Wins", str(wins)],
		["Win Rate", "%.0f%%" % winrate],
		["Total Kills", str(kills)],
	]

	for pair in stat_pairs:
		var key_label := Label.new()
		key_label.text = pair[0]
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		stats_grid.add_child(key_label)

		var val_label := Label.new()
		val_label.text = pair[1]
		val_label.add_theme_font_size_override("font_size", 12)
		stats_grid.add_child(val_label)

	# Separator before match history
	_stats_container.add_child(HSeparator.new())

	var hist_title := Label.new()
	hist_title.text = "Recent Matches"
	hist_title.add_theme_font_size_override("font_size", 13)
	hist_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_stats_container.add_child(hist_title)

	# History will be populated by the other callback
	var hist_placeholder := Label.new()
	hist_placeholder.name = "HistPlaceholder"
	hist_placeholder.text = "Loading..."
	hist_placeholder.add_theme_font_size_override("font_size", 11)
	_stats_container.add_child(hist_placeholder)


func _on_stats_history_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if _stats_container == null:
		return

	# Remove placeholder if it exists
	var placeholder := _stats_container.get_node_or_null("HistPlaceholder")
	if placeholder != null:
		placeholder.queue_free()

	if response_code != 200:
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	if not json.data is Array:
		return

	var matches: Array = json.data

	if matches.is_empty():
		var empty := Label.new()
		empty.text = "No matches yet"
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_stats_container.add_child(empty)
		return

	# Header
	var header := _make_stats_hist_row("Result", "Team", "Kills", "PP", "Date", true)
	_stats_container.add_child(header)

	for m in matches:
		var result_text := "Draw"
		if m.get("won", false):
			result_text = "Win"
		elif not m.get("draw", false):
			result_text = "Loss"

		var team_text: String = m.get("team", "?")
		var match_kills: int = int(m.get("kills", 0))
		var match_pp: int = int(m.get("pp_earned", 0))
		var pp_text := "+%d" % match_pp if match_pp >= 0 else str(match_pp)
		var played_at: String = m.get("played_at", "")
		var date_text := _format_date(played_at)

		var row := _make_stats_hist_row(result_text, team_text, str(match_kills), pp_text, date_text, false)
		_stats_container.add_child(row)


func _make_stats_hist_row(result_text: String, team_text: String, kills_text: String,
		pp_text: String, date_text: String, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var font_size := 10 if is_header else 11

	var result_label := Label.new()
	result_label.text = result_text
	result_label.custom_minimum_size = Vector2(40, 0)
	result_label.add_theme_font_size_override("font_size", font_size)
	if is_header:
		result_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	elif result_text == "Win":
		result_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	elif result_text == "Loss":
		result_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	else:
		result_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	row.add_child(result_label)

	var team_label := Label.new()
	team_label.text = team_text
	team_label.custom_minimum_size = Vector2(60, 0)
	team_label.add_theme_font_size_override("font_size", font_size)
	team_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6) if is_header else Color.WHITE)
	row.add_child(team_label)

	var kills_label := Label.new()
	kills_label.text = kills_text
	kills_label.custom_minimum_size = Vector2(35, 0)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_font_size_override("font_size", font_size)
	kills_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6) if is_header else Color.WHITE)
	row.add_child(kills_label)

	var pp_label := Label.new()
	pp_label.text = pp_text
	pp_label.custom_minimum_size = Vector2(40, 0)
	pp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pp_label.add_theme_font_size_override("font_size", font_size)
	pp_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6) if is_header else Color(0.4, 0.85, 1.0))
	row.add_child(pp_label)

	var date_label := Label.new()
	date_label.text = date_text
	date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.add_theme_font_size_override("font_size", font_size)
	date_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(date_label)

	return row


func _format_date(iso_str: String) -> String:
	if iso_str.is_empty():
		return "?"
	var date_part := iso_str.left(10)
	var parts := date_part.split("-")
	if parts.size() < 3:
		return date_part
	var month_names := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_idx := int(parts[1])
	if month_idx < 1 or month_idx > 12:
		return date_part
	return "%s %s" % [month_names[month_idx], str(int(parts[2]))]


func _on_rank_selected(index: int, player_id: String, btn: OptionButton) -> void:
	if _current_regiment.is_empty():
		return
	var rank_names := ["", "1LT", "CPT", "MAJ", "LT COL", "COL"]
	var selected_rank: String = rank_names[index] if index < rank_names.size() else ""
	_regiment_client.assign_rank(str(_current_regiment.get("id", "")), player_id, selected_rank)


func _show_edit_controls(show: bool, current_desc: String, current_website: String) -> void:
	_clear_container(_edit_container)
	_edit_container.visible = show
	if not show:
		return

	var edit_title := Label.new()
	edit_title.text = "Edit Regiment"
	edit_title.add_theme_font_size_override("font_size", 13)
	edit_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_edit_container.add_child(edit_title)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = "Description:"
	desc_lbl.add_theme_font_size_override("font_size", 12)
	_edit_container.add_child(desc_lbl)
	_edit_desc_input = TextEdit.new()
	_edit_desc_input.text = current_desc
	_edit_desc_input.custom_minimum_size = Vector2(0, 50)
	_edit_desc_input.add_theme_font_size_override("font_size", 12)
	_edit_desc_input.add_theme_color_override("font_color", Color.WHITE)
	_edit_container.add_child(_edit_desc_input)

	# Website
	var web_row := HBoxContainer.new()
	web_row.add_theme_constant_override("separation", 8)
	_edit_container.add_child(web_row)
	var web_lbl := Label.new()
	web_lbl.text = "Website:"
	web_lbl.custom_minimum_size = Vector2(65, 0)
	web_lbl.add_theme_font_size_override("font_size", 12)
	web_row.add_child(web_lbl)
	_edit_website_input = LineEdit.new()
	_edit_website_input.text = current_website
	_edit_website_input.placeholder_text = "https://..."
	_edit_website_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_website_input.add_theme_font_size_override("font_size", 12)
	_edit_website_input.add_theme_color_override("font_color", Color.WHITE)
	web_row.add_child(_edit_website_input)

	# Save button
	var save_btn := Button.new()
	save_btn.text = "Save Changes"
	save_btn.custom_minimum_size = Vector2(0, 28)
	save_btn.pressed.connect(_on_save_edit)
	_edit_container.add_child(save_btn)


func _on_save_edit() -> void:
	if _current_regiment.is_empty():
		return
	var new_desc := _edit_desc_input.text.strip_edges()
	var new_website := _edit_website_input.text.strip_edges()
	_regiment_client.update_details(
		str(_current_regiment.get("id", "")),
		new_desc,
		new_website
	)


func _on_leave_pressed() -> void:
	if SupabaseAuth.regiment_id == "":
		return
	_regiment_client.leave_regiment(SupabaseAuth.regiment_id)
	# Clear local state after leaving
	SupabaseAuth.regiment_id = ""
	SupabaseAuth.regiment_tag = ""
	_refresh_my_regiment()


func _on_back_pressed() -> void:
	var target := return_scene if not return_scene.is_empty() else MODE_SELECT_SCENE
	return_scene = ""
	get_tree().change_scene_to_file(target)


# ─────────────────────────────────────────────────────────────────────────
# Admin regiment management
# ─────────────────────────────────────────────────────────────────────────

var _admin_all_regiments: Array = []
var _admin_reg_names_http: HTTPRequest
var _admin_reg_fetch_pending := false

func _fetch_all_regiments_admin() -> void:
	_admin_reg_fetch_pending = true
	_regiment_client.list_all_regiments()


func _resolve_admin_regiment_names(regiments: Array) -> void:
	var co_ids: Array[String] = []
	for reg in regiments:
		var co_id: String = str(reg.get("co_id", ""))
		if co_id != "" and co_id != "null" and co_id not in co_ids:
			co_ids.append(co_id)

	if co_ids.is_empty():
		_populate_admin_regiments(regiments, {})
		return

	if _admin_reg_names_http != null:
		_admin_reg_names_http.queue_free()
	_admin_reg_names_http = HTTPRequest.new()
	add_child(_admin_reg_names_http)
	_admin_reg_names_http.request_completed.connect(_on_admin_reg_names_response)

	var id_filter := "(" + ",".join(co_ids) + ")"
	var url := "%s/rest/v1/player_profiles?id=in.%s&select=id,display_name" % [SupabaseAuth.SUPABASE_URL, id_filter]
	var hdrs := PackedStringArray([
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
	])
	_admin_reg_names_http.request(url, hdrs, HTTPClient.METHOD_GET)


func _on_admin_reg_names_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	var name_map: Dictionary = {}
	if response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
			for p in json.data:
				name_map[str(p.get("id", ""))] = str(p.get("display_name", "???"))
	_populate_admin_regiments(_admin_all_regiments, name_map)


func _populate_admin_regiments(regiments: Array, name_map: Dictionary) -> void:
	_clear_container(_admin_reg_container)

	if regiments.is_empty():
		var empty := Label.new()
		empty.text = "No regiments"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_admin_reg_container.add_child(empty)
		return

	for reg in regiments:
		var reg_name: String = reg.get("name", "???")
		var reg_tag: String = reg.get("tag", "?")
		var reg_id: String = str(reg.get("id", ""))
		var reg_status: String = reg.get("status", "?")
		var co_id: String = str(reg.get("co_id", ""))
		var co_name: String = name_map.get(co_id, "???")

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		# Header: [TAG] Name (status)
		var status_color := Color(0.4, 0.9, 0.4) if reg_status == "active" else (Color(0.9, 0.9, 0.4) if reg_status == "pending" else Color(0.6, 0.6, 0.6))
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		card.add_child(header)

		var name_label := Label.new()
		name_label.text = "[%s] %s" % [reg_tag, reg_name]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		header.add_child(name_label)

		var status_label := Label.new()
		status_label.text = reg_status.to_upper()
		status_label.custom_minimum_size = Vector2(70, 0)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.add_theme_font_size_override("font_size", 11)
		status_label.add_theme_color_override("font_color", status_color)
		header.add_child(status_label)

		# CO info
		var co_label := Label.new()
		co_label.text = "CO: %s" % co_name
		co_label.add_theme_font_size_override("font_size", 12)
		co_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		card.add_child(co_label)

		# Admin action buttons
		if reg_status == "active":
			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 6)
			card.add_child(btn_row)

			var disband_btn := Button.new()
			disband_btn.text = "Force Disband"
			disband_btn.custom_minimum_size = Vector2(100, 24)
			disband_btn.add_theme_font_size_override("font_size", 11)
			disband_btn.pressed.connect(_on_admin_force_disband.bind(reg_id))
			btn_row.add_child(disband_btn)

		var sep := HSeparator.new()
		card.add_child(sep)

		_admin_reg_container.add_child(card)


func _on_admin_force_disband(regiment_id: String) -> void:
	# Submit a disband application and auto-approve it
	_status_label.text = "Disbanding regiment..."
	# We need to use a direct update since admin can force it
	# For now, use the approve flow: create a disband application, then approve it
	# This is a two-step process; for simplicity let's add a direct admin RPC later
	# For now, just update the status directly via REST (admin RLS allows it)
	var body := JSON.stringify({
		"status": "disbanded",
		"disbanded_at": Time.get_datetime_string_from_system(true),
	})
	if _admin_reg_names_http != null:
		_admin_reg_names_http.queue_free()
	_admin_reg_names_http = HTTPRequest.new()
	add_child(_admin_reg_names_http)
	_admin_reg_names_http.request_completed.connect(_on_admin_disband_response)
	var url := "%s/rest/v1/regiments?id=eq.%s" % [SupabaseAuth.SUPABASE_URL, regiment_id]
	var hdrs := PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Authorization: Bearer %s" % SupabaseAuth.access_token,
		"Prefer: return=representation",
	])
	_admin_reg_names_http.request(url, hdrs, HTTPClient.METHOD_PATCH, body)


func _on_admin_disband_response(_result: int, response_code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code >= 200 and response_code < 300:
		_status_label.text = "Regiment disbanded."
		_fetch_all_regiments_admin()
		_refresh_browse()
	else:
		_status_label.text = "Failed to disband regiment (HTTP %d)" % response_code


# ─────────────────────────────────────────────────────────────────────────
# CO name resolution for browse tab
# ─────────────────────────────────────────────────────────────────────────

var _co_names_http: HTTPRequest

func _fetch_co_names(regiments: Array) -> void:
	var co_ids: Array[String] = []
	for reg in regiments:
		var co_id: String = str(reg.get("co_id", ""))
		if co_id != "" and co_id != "null" and co_id not in co_ids:
			co_ids.append(co_id)

	if co_ids.is_empty():
		return

	if _co_names_http != null:
		_co_names_http.queue_free()
	_co_names_http = HTTPRequest.new()
	add_child(_co_names_http)
	_co_names_http.request_completed.connect(_on_co_names_response.bind(regiments))

	var id_filter := "(" + ",".join(co_ids) + ")"
	var url := "%s/rest/v1/player_profiles?id=in.%s&select=id,display_name" % [SupabaseAuth.SUPABASE_URL, id_filter]
	var hdrs := PackedStringArray([
		"apikey: %s" % SupabaseAuth.SUPABASE_ANON_KEY,
		"Content-Type: application/json",
	])
	_co_names_http.request(url, hdrs, HTTPClient.METHOD_GET)


func _on_co_names_response(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray, regiments: Array) -> void:
	if response_code != 200:
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return

	var name_map: Dictionary = {}
	for profile in json.data:
		name_map[str(profile.get("id", ""))] = str(profile.get("display_name", "???"))

	# Re-populate the browse list with resolved CO names
	_clear_container(_regiment_list_container)
	for reg in regiments:
		var reg_name: String = reg.get("name", "???")
		var reg_tag: String = reg.get("tag", "?")
		var reg_id: String = reg.get("id", "")
		var co_id: String = str(reg.get("co_id", ""))
		var co_name: String = name_map.get(co_id, co_id.left(8) + "...")
		var row := _make_regiment_row(reg_name, reg_tag, co_name, "?", false, reg_id)
		_regiment_list_container.add_child(row)


# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _clear_container(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
