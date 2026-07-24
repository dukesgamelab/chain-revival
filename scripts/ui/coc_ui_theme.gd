class_name CocUiTheme
extends RefCounted
## Close Combat / Windows 95-era theme for the bottom command toolbar.
## Uses recovered blank/grenade button textures when available.

const PANEL_FACE := Color("8A8680")
const PANEL_FACE_DARK := Color("6E6A64")
const BUTTON_FACE := Color("C0C0C0")
const BUTTON_FACE_HOVER := Color("CACACA")
const BUTTON_FACE_PRESSED := Color("A8A8A8")
const BUTTON_FACE_DISABLED := Color("9A9A9A")
const BEVEL_LIGHT := Color("F0F0F0")
const BEVEL_DARK := Color("404040")
const TEXT_BLACK := Color("000000")
const TEXT_WHITE := Color("FFFFFF")
const TEXT_DISABLED := Color("606060")
const TEXT_MUTED := Color("1A1A1A")
const TEXT_STATUS_RED := Color("C00000")
const TEXT_CHAT_SYSTEM := Color("CC0000")
const CHAT_BG := Color("FFFFFF")
const SELECTED_TINT := Color(0.92, 0.92, 0.85, 1.0)
const FONT_PATH := "res://assets/ui/fonts/tahoma.ttf"
const FONT_FALLBACK_PATH := "res://assets/ui/fonts/microsoft_sans_serif.ttf"
const BLANK_BUTTON_PATH := "res://assets/ui/toolbar/blank_button.png"
const GRENADE_BUTTON_PATH := "res://assets/ui/toolbar/grenade_button.png"
const FONT_SIZE := 11
const ROW_HEIGHT := 26
const BUTTON_HEIGHT := 26
const BUTTON_WIDTH_DEFAULT := 60
const GRENADE_BUTTON_SIZE := Vector2(60, 26)
const PANEL_MARGIN := 3
const BUTTON_GAP := 2

static var _cached_theme: Theme
static var _font: Font
static var _blank_img: Image
static var _grenade_img: Image


static func get_theme() -> Theme:
	if _cached_theme == null:
		_cached_theme = build_theme()
	return _cached_theme


static func get_font() -> Font:
	if _font != null:
		return _font
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font
	elif ResourceLoader.exists(FONT_FALLBACK_PATH):
		_font = load(FONT_FALLBACK_PATH) as Font
	else:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Tahoma", "Microsoft Sans Serif", "MS Sans Serif", "Verdana"])
		_font = sys
	return _font


static func build_theme() -> Theme:
	_ensure_button_images()
	var theme := Theme.new()
	var font := get_font()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", _panel_style())
	theme.set_stylebox("panel", "Panel", _panel_style())

	theme.set_stylebox("normal", "Button", _blank_button_style(false, false, false))
	theme.set_stylebox("hover", "Button", _blank_button_style(false, true, false))
	theme.set_stylebox("pressed", "Button", _blank_button_style(true, false, false))
	theme.set_stylebox("hover_pressed", "Button", _blank_button_style(true, true, false))
	theme.set_stylebox("disabled", "Button", _blank_button_style(false, false, true))
	theme.set_stylebox("focus", "Button", _blank_button_style(false, false, false))

	theme.set_color("font_color", "Button", TEXT_BLACK)
	theme.set_color("font_hover_color", "Button", TEXT_BLACK)
	theme.set_color("font_pressed_color", "Button", TEXT_BLACK)
	theme.set_color("font_hover_pressed_color", "Button", TEXT_BLACK)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	theme.set_color("font_focus_color", "Button", TEXT_BLACK)
	theme.set_font("font", "Button", font)
	theme.set_font_size("font_size", "Button", FONT_SIZE)
	theme.set_constant("h_separation", "Button", 2)

	theme.set_color("font_color", "Label", TEXT_BLACK)
	theme.set_font("font", "Label", font)
	theme.set_font_size("font_size", "Label", FONT_SIZE)

	theme.set_stylebox("normal", "LineEdit", _chat_input_style())
	theme.set_stylebox("focus", "LineEdit", _chat_input_style())
	theme.set_color("font_color", "LineEdit", TEXT_BLACK)
	theme.set_font("font", "LineEdit", font)
	theme.set_font_size("font_size", "LineEdit", FONT_SIZE)

	theme.set_constant("separation", "HBoxContainer", BUTTON_GAP)
	theme.set_constant("separation", "VBoxContainer", BUTTON_GAP)
	theme.set_constant("margin_left", "MarginContainer", PANEL_MARGIN)
	theme.set_constant("margin_top", "MarginContainer", PANEL_MARGIN)
	theme.set_constant("margin_right", "MarginContainer", PANEL_MARGIN)
	theme.set_constant("margin_bottom", "MarginContainer", PANEL_MARGIN)

	return theme


