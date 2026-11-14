extends Control

signal play_requested(level_id: String)


func _ready() -> void:
	_style()
	_refresh()
	%RaceButton.pressed.connect(_on_race_pressed)
	%RaceButton.grab_focus()
	SaveManager.currency_changed.connect(_on_currency_changed)
	SaveManager.pilot_changed.connect(_on_pilot_changed)
	SaveManager.campaign_changed.connect(_on_campaign_changed)


func _style() -> void:
	%Title.add_theme_font_size_override("font_size", 68)
	%Title.add_theme_color_override("font_color", UiPalette.INK)
	%Kicker.add_theme_font_size_override("font_size", 18)
	%Kicker.add_theme_color_override("font_color", UiPalette.MAGENTA)
	%Subtitle.add_theme_font_size_override("font_size", 18)
	%Subtitle.add_theme_color_override("font_color", UiPalette.MUTED)
	%Status.add_theme_font_size_override("font_size", 16)
	%Status.add_theme_color_override("font_color", UiPalette.AMBER)
	UiPalette.style_button(%RaceButton, UiPalette.PIT, UiPalette.MAGENTA, 24)


func _on_currency_changed(_cr: int) -> void:
	_refresh()


func _on_pilot_changed(_level: int, _xp: int, _points: int) -> void:
	_refresh()


func _on_campaign_changed() -> void:
	_refresh()


func _refresh() -> void:
	var rank := GameData.get_rank_for_level(SaveManager.get_pilot_level())
	var level := GameData.get_level(SaveManager.get_continue_level_id())
	%Status.text = "%s  ·  %d CR  ·  %d stars\nNext: %s" % [
		str(rank.get("name", "Novice")),
		SaveManager.get_cr(),
		SaveManager.get_total_stars(),
		str(level.get("name", "Touge Gate")),
	]


func _on_race_pressed() -> void:
	play_requested.emit(SaveManager.get_continue_level_id())
