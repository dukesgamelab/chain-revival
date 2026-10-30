class_name TutorialCompleteDialog
extends AcceptDialog

signal finished


func _ready() -> void:
	title = "Tutorial Complete"
	exclusive = true
	transient = true
	unresizable = true
	ok_button_text = "Return to Menu"
	min_size = Vector2(460, 0)
	CocUiTheme.apply_to(self)

	var label := Label.new()
	label.text = (
		"Congratulations, Commander!\n\n"
		+ "You have learned the basics:\n\n"
		+ "  - Moving soldiers (Run and Crawl)\n"
		+ "  - Changing stance (Prone / Standing)\n"
		+ "  - Facing a direction\n"
		+ "  - Fire control (Fire At Will / Hold Fire)\n"
		+ "  - Manual targeting (Fire At)\n"
		+ "  - Throwing grenades\n\n"
		+ "You are ready for battle!\n"
		+ "Try Single Player or Survival Mode next."
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	label.add_theme_color_override("font_color", Color.WHITE)
	add_child(label)

	confirmed.connect(_on_confirmed)
	canceled.connect(_on_confirmed)


func _on_confirmed() -> void:
	finished.emit()
	queue_free()