static func apply_to(node: Node) -> void:
	if node == null:
		return
	if node is Control:
		(node as Control).theme = get_theme()
	elif node is Window:
		(node as Window).theme = get_theme()


static func selected_modulate(is_selected: bool) -> Color:
	return SELECTED_TINT if is_selected else Color.WHITE


## Apply recovered grenade-button chrome + white count text.
static func style_grenade_button(button: Button) -> void:
	if button == null:
		return
	_ensure_button_images()
	button.custom_minimum_size = GRENADE_BUTTON_SIZE
	button.add_theme_stylebox_override("normal", _grenade_button_style(false, false))
	button.add_theme_stylebox_override("hover", _grenade_button_style(false, true))
	button.add_theme_stylebox_override("pressed", _grenade_button_style(true, false))
	button.add_theme_stylebox_override("hover_pressed", _grenade_button_style(true, true))
	button.add_theme_stylebox_override("disabled", _grenade_button_style(false, false, true))
	button.add_theme_stylebox_override("focus", _grenade_button_style(false, false))
	button.add_theme_color_override("font_color", TEXT_WHITE)
	button.add_theme_color_override("font_hover_color", TEXT_WHITE)
	button.add_theme_color_override("font_pressed_color", TEXT_WHITE)
	button.add_theme_color_override("font_hover_pressed_color", TEXT_WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.75, 0.75, 0.75, 1.0))
	button.add_theme_color_override("font_focus_color", TEXT_WHITE)
	button.add_theme_font_size_override("font_size", 12)
	button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.clip_text = true


static func chat_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHAT_BG
	sb.border_color = Color("202020")
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_top = 3
	sb.content_margin_right = 4
	sb.content_margin_bottom = 3
	return sb


static func inset_label_panel() -> StyleBoxTexture:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("9A968C"))
	_paint_bevel(img, false)
	return _style_from_image(img, 2, 0, 2, 1)


static func _ensure_button_images() -> void:
	if _blank_img == null:
		_blank_img = _load_image(BLANK_BUTTON_PATH)
	if _grenade_img == null:
		_grenade_img = _load_image(GRENADE_BUTTON_PATH)


static func _load_image(path: String) -> Image:
	## Prefer raw PNG load so we can mutate pixels for pressed/hover variants.
	if FileAccess.file_exists(path):
		var from_file := Image.new()
		if from_file.load(path) == OK:
			return from_file
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			var img := tex.get_image()
			if img != null:
				return img
	## Fallback procedural face if asset missing.
	var fallback := Image.create(60, 26, false, Image.FORMAT_RGBA8)
	fallback.fill(BUTTON_FACE)
	_paint_bevel(fallback, true)
	return fallback


static func _blank_button_style(pressed: bool, hover: bool, disabled: bool = false) -> StyleBoxTexture:
	if _blank_img == null:
		return _procedural_button_style(pressed, hover, disabled)
	var img := _blank_img.duplicate() as Image
	if pressed:
		img = _make_pressed_variant(img)
	elif hover:
		img = _tint_image(img, Color(1.05, 1.05, 1.02, 1.0))
	if disabled:
		img = _tint_image(img, Color(0.85, 0.85, 0.85, 1.0))
	## Content margin: leave room for text inside the bevel (icon-free blank face).
	var content_l := 4 if not pressed else 5
	var content_t := 2 if not pressed else 3
	return _style_from_image(img, 3, 0, content_l, content_t)


