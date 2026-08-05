class_name CocUiTheme
extends RefCounted
## Close Combat / Windows 95-era theme for the bottom command toolbar.
## Button textures are built once and shared — never regenerate per control/frame.

const PANEL_FACE := Color("8A8680")
const PANEL_FACE_DARK := Color("6E6A64")
const BUTTON_FACE := Color("C0C0C0")
const BUTTON_FACE_HOVER := Color("CACACA")
const BUTTON_FACE_PRESSED := Color("808080")
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
## OG toolbar rows are short — one text line with minimal padding.
const FONT_SIZE := 10
const ROW_HEIGHT := 18
const BUTTON_HEIGHT := 18
const BUTTON_WIDTH_DEFAULT := 60
const GRENADE_BUTTON_SIZE := Vector2(60, 18)
const PANEL_MARGIN := 2
const BUTTON_GAP := 1

static var _cached_theme: Theme
static var _font: Font
static var _blank_tex_normal: Texture2D
static var _blank_tex_pressed: Texture2D
static var _blank_tex_disabled: Texture2D
static var _grenade_tex_normal: Texture2D
static var _grenade_tex_pressed: Texture2D
static var _grenade_tex_disabled: Texture2D
static var _blank_styles: Dictionary = {} ## key -> StyleBoxTexture
static var _grenade_styles: Dictionary = {}
static var _panel_style_cached: StyleBoxTexture
static var _inset_style_cached: StyleBoxTexture
static var _chat_panel_cached: StyleBoxFlat
static var _chat_input_cached: StyleBoxFlat
static var _textures_ready: bool = false


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
	_ensure_textures()
	var theme := Theme.new()
	var font := get_font()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "Panel", panel_style())

	theme.set_stylebox("normal", "Button", blank_button_style(false, false, false))
	theme.set_stylebox("hover", "Button", blank_button_style(false, true, false))
	theme.set_stylebox("pressed", "Button", blank_button_style(true, false, false))
	theme.set_stylebox("hover_pressed", "Button", blank_button_style(true, true, false))
	theme.set_stylebox("disabled", "Button", blank_button_style(false, false, true))
	theme.set_stylebox("focus", "Button", blank_button_style(false, false, false))

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

	theme.set_stylebox("normal", "LineEdit", chat_input_style())
	theme.set_stylebox("focus", "LineEdit", chat_input_style())
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


## Shared grenade chrome — same StyleBox instances for every row.
static func style_grenade_button(button: Button) -> void:
	if button == null:
		return
	_ensure_textures()
	button.custom_minimum_size = GRENADE_BUTTON_SIZE
	button.add_theme_stylebox_override("normal", grenade_button_style(false, false, false))
	button.add_theme_stylebox_override("hover", grenade_button_style(false, true, false))
	button.add_theme_stylebox_override("pressed", grenade_button_style(true, false, false))
	button.add_theme_stylebox_override("hover_pressed", grenade_button_style(true, true, false))
	button.add_theme_stylebox_override("disabled", grenade_button_style(false, false, true))
	button.add_theme_stylebox_override("focus", grenade_button_style(false, false, false))
	button.add_theme_color_override("font_color", TEXT_WHITE)
	button.add_theme_color_override("font_hover_color", TEXT_WHITE)
	button.add_theme_color_override("font_pressed_color", TEXT_WHITE)
	button.add_theme_color_override("font_hover_pressed_color", TEXT_WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.75, 0.75, 0.75, 1.0))
	button.add_theme_color_override("font_focus_color", TEXT_WHITE)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.clip_text = true


static func chat_panel_style() -> StyleBoxFlat:
	if _chat_panel_cached != null:
		return _chat_panel_cached
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHAT_BG
	sb.border_color = Color("202020")
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_top = 3
	sb.content_margin_right = 4
	sb.content_margin_bottom = 3
	_chat_panel_cached = sb
	return sb


static func chat_input_style() -> StyleBoxFlat:
	if _chat_input_cached != null:
		return _chat_input_cached
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHAT_BG
	sb.border_color = Color("404040")
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_top = 2
	sb.content_margin_right = 4
	sb.content_margin_bottom = 2
	_chat_input_cached = sb
	return sb


static func inset_label_panel() -> StyleBoxTexture:
	if _inset_style_cached != null:
		return _inset_style_cached
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("9A968C"))
	_paint_bevel(img, false)
	_inset_style_cached = _style_from_texture(ImageTexture.create_from_image(img), 2, 2, 1)
	return _inset_style_cached


static func panel_style() -> StyleBoxTexture:
	if _panel_style_cached != null:
		return _panel_style_cached
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var face := PANEL_FACE.lerp(PANEL_FACE_DARK, t * 0.4)
		for x in w:
			var n := 0.97 + 0.06 * float((x * 17 + y * 31) % 5) / 4.0
			img.set_pixel(x, y, Color(face.r * n, face.g * n, face.b * n, 1.0))
	_paint_bevel(img, true)
	_panel_style_cached = _style_from_texture(ImageTexture.create_from_image(img), 3, 4, 2)
	return _panel_style_cached


