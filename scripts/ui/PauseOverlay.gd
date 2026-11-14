extends CanvasLayer

## Full pause card used by RaceWorld's pause button.
## Node path Panel/ResumeButton stays stable for the foundation smoke check.
## Resume and quit match the older overlay. Settings and tips live underneath.

signal resume_requested
signal quit_requested
signal tips_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%Dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	UiPalette.style_label(%Title, UiPalette.INK, 32, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.prepare_scroll(%Scroll)
	UiPalette.style_button(%ResumeButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%QuitButton, UiPalette.PIT, UiPalette.MAGENTA, 18)
	%ResumeButton.pressed.connect(func() -> void: resume_requested.emit())
	%QuitButton.pressed.connect(func() -> void: quit_requested.emit())
	var settings := get_node("Panel/Scroll/Settings")
	if settings.has_signal("tips_requested"):
		settings.tips_requested.connect(_on_tips)
	%ResumeButton.grab_focus()


func _exit_tree() -> void:
	shutdown()


func _on_tips() -> void:
	_open_tutorial()
	tips_requested.emit()


func _open_tutorial() -> void:
	var tree := get_tree()
	if tree and tree.get_first_node_in_group("apex_tutorial") != null:
		return
	var packed := load("res://scenes/overlays/TutorialOverlay.tscn") as PackedScene
	if packed == null:
		return
	var tip := packed.instantiate()
	if tip is CanvasLayer:
		(tip as CanvasLayer).layer = 90
	add_child(tip)


func shutdown() -> void:
	var settings := get_node_or_null("Panel/Scroll/Settings")
	if settings and settings.has_method("shutdown"):
		settings.shutdown()