static func _grenade_button_style(pressed: bool, hover: bool, disabled: bool = false) -> StyleBoxTexture:
	if _grenade_img == null:
		return _blank_button_style(pressed, hover, disabled)
	var img := _grenade_img.duplicate() as Image
	if pressed:
		img = _make_pressed_variant(img)
	elif hover:
		img = _tint_image(img, Color(1.05, 1.05, 1.02, 1.0))
	if disabled:
		img = _tint_image(img, Color(0.85, 0.85, 0.85, 1.0))
	## Leave the left ~half for the baked grenade icon; count sits on the right.
	var content_l := 28 if not pressed else 29
	var content_r := 6 if not pressed else 5
	var content_t := 2 if not pressed else 3
	var sb := _style_from_image(img, 3, 0, content_l, content_t)
	sb.content_margin_right = content_r
	return sb


static func _make_pressed_variant(src: Image) -> Image:
	## Invert bevel + darken face slightly for a sunken click.
	var img := src.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			c = c.darkened(0.08)
			img.set_pixel(x, y, c)
	## Swap outer bevel rows/cols.
	for x in w:
		var top := img.get_pixel(x, 0)
		var bot := img.get_pixel(x, h - 1)
		img.set_pixel(x, 0, bot.darkened(0.15))
		img.set_pixel(x, h - 1, top.lightened(0.1))
	for y in h:
		var left := img.get_pixel(0, y)
		var right := img.get_pixel(w - 1, y)
		img.set_pixel(0, y, right.darkened(0.15))
		img.set_pixel(w - 1, y, left.lightened(0.1))
	return img


static func _tint_image(src: Image, mul: Color) -> Image:
	var img := src.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * mul.r, c.g * mul.g, c.b * mul.b, c.a * mul.a))
	return img


static func _panel_style() -> StyleBoxTexture:
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var face := PANEL_FACE.lerp(PANEL_FACE_DARK, t * 0.4)
		for x in w:
			## Subtle grain so the bar reads less flat.
			var n := 0.97 + 0.06 * float((x * 17 + y * 31) % 5) / 4.0
			img.set_pixel(x, y, Color(face.r * n, face.g * n, face.b * n, 1.0))
	_paint_bevel(img, true)
	return _style_from_image(img, 3, 3, 4, 2)


static func _procedural_button_style(pressed: bool, hover: bool, disabled: bool) -> StyleBoxTexture:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var face := BUTTON_FACE
	if disabled:
		face = BUTTON_FACE_DISABLED
	elif pressed:
		face = BUTTON_FACE_PRESSED
	elif hover:
		face = BUTTON_FACE_HOVER
	img.fill(face)
	_paint_bevel(img, not pressed)
	var content := 1 if pressed else 2
	return _style_from_image(img, 2, 2, content, content)


static func _chat_input_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHAT_BG
	sb.border_color = Color("404040")
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_top = 2
	sb.content_margin_right = 4
	sb.content_margin_bottom = 2
	return sb


static func _paint_bevel(img: Image, raised: bool) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var hi := BEVEL_LIGHT if raised else BEVEL_DARK
	var lo := BEVEL_DARK if raised else BEVEL_LIGHT
	for x in w:
		img.set_pixel(x, 0, hi)
		img.set_pixel(x, h - 1, lo)
		if h > 2:
			img.set_pixel(x, 1, hi.lerp(img.get_pixel(x, 1), 0.35) if raised else lo.lerp(img.get_pixel(x, 1), 0.35))
			img.set_pixel(x, h - 2, lo.lerp(img.get_pixel(x, h - 2), 0.35) if raised else hi.lerp(img.get_pixel(x, h - 2), 0.35))
	for y in h:
		img.set_pixel(0, y, hi)
		img.set_pixel(w - 1, y, lo)
		if w > 2:
			img.set_pixel(1, y, hi.lerp(img.get_pixel(1, y), 0.35) if raised else lo.lerp(img.get_pixel(1, y), 0.35))
			img.set_pixel(w - 2, y, lo.lerp(img.get_pixel(w - 2, y), 0.35) if raised else hi.lerp(img.get_pixel(w - 2, y), 0.35))
	img.set_pixel(0, 0, hi)
	img.set_pixel(w - 1, h - 1, lo)
	img.set_pixel(w - 1, 0, lo if raised else hi)
	img.set_pixel(0, h - 1, lo if raised else hi)


static func _style_from_image(
	img: Image,
	margin: int,
	_expand: int,
	content_h: int,
	content_v: int,
) -> StyleBoxTexture:
	var tex := ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content_h
	sb.content_margin_top = content_v
	sb.content_margin_right = content_h
	sb.content_margin_bottom = content_v
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb
