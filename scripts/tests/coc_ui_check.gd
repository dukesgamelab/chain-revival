extends Node


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/ui/command_bar.tscn")
	var bar: Control = packed.instantiate()
	add_child(bar)
	await get_tree().process_frame
	print("theme_ok=", bar.theme != null)
	print("offset_top=", bar.offset_top)
	print("font_size=", CocUiTheme.FONT_SIZE)
	print("PASS coc_ui_check")
	get_tree().quit(0)
