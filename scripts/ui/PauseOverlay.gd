extends CanvasLayer

signal resume_requested
signal quit_requested


func _ready() -> void:
	%ResumeButton.pressed.connect(_on_resume_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	UiPalette.style_button(%ResumeButton, UiPalette.PIT, UiPalette.CYAN, 20)
	UiPalette.style_button(%QuitButton, UiPalette.PIT, UiPalette.MAGENTA, 20)
	%Title.add_theme_font_size_override("font_size", 36)
	%Title.add_theme_color_override("font_color", UiPalette.INK)


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
