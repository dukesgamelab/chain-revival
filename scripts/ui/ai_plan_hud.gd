class_name AiPlanHud
extends PanelContainer
## Temporary top-right debug readout for AI Commanders (plan / state / objective / order).

const GameStateClass := preload("res://scripts/core/game_state.gd")
const AiPlanClass := preload("res://scripts/ai/ai_plan.gd")
const AiCommanderFrameworkClass := preload("res://scripts/ai/ai_commander_framework.gd")

var _label: Label
var _game_state: GameStateClass = null
var _framework: AiCommanderFrameworkClass = null


func _ready() -> void:
	if BuildConfig.is_survival_playtest():
		visible = false
		return
	CocUiTheme.apply_to(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _label == null:
		_ensure_label()
	_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.2))
	_label.add_theme_font_size_override("font_size", 11)
	refresh()


func bind_game_state(game_state: GameStateClass) -> void:
	_game_state = game_state
	refresh()


func bind_framework(framework: AiCommanderFrameworkClass, game_state: GameStateClass) -> void:
	_framework = framework
	_game_state = game_state
	refresh()


func refresh() -> void:
	if BuildConfig.is_survival_playtest():
		visible = false
		return
	_ensure_label()
	if _framework != null and _framework.has_commanders():
		var lines := _framework.debug_lines(_game_state)
		if lines.size() <= 1:
			visible = false
			_label.text = ""
			return
		_label.text = "\n".join(lines)
		visible = true
		return

	## Fallback: Phase 3 plan-only display before framework spins up.
	if _game_state == null or _game_state.command_hierarchy == null:
		visible = false
		_label.text = ""
		return
	var lines2: PackedStringArray = []
	lines2.append("[DEBUG] AI Plans")
	var hierarchy := _game_state.command_hierarchy
	for pid in hierarchy.all_player_ids():
		if not hierarchy.is_ai_player(pid):
			continue
		var selected := _game_state.get_selected_ai_plan(pid)
		var active := _game_state.get_active_ai_plan(pid)
		if active.is_empty() and selected.is_empty():
			continue
		var team_name := Team.display_name(hierarchy.get_team_id(pid))
		var player_name := hierarchy.get_display_name(pid)
		if player_name.is_empty():
			player_name = "Player %d" % pid
		var plan_text := AiPlanClass.format_runtime_label(selected, active)
		lines2.append("%s %s — %s" % [team_name, player_name, plan_text])
	if lines2.size() <= 1:
		visible = false
		_label.text = ""
		return
	_label.text = "\n".join(lines2)
	visible = true


func _ensure_label() -> void:
	if _label != null:
		return
	var margin := MarginContainer.new()
	margin.name = "AiPlanMargin"
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)
	_label = Label.new()
	_label.name = "AiPlanLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_label)
