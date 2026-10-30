class_name TutorialWelcomeDialog
extends AcceptDialog

signal tutorial_started


func _ready() -> void:
	title = "Tutorial: Basic Training"
	exclusive = true
	transient = true
	unresizable = true
	ok_button_text = "Begin"
	min_size = Vector2(460, 0)
	CocUiTheme.apply_to(self)

	var label := Label.new()
	label.text = (
		"Welcome, Commander!\n\n"
		+ "This tutorial will teach you the basics of commanding your fireteam.\n\n"
		+ "You will learn:\n"
		+ "  - Moving soldiers (Run and Crawl)\n"
		+ "  - Changing stance (Prone / Standing)\n"
		+ "  - Facing a direction\n"
		+ "  - Fire control (Fire At Will / Hold Fire)\n"
		+ "  - Manual targeting (Fire At)\n"
		+ "  - Throwing grenades\n\n"
		+ "Click 'Begin' to start."
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	label.add_theme_color_override("font_color", Color.WHITE)
	add_child(label)

	confirmed.connect(_on_confirmed)
	canceled.connect(_on_confirmed)


func _on_confirmed() -> void:
	tutorial_started.emit()
	queue_free()
