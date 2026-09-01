class_name SurvivalDifficultyDialog
extends AcceptDialog
## Survival Mode only: pick how fast German fireteams deploy.

signal difficulty_chosen(difficulty: int)

const SurvivalModeControllerClass := preload("res://scripts/core/survival_mode_controller.gd")

var _emitted: bool = false


func _ready() -> void:
	title = "Survival Difficulty"
	dialog_hide_on_ok = true
	transient = true
	exclusive = true
	unresizable = true
	CocUiTheme.apply_to(self)
	var ok := get_ok_button()
	if ok != null:
		ok.visible = false
		ok.disabled = true
	_build_layout()
	canceled.connect(_on_canceled)
	close_requested.connect(_on_canceled)


func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var prompt := Label.new()
	prompt.text = "How often should a new enemy fireteam deploy?"
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(320, 0)
	prompt.add_theme_font_size_override("font_size", 14)
	root.add_child(prompt)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	root.add_child(buttons)

	_add_choice_button(
		buttons,
		"Normal",
		"New enemy squad every 1 minute",
		SurvivalModeControllerClass.Difficulty.NORMAL,
	)
	_add_choice_button(
		buttons,
		"Hard",
		"New enemy squad every 30 seconds",
		SurvivalModeControllerClass.Difficulty.HARD,
	)
	_add_choice_button(
		buttons,
		"A-town",
		"New enemy squad every 15 seconds",
		SurvivalModeControllerClass.Difficulty.A_TOWN,
	)


func _add_choice_button(host: VBoxContainer, title: String, subtitle: String, diff: int) -> void:
	var btn := Button.new()
	btn.text = "%s  —  %s" % [title, subtitle]
	btn.custom_minimum_size = Vector2(340, 28)
	btn.pressed.connect(func() -> void: _choose(diff))
	host.add_child(btn)


func _choose(diff: int) -> void:
	if _emitted:
		return
	_emitted = true
	difficulty_chosen.emit(diff)
	hide()


func _on_canceled() -> void:
	## Escape / window close still starts the match — default to Normal.
	_choose(SurvivalModeControllerClass.Difficulty.NORMAL)
