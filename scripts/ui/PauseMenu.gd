extends CanvasLayer

signal resume_requested
signal quit_requested
signal tips_requested


func _ready() -> void:
	add_to_group("apex_pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	%Dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	UiPalette.style_panel(%Panel, UiPalette.CYAN)
	UiPalette.style_label(%Title, UiPalette.INK, 32, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.prepare_scroll(%Scroll)
	UiPalette.style_button(%ResumeButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%QuitButton, UiPalette.PIT, UiPalette.MAGENTA, 18)
	%ResumeButton.custom_minimum_size = Vector2(0, 60)
	%QuitButton.custom_minimum_size = Vector2(0, 56)
	%ResumeButton.pressed.connect(func() -> void: resume_requested.emit())
	%QuitButton.pressed.connect(func() -> void: quit_requested.emit())
	if %Settings.has_signal("tips_requested"):
		%Settings.tips_requested.connect(_on_tips)
	%ResumeButton.grab_focus()


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
	if is_instance_valid(%Settings) and %Settings.has_method("shutdown"):
		%Settings.shutdown()
