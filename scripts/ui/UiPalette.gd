class_name UiPalette
extends Object

const BG := Color("#07060d")
const INK := Color("#f4f1ea")
const MUTED := Color("#b7a9b8")
const MAGENTA := Color("#ff2d8a")
const CYAN := Color("#3de1ff")
const AMBER := Color("#ffc857")
const PIT := Color("#1a1020")
const LAMP := Color("#ffd7a1")
const GOOD := Color("#d6ff6b")
const DANGER := Color("#ff5a6a")
const LOCK := Color("#6d6270")


static func button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(12)
	return box


static func style_button(button: Button, fill: Color, border: Color, font_size: int = 22) -> void:
	var hover := fill.lightened(0.08)
	button.add_theme_stylebox_override("normal", button_style(fill, border))
	button.add_theme_stylebox_override("hover", button_style(hover, CYAN))
	button.add_theme_stylebox_override("pressed", button_style(fill.darkened(0.08), AMBER))
	button.add_theme_stylebox_override("focus", button_style(fill, AMBER))
	button.add_theme_stylebox_override("disabled", button_style(fill.darkened(0.45), border.darkened(0.35)))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", CYAN)
	button.add_theme_color_override("font_pressed_color", AMBER)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", LOCK)
	button.add_theme_font_size_override("font_size", font_size)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func style_choice(button: Button, selected: bool, font_size: int = 16) -> void:
	if selected:
		style_button(button, PIT.lightened(0.1), CYAN, font_size)
	else:
		style_button(button, PIT, Color(MAGENTA.r, MAGENTA.g, MAGENTA.b, 0.9), font_size)


static func style_label(label: Label, color: Color, size: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align


static func paint_header(back: Button, title: Label, wallet: Label) -> void:
	style_button(back, PIT, CYAN, 16)
	back.custom_minimum_size = Vector2(104, 52)
	style_label(title, INK, 26, HORIZONTAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	if wallet:
		style_label(wallet, AMBER, 15, HORIZONTAL_ALIGNMENT_RIGHT)
		wallet.custom_minimum_size = Vector2(132, 0)
		wallet.clip_text = true
		wallet.text = money(SaveManager.get_cr()) if _save_ready() else "0 CR"


static func panel_style(border: Color = MAGENTA) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PIT.r, PIT.g, PIT.b, 0.94)
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func style_panel(panel: PanelContainer, border: Color = MAGENTA) -> void:
	panel.add_theme_stylebox_override("panel", panel_style(border))


static func style_check(check: CheckBox) -> void:
	check.add_theme_color_override("font_color", INK)
	check.add_theme_color_override("font_pressed_color", CYAN)
	check.add_theme_color_override("font_hover_color", CYAN)
	check.add_theme_font_size_override("font_size", 18)


static func style_slider(slider: Slider) -> void:
	slider.custom_minimum_size.y = 42


static func style_bar(bar: ProgressBar, fill: Color) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size.y = 16
	var background := StyleBoxFlat.new()
	background.bg_color = Color(BG.r, BG.g, BG.b, 0.9)
	background.set_corner_radius_all(6)
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill
	foreground.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", foreground)


static func prepare_scroll(scroll: ScrollContainer) -> void:
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func money(amount: int) -> String:
	return "%s CR" % grouped_int(amount)


static func grouped_int(amount: int) -> String:
	var negative := amount < 0
	var digits := str(absi(amount))
	var groups: PackedStringArray = []
	while digits.length() > 3:
		groups.insert(0, digits.substr(digits.length() - 3, 3))
		digits = digits.substr(0, digits.length() - 3)
	groups.insert(0, digits)
	var text := ",".join(groups)
	if negative:
		return "-" + text
	return text


static func stars(count: int, cap: int = 3) -> String:
	var filled := clampi(count, 0, cap)
	var text := ""
	for i in cap:
		text += "★" if i < filled else "☆"
	return text


static func clock(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%d:%02d" % [int(total / 60.0), total % 60]


static func trim_number(value) -> String:
	var number := float(value)
	if is_equal_approx(number, round(number)):
		return str(int(round(number)))
	return "%0.2f" % number


static func format_effect(effect: Dictionary) -> String:
	if effect.is_empty():
		return "Stock"
	var keys: Array = effect.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		if str(key) == "level":
			continue
		if absf(float(effect[key])) < 0.0001:
			continue
		parts.append(_format_stat(str(key), effect[key]))
	if parts.is_empty():
		return "Stock"
	return ", ".join(parts)


static func reason_text(result: Dictionary) -> String:
	match str(result.get("reason", "")):
		"not_enough_cr":
			return "Not enough CR."
		"stars_locked":
			return "Need %d stars for that car." % int(result.get("unlock_stars", 0))
		"already_owned":
			return "Already in the garage."
		"car_not_owned":
			return "Buy the car first."
		"max_level":
			return "Already maxed."
		"not_enough_skill_points":
			return "No skill points left."
		"paint_not_owned":
			return "Buy that paint first."
		"unknown_car", "unknown_upgrade", "unknown_paint", "unknown_perk":
			return "That part isn't in the catalog."
		_:
			return "Couldn't do that."


static func paint_tint(paint: Dictionary, time: float) -> Color:
	var primary := Color(str(paint.get("primary", "#e6e6ea")))
	var accent := Color(str(paint.get("accent", "#ff2d8a")))
	match str(paint.get("style", "gloss")):
		"metallic":
			return primary.lerp(Color.WHITE, 0.22)
		"chameleon":
			var wave := sin(time * 1.4) * 0.5 + 0.5
			return primary.lerp(accent, 0.2 + 0.6 * wave)
		_:
			return primary


static func _format_stat(key: String, value) -> String:
	match key:
		"angle_deg":
			return "+%s° angle" % trim_number(value)
		"score_mult":
			return "+%d%% score" % int(round(float(value) * 100.0))
		"speed_mult":
			return "+%d%% speed" % int(round(float(value) * 100.0))
		"wall_durability":
			return "+%d%% armor" % int(round(float(value) * 100.0))
		"snap":
			return "+%d%% snap" % int(round(float(value) * 100.0))
		"pickup_mult":
			return "+%d%% pickups" % int(round(float(value) * 100.0))
		"cr_bonus":
			return "+%d%% CR" % int(round(float(value) * 100.0))
		"boost_sec":
			return "+%ss boost" % trim_number(value)
		"slowmo_sec":
			return "+%ss focus" % trim_number(value)
		"extra_hits":
			return "+%s hits" % trim_number(value)
		"misses_kept":
			return "+%s misses kept" % trim_number(value)
		"window_ms":
			return "+%s ms window" % trim_number(value)
		"time_scale":
			return "time x%s" % trim_number(value)
		_:
			return "%s %s" % [key.replace("_", " "), trim_number(value)]


static func _save_ready() -> bool:
	return Engine.get_main_loop() != null and Engine.get_main_loop().root.get_node_or_null("SaveManager") != null
