extends Control

## Portrait race shell. Driving, camera, and hit windows land in a later pass.
## configure(level_id) is the handoff from the menu.

signal exit_requested

var _level_id := ""


func _ready() -> void:
	_style()
	%BackButton.pressed.connect(_on_back_pressed)
	if _level_id.is_empty():
		_show_level(SaveManager.get_continue_level_id())


func configure(level_id: String) -> void:
	var resolved := level_id
	if resolved.is_empty() or not GameData.has_level(resolved) or not SaveManager.is_level_unlocked(resolved):
		resolved = SaveManager.get_continue_level_id()
	_show_level(resolved)


func current_level_id() -> String:
	return _level_id


func _on_back_pressed() -> void:
	exit_requested.emit()


func _show_level(level_id: String) -> void:
	_level_id = level_id
	var level := GameData.get_level(level_id)
	var car := GameData.get_car(SaveManager.get_selected_car())
	%LevelName.text = str(level.get("name", "Open Road"))
	%Meta.text = "%s  ·  %s  ·  %d BPM" % [
		str(level.get("chapter_name", "")),
		str(level.get("weather", "")).replace("_", " "),
		int(level.get("bpm", 0)),
	]
	%CarName.text = str(car.get("name", "Street 86"))
	%Hint.text = "Hold the lane. Release on the beat."


func _style() -> void:
	%Heading.add_theme_font_size_override("font_size", 18)
	%Heading.add_theme_color_override("font_color", UiPalette.MAGENTA)
	%LevelName.add_theme_font_size_override("font_size", 40)
	%LevelName.add_theme_color_override("font_color", UiPalette.INK)
	%Meta.add_theme_font_size_override("font_size", 16)
	%Meta.add_theme_color_override("font_color", UiPalette.CYAN)
	%CarName.add_theme_font_size_override("font_size", 22)
	%CarName.add_theme_color_override("font_color", UiPalette.AMBER)
	%Hint.add_theme_font_size_override("font_size", 16)
	%Hint.add_theme_color_override("font_color", UiPalette.MUTED)
	UiPalette.style_button(%BackButton, UiPalette.PIT, UiPalette.CYAN, 20)
