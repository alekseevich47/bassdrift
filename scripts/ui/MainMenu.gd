extends Control

## Night-garage front door. Sub-screens cover the home layout; the race
## button and campaign rows hand a level id to Main.show_race.

signal play_requested(level_id: String)
signal custom_race_requested(request: Dictionary)
signal tips_requested

const SCREENS := {
	"campaign": "res://scenes/ui/CampaignUI.tscn",
	"garage": "res://scenes/ui/GarageUI.tscn",
	"pilot": "res://scenes/ui/PilotUI.tscn",
	"custom": "res://scenes/ui/CustomTrackUI.tscn",
	"settings": "res://scenes/ui/SettingsScreen.tscn",
}

var _screen: Control = null
var _screen_id := ""
var _time := 0.0
var _paint: Dictionary = {}
var _accent := Color("#ff2d8a")
var _pivot_base := Vector2.ZERO
var _lamp: ColorRect
var _pivot: Control
var _body: ColorRect
var _cabin: ColorRect
var _stripe: ColorRect
var _glow: ColorRect
var _bumper: ColorRect


func _ready() -> void:
	_build_hero()
	_style()
	_bind()
	_refresh()
	%Stage.resized.connect(_layout_stage)
	_layout_stage()
	call_deferred("_layout_stage")
	%RaceButton.grab_focus()


func _process(delta: float) -> void:
	if not $Margin.visible:
		return
	_time += delta
	_animate_hero()


func open_campaign() -> void:
	_open_screen("campaign")


func open_garage() -> void:
	_open_screen("garage")


func open_pilot() -> void:
	_open_screen("pilot")


func open_custom() -> void:
	_open_screen("custom")


func open_settings() -> void:
	_open_screen("settings")


func handle_back() -> bool:
	if _screen_id.is_empty():
		return false
	close_screen()
	return true


func close_screen() -> void:
	if is_instance_valid(_screen):
		_screen.hide()
		_screen.name = "closed_screen"
		_screen.queue_free()
	_screen = null
	_screen_id = ""
	$Margin.visible = true
	_refresh()


func _open_screen(screen_id: String) -> void:
	if not SCREENS.has(screen_id):
		return
	if _screen_id == screen_id and is_instance_valid(_screen) and not _screen.is_queued_for_deletion():
		return
	close_screen()
	var packed := load(str(SCREENS[screen_id])) as PackedScene
	if packed == null:
		push_error("Missing screen: %s" % screen_id)
		return
	var screen := packed.instantiate() as Control
	%ScreenHost.add_child(screen)
	_screen = screen
	_screen_id = screen_id
	$Margin.visible = false
	if screen.has_signal("closed"):
		screen.closed.connect(close_screen)
	if screen.has_signal("race_requested"):
		screen.race_requested.connect(_on_screen_race)
	if screen.has_signal("custom_race_requested"):
		screen.custom_race_requested.connect(_on_screen_custom)
	if screen.has_signal("tips_requested"):
		screen.tips_requested.connect(func() -> void: tips_requested.emit())


func _on_screen_race(level_id: String) -> void:
	play_requested.emit(level_id)


func _on_screen_custom(request: Dictionary) -> void:
	custom_race_requested.emit(request)


func _bind() -> void:
	%LevelsButton.pressed.connect(open_campaign)
	%CustomButton.pressed.connect(open_custom)
	%GarageButton.pressed.connect(open_garage)
	%PilotButton.pressed.connect(open_pilot)
	%SettingsButton.pressed.connect(open_settings)
	%RaceButton.pressed.connect(_on_race_pressed)
	SaveManager.currency_changed.connect(_on_currency_changed)
	SaveManager.pilot_changed.connect(_on_pilot_changed)
	SaveManager.campaign_changed.connect(_on_campaign_changed)
	SaveManager.garage_changed.connect(_on_garage_changed)
	SaveManager.settings_changed.connect(_on_settings_changed)


