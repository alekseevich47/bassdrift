extends CanvasLayer

## First-night tips: hold the lane, release on the beat.
## Dismissing writes tutorial_seen on SaveManager.

signal dismissed


func _ready() -> void:
	add_to_group("apex_tutorial")
	process_mode = Node.PROCESS_MODE_ALWAYS
	%Dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	UiPalette.style_panel(%Panel, UiPalette.MAGENTA)
	UiPalette.style_label(%Kicker, UiPalette.MAGENTA, 14, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.style_label(%Title, UiPalette.INK, 32, HORIZONTAL_ALIGNMENT_CENTER)
	for verb in [%HoldVerb, %ReleaseVerb, %MissVerb]:
		UiPalette.style_label(verb, UiPalette.CYAN, 22, HORIZONTAL_ALIGNMENT_LEFT)
	for body in [%HoldBody, %ReleaseBody, %MissBody]:
		UiPalette.style_label(body, UiPalette.MUTED, 16, HORIZONTAL_ALIGNMENT_LEFT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_button(%OkButton, UiPalette.PIT, UiPalette.MAGENTA, 20)
	%OkButton.custom_minimum_size = Vector2(0, 64)
	%OkButton.pressed.connect(_dismiss)
	%OkButton.grab_focus()


func _dismiss() -> void:
	SaveManager.set_tutorial_seen(true)
	dismissed.emit()
	queue_free()
