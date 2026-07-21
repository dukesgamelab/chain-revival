class_name CocUiTheme
extends RefCounted
## Close Combat / Windows 95-era theme for the bottom command toolbar.
## Presentation only — does not change command behavior.

const PANEL_FACE := Color("7A7A7A")
const PANEL_FACE_DARK := Color("6E6E6E")
const BUTTON_FACE := Color("C0C0C0")
const BUTTON_FACE_HOVER := Color("CACACA")
const BUTTON_FACE_PRESSED := Color("A8A8A8")
const BUTTON_FACE_DISABLED := Color("9A9A9A")
const BEVEL_LIGHT := Color("F0F0F0")
const BEVEL_DARK := Color("404040")
const TEXT_BLACK := Color("000000")
const TEXT_DISABLED := Color("606060")
const TEXT_MUTED := Color("1A1A1A")
const SELECTED_TINT := Color(0.92, 0.92, 0.85, 1.0) ## Subtle selected command highlight
const FONT_PATH := "res://assets/ui/fonts/tahoma.ttf"
const FONT_FALLBACK_PATH := "res://assets/ui/fonts/microsoft_sans_serif.ttf"
const FONT_SIZE := 11 ## ~8–9pt at 96 DPI in Godot terms
const ROW_HEIGHT := 20
const BUTTON_HEIGHT := 18
const PANEL_MARGIN := 4
const BUTTON_GAP := 2

static var _cached_theme: Theme
static var _font: Font


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
	var theme := Theme.new()
	var font := get_font()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("panel", "PanelContainer", _panel_style())
	theme.set_stylebox("panel", "Panel", _panel_style())

	theme.set_stylebox("normal", "Button", _button_style(false, false, false))
	theme.set_stylebox("hover", "Button", _button_style(false, true, false))
	theme.set_stylebox("pressed", "Button", _button_style(true, false, false))
	theme.set_stylebox("hover_pressed", "Button", _button_style(true, true, false))
	theme.set_stylebox("disabled", "Button", _button_style(false, false, true))
	theme.set_stylebox("focus", "Button", _button_style(false, false, false))

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

	theme.set_constant("separation", "HBoxContainer", BUTTON_GAP)
	theme.set_constant("separation", "VBoxContainer", BUTTON_GAP)
	theme.set_constant("margin_left", "MarginContainer", PANEL_MARGIN)
	theme.set_constant("margin_top", "MarginContainer", PANEL_MARGIN)
	theme.set_constant("margin_right", "MarginContainer", PANEL_MARGIN)
	theme.set_constant("margin_bottom", "MarginContainer", PANEL_MARGIN)

	return theme


static func apply_to(control: Control) -> void:
	if control == null:
		return
	control.theme = get_theme()


static func selected_modulate(is_selected: bool) -> Color:
	return SELECTED_TINT if is_selected else Color.WHITE


static func _panel_style() -> StyleBoxTexture:
	## Opaque medium-gray face with a light vertical gradient and raised outer bevel.
	var w := 32
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var face := PANEL_FACE.lerp(PANEL_FACE_DARK, t * 0.35)
		for x in w:
			img.set_pixel(x, y, face)
	_paint_bevel(img, true)
	return _style_from_image(img, 3, 3, 4, 2)


static func _button_style(pressed: bool, hover: bool, disabled: bool) -> StyleBoxTexture:
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


static func _paint_bevel(img: Image, raised: bool) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var hi := BEVEL_LIGHT if raised else BEVEL_DARK
	var lo := BEVEL_DARK if raised else BEVEL_LIGHT
	## Outer bevel (2px).
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
	## Corner fixes so top-left stays light / bottom-right stays dark when raised.
	img.set_pixel(0, 0, hi)
	img.set_pixel(w - 1, h - 1, lo)
	img.set_pixel(w - 1, 0, lo if raised else hi)
	img.set_pixel(0, h - 1, lo if raised else hi)


static func _style_from_image(
	img: Image,
	margin: int,
	expand: int,
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
	sb.expand_margin_left = 0
	sb.expand_margin_top = 0
	sb.expand_margin_right = 0
	sb.expand_margin_bottom = 0
	sb.content_margin_left = content_h
	sb.content_margin_top = content_v
	sb.content_margin_right = content_h
	sb.content_margin_bottom = content_v
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


static func inset_label_panel() -> StyleBoxTexture:
	## Slightly inset wells for weapon/ammo/status columns.
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("8A8A8A"))
	_paint_bevel(img, false)
	return _style_from_image(img, 2, 0, 2, 1)