func _style() -> void:
	%Title.add_theme_font_size_override("font_size", 64)
	%Title.add_theme_color_override("font_color", UiPalette.INK)
	%Kicker.add_theme_font_size_override("font_size", 16)
	%Kicker.add_theme_color_override("font_color", UiPalette.MAGENTA)
	%Subtitle.add_theme_font_size_override("font_size", 16)
	%Subtitle.add_theme_color_override("font_color", UiPalette.MUTED)
	%Status.add_theme_font_size_override("font_size", 16)
	%Status.add_theme_color_override("font_color", UiPalette.AMBER)
	UiPalette.style_label(%CarName, UiPalette.INK, 22, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.style_label(%PaintName, UiPalette.CYAN, 14, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.style_button(%LevelsButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%CustomButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%GarageButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%PilotButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%SettingsButton, UiPalette.PIT, UiPalette.AMBER, 18)
	UiPalette.style_button(%RaceButton, UiPalette.PIT, UiPalette.MAGENTA, 26)


func _on_currency_changed(_cr: int) -> void:
	_refresh()


func _on_pilot_changed(_level: int, _xp: int, _points: int) -> void:
	_refresh()


func _on_campaign_changed() -> void:
	_refresh()


func _on_garage_changed() -> void:
	_refresh()


func _on_settings_changed() -> void:
	_refresh()


func _refresh() -> void:
	var rank := GameData.get_rank_for_level(SaveManager.get_pilot_level())
	var level := GameData.get_level(SaveManager.get_continue_level_id())
	%Status.text = "%s  ·  %s  ·  %d stars\nNext: %s" % [
		str(rank.get("name", "Novice")),
		UiPalette.money(SaveManager.get_cr()),
		SaveManager.get_total_stars(),
		str(level.get("name", "Touge Gate")),
	]
	_apply_hero_colors()


func _on_race_pressed() -> void:
	play_requested.emit(SaveManager.get_continue_level_id())


func _build_hero() -> void:
	_lamp = ColorRect.new()
	_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lamp.color = Color(UiPalette.LAMP.r, UiPalette.LAMP.g, UiPalette.LAMP.b, 0.14)
	%Stage.add_child(_lamp)
	%Stage.move_child(_lamp, 0)

	_pivot = Control.new()
	_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pivot.custom_minimum_size = Vector2(240, 160)
	%Stage.add_child(_pivot)
	%Stage.move_child(_pivot, 1)

	_glow = _rect(Vector2(-10, 122), Vector2(260, 16), Color(UiPalette.MAGENTA.r, UiPalette.MAGENTA.g, UiPalette.MAGENTA.b, 0.35))
	_body = _rect(Vector2(10, 58), Vector2(220, 64), Color("#e6e6ea"))
	_cabin = _rect(Vector2(68, 24), Vector2(104, 40), Color("#16161c"))
	_stripe = _rect(Vector2(10, 86), Vector2(220, 8), UiPalette.MAGENTA)
	_bumper = _rect(Vector2(10, 112), Vector2(220, 10), Color("#16161c"))
	_rect(Vector2(18, 108), Vector2(204, 8), Color(0, 0, 0, 0.35))
	_add_wheel(Vector2(28, 102))
	_add_wheel(Vector2(172, 102))
	_rect(Vector2(18, 70), Vector2(18, 10), UiPalette.AMBER)
	_rect(Vector2(204, 70), Vector2(18, 10), UiPalette.AMBER)
	_rect(Vector2(78, 32), Vector2(36, 4), Color(1, 1, 1, 0.35))

	%CarName.z_index = 2
	%PaintName.z_index = 2


func _rect(at: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = at
	rect.size = size
	rect.color = color
	_pivot.add_child(rect)
	return rect


func _add_wheel(at: Vector2) -> void:
	var wheel := Panel.new()
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.position = at
	wheel.size = Vector2(40, 40)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#121216")
	box.border_color = Color("#d9d4cc")
	box.set_border_width_all(4)
	box.set_corner_radius_all(20)
	wheel.add_theme_stylebox_override("panel", box)
	_pivot.add_child(wheel)


func _layout_stage() -> void:
	var size: Vector2 = %Stage.size
	if size.x < 20.0 or size.y < 20.0:
		return
	var name_band := 86.0
	var car_height := 156.0
	_pivot_base = Vector2(size.x * 0.5 - 120.0, maxf(size.y - name_band - car_height, 8.0))
	_pivot.position = _pivot_base
	_lamp.size = Vector2(200, maxf(_pivot_base.y + 78.0, 48.0))
	_lamp.position = Vector2(size.x * 0.5 - 100.0, 0)


func _apply_hero_colors() -> void:
	var car_id := SaveManager.get_selected_car()
	var car := GameData.get_car(car_id)
	_paint = SaveManager.get_paint(car_id)
	var style := GameData.get_paint_style(str(_paint.get("style", "gloss")))
	%CarName.text = str(car.get("name", "Street 86"))
	%PaintName.text = "%s  ·  %s" % [
		str(style.get("name", "Gloss")).to_upper(),
		str(_paint.get("primary", "#e6e6ea")).to_upper(),
	]
	_accent = Color(str(_paint.get("accent", "#ff2d8a")))
	if _cabin:
		_cabin.color = Color(str(_paint.get("secondary", "#16161c")))
	if _bumper:
		_bumper.color = Color(str(_paint.get("secondary", "#16161c"))).lightened(0.08)


func _animate_hero() -> void:
	if _pivot_base == Vector2.ZERO and %Stage.size.y > 20.0:
		_layout_stage()
	if _body == null or _lamp == null:
		return
	var quality := SaveManager.get_graphics_quality()
	var energy := 1.0
	if quality == "low":
		energy = 0.55
	elif quality == "high":
		energy = 1.25
	var flick := 0.82 + 0.18 * sin(_time * 2.6)
	if quality != "low":
		flick *= 0.85 + 0.15 * sin(_time * 11.0)
	_lamp.color = Color(UiPalette.LAMP.r, UiPalette.LAMP.g, UiPalette.LAMP.b, 0.18 * flick * energy)
	_body.color = UiPalette.paint_tint(_paint, _time if quality != "low" else 0.2)
	_stripe.color = _accent
	var glow_alpha := 0.28 + (0.18 * sin(_time * 3.0) if quality != "low" else 0.0)
	_glow.color = Color(_accent.r, _accent.g, _accent.b, glow_alpha * energy)
	if quality == "low":
		_pivot.position = _pivot_base
	else:
		_pivot.position = _pivot_base + Vector2(sin(_time * 0.8) * 6.0, cos(_time * 0.55) * 2.0)