static func blank_button_style(pressed: bool, hover: bool, disabled: bool = false) -> StyleBoxTexture:
	_ensure_textures()
	## Hover uses the same chrome as normal — no extra texture work.
	if hover and not pressed and not disabled:
		return blank_button_style(false, false, false)
	var key := _style_key(pressed, false, disabled)
	if _blank_styles.has(key):
		return _blank_styles[key] as StyleBoxTexture
	var tex := _blank_tex_normal
	if disabled:
		tex = _blank_tex_disabled
	elif pressed:
		tex = _blank_tex_pressed
	var content_l := 4 if pressed else 3
	var content_t := 1
	var sb := _style_from_texture(tex, 2, content_l, content_t)
	_blank_styles[key] = sb
	return sb


static func grenade_button_style(pressed: bool, hover: bool, disabled: bool = false) -> StyleBoxTexture:
	_ensure_textures()
	if hover and not pressed and not disabled:
		return grenade_button_style(false, false, false)
	var key := _style_key(pressed, false, disabled)
	if _grenade_styles.has(key):
		return _grenade_styles[key] as StyleBoxTexture
	var tex := _grenade_tex_normal
	if disabled:
		tex = _grenade_tex_disabled
	elif pressed:
		tex = _grenade_tex_pressed
	var content_l := 27 if pressed else 26
	var content_r := 4 if pressed else 5
	var content_t := 1
	var sb := _style_from_texture(tex, 2, content_l, content_t)
	sb.content_margin_right = content_r
	_grenade_styles[key] = sb
	return sb


static func _style_key(pressed: bool, hover: bool, disabled: bool) -> String:
	return "%d%d%d" % [int(pressed), int(hover), int(disabled)]


static func _ensure_textures() -> void:
	if _textures_ready:
		return
	_blank_tex_normal = _load_texture(BLANK_BUTTON_PATH, true)
	_blank_tex_pressed = _make_pressed_texture(_blank_tex_normal)
	_blank_tex_disabled = _make_modulated_texture(_blank_tex_normal, Color(0.85, 0.85, 0.85, 1.0))
	_grenade_tex_normal = _load_texture(GRENADE_BUTTON_PATH, true)
	_grenade_tex_pressed = _make_pressed_texture(_grenade_tex_normal)
	_grenade_tex_disabled = _make_modulated_texture(_grenade_tex_normal, Color(0.85, 0.85, 0.85, 1.0))
	_textures_ready = true


static func _load_texture(path: String, procedural_fallback: bool) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	if not procedural_fallback:
		return ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	var fallback := Image.create(60, 26, false, Image.FORMAT_RGBA8)
	fallback.fill(BUTTON_FACE)
	_paint_bevel(fallback, true)
	return ImageTexture.create_from_image(fallback)


static func _image_from_texture(tex: Texture2D) -> Image:
	if tex == null:
		return Image.create(60, 26, false, Image.FORMAT_RGBA8)
	var img := tex.get_image()
	if img != null:
		## Decompress / convert so CPU pixel edits work on imported textures.
		if img.is_compressed():
			img.decompress()
		return img
	## Last resort: blank face matching typical button size.
	var fallback := Image.create(60, 26, false, Image.FORMAT_RGBA8)
	fallback.fill(BUTTON_FACE)
	_paint_bevel(fallback, true)
	return fallback


static func _make_pressed_texture(src: Texture2D) -> Texture2D:
	var img := _image_from_texture(src)
	## OG Hold Fire / Fire at Will: pressed is clearly darker + sunken bevel.
	img.adjust_bcs(0.70, 1.0, 1.0)
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		img.set_pixel(x, 0, img.get_pixel(x, 0).darkened(0.55))
		if h > 2:
			img.set_pixel(x, 1, img.get_pixel(x, 1).darkened(0.28))
		img.set_pixel(x, h - 1, img.get_pixel(x, h - 1).lightened(0.40))
		if h > 3:
			img.set_pixel(x, h - 2, img.get_pixel(x, h - 2).lightened(0.18))
	for y in h:
		img.set_pixel(0, y, img.get_pixel(0, y).darkened(0.55))
		if w > 2:
			img.set_pixel(1, y, img.get_pixel(1, y).darkened(0.28))
		img.set_pixel(w - 1, y, img.get_pixel(w - 1, y).lightened(0.40))
		if w > 3:
			img.set_pixel(w - 2, y, img.get_pixel(w - 2, y).lightened(0.18))
	return ImageTexture.create_from_image(img)


static func _make_modulated_texture(src: Texture2D, _mul: Color) -> Texture2D:
	var img := _image_from_texture(src)
	## Once at startup — dim for disabled without per-frame work.
	img.adjust_bcs(0.85, 1.0, 1.0)
	return ImageTexture.create_from_image(img)


static func _style_from_texture(
	tex: Texture2D,
	margin: int,
	content_h: int,
	content_v: int,
) -> StyleBoxTexture:
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
	## STRETCH is far cheaper than TILE_FIT for dozens of toolbar buttons.
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb


static func _paint_bevel(img: Image, raised: bool) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var hi := BEVEL_LIGHT if raised else BEVEL_DARK
	var lo := BEVEL_DARK if raised else BEVEL_LIGHT
	for x in w:
		img.set_pixel(x, 0, hi)
		img.set_pixel(x, h - 1, lo)
	for y in h:
		img.set_pixel(0, y, hi)
		img.set_pixel(w - 1, y, lo)
	img.set_pixel(0, 0, hi)
	img.set_pixel(w - 1, h - 1, lo)
	img.set_pixel(w - 1, 0, lo if raised else hi)
	img.set_pixel(0, h - 1, lo if raised else hi)
