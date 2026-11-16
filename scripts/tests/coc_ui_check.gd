extends Node


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/ui/command_bar.tscn")
	var bar: Control = packed.instantiate()
	add_child(bar)
	await get_tree().process_frame
	await get_tree().process_frame
	var host := bar.get_node("BottomHost") as Control
	var fire := bar.get_node("BottomHost/LeftPanel/LeftMargin/LeftVBox/SoldierRows/Row1/FireAtButton") as Button
	var grenade := bar.get_node("BottomHost/LeftPanel/LeftMargin/LeftVBox/SoldierRows/Row1/GrenadeButton") as Button
	var weapon := bar.get_node("BottomHost/LeftPanel/LeftMargin/LeftVBox/SoldierRows/Row1/WeaponAmmoPanel/WeaponAmmoRow/WeaponLabel") as Label
	var view := bar.get_viewport_rect().size
	var host_top := view.y + host.offset_top
	print("theme_ok=", bar.theme != null)
	print("button=", fire.custom_minimum_size, " font=", fire.get_theme_font_size("font_size"))
	print("grenade=", grenade.custom_minimum_size, " inset=", grenade.get_theme_stylebox("normal").content_margin_left)
	print("label_font=", weapon.get_theme_font_size("font_size"))
	print("host_top=", host_top, " host_min=", host.get_combined_minimum_size(), " view=", view)
	var ok := true
	if fire.custom_minimum_size.y < 30.0:
		print("FAIL button height")
		ok = false
	if fire.get_theme_font_size("font_size") < 14:
		print("FAIL button font")
		ok = false
	if weapon.get_theme_font_size("font_size") < 14:
		print("FAIL label font")
		ok = false
	if grenade.custom_minimum_size.y < 30.0:
		print("FAIL grenade height")
		ok = false
	if grenade.get_theme_stylebox("normal").content_margin_left < 34.0:
		print("FAIL grenade icon inset")
		ok = false
	if host.get_combined_minimum_size().x > view.x + 1.0:
		print("FAIL toolbar wider than the viewport")
		ok = false
	if host_top < 200.0:
		print("FAIL toolbar overlaps the top status area")
		ok = false
	if host.offset_top >= -160.0:
		print("FAIL toolbar did not grow")
		ok = false
	if fire.text != "Fire at" or grenade.tooltip_text.is_empty():
		print("FAIL command or tooltip missing")
		ok = false
	for node in _buttons_under(host):
		var button := node as Button
		if button.text.is_empty() or not button.visible:
			continue
		var font := button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var style := button.get_theme_stylebox("normal")
		var inner := button.custom_minimum_size.x - style.content_margin_left - style.content_margin_right
		if text_width > inner + 1.0:
			print("TIGHT ", button.name, " text=", text_width, " inner=", inner, " label=", button.text)
			ok = false
	var stage := bar.get_node("BottomHost/LeftPanel/LeftMargin/LeftVBox/TopBar/DeploymentStageLabel") as Label
	var stage_font := stage.get_theme_font("font")
	var stage_size := stage.get_theme_font_size("font_size")
	var stage_width := stage_font.get_string_size("Scenario Running", HORIZONTAL_ALIGNMENT_LEFT, -1, stage_size).x
	if stage_width > stage.custom_minimum_size.x + 1.0:
		print("TIGHT deployment label ", stage_width, " min=", stage.custom_minimum_size.x)
		ok = false
	print("PASS coc_ui_check" if ok else "FAIL coc_ui_check")
	get_tree().quit(0 if ok else 1)


func _buttons_under(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	if node is Button:
		found.append(node)
	for child in node.get_children():
		found.append_array(_buttons_under(child))
	return found
