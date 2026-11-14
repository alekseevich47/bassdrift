class_name UiPalette
extends Object

const BG := Color("#07060d")
const INK := Color("#f4f1ea")
const MUTED := Color("#b7a9b8")
const MAGENTA := Color("#ff2d8a")
const CYAN := Color("#3de1ff")
const AMBER := Color("#ffc857")
const PIT := Color("#1a1020")


static func button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(12)
	return box


static func style_button(button: Button, fill: Color, border: Color, font_size: int = 22) -> void:
	button.add_theme_stylebox_override("normal", button_style(fill, border))
	button.add_theme_stylebox_override("hover", button_style(fill.lightened(0.08), CYAN))
	button.add_theme_stylebox_override("pressed", button_style(fill.darkened(0.08), AMBER))
	button.add_theme_stylebox_override("focus", button_style(fill, AMBER))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", CYAN)
	button.add_theme_color_override("font_pressed_color", AMBER)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_font_size_override("font_size", font_size)
