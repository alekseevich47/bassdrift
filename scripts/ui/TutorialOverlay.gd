extends CanvasLayer

## First-night tips: hold the lane, release on the beat.
## Dismissing writes tutorial_seen on SaveManager.

signal dismissed

var _default_kicker := "FIRST NIGHT"
var _default_title := "HOW TO DRIFT"
var _default_miss := ""


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
	_default_kicker = %Kicker.text
	_default_title = %Title.text
	_default_miss = %MissBody.text
	call_deferred("_pull_race_tutorial")


func _exit_tree() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for group_name in ["race_world", "apex_race"]:
		var race := tree.get_first_node_in_group(group_name)
		if race and race.has_signal("tutorial_changed") and race.tutorial_changed.is_connected(_on_tutorial_changed):
			race.tutorial_changed.disconnect(_on_tutorial_changed)


func sync_from_race(active: bool, message: String) -> void:
	if not is_node_ready():
		call_deferred("sync_from_race", active, message)
		return
	if active and not message.is_empty():
		%Kicker.text = "ON THE LINE"
		%Title.text = "FIRST APEX"
		%MissBody.text = message
		return
	%Kicker.text = _default_kicker
	%Title.text = _default_title
	%MissBody.text = _default_miss


func _pull_race_tutorial() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for group_name in ["race_world", "apex_race"]:
		var race := tree.get_first_node_in_group(group_name)
		if race == null:
			continue
		if race.has_signal("tutorial_changed") and not race.tutorial_changed.is_connected(_on_tutorial_changed):
			race.tutorial_changed.connect(_on_tutorial_changed)
		if race.has_method("is_tutorial_active") and bool(race.is_tutorial_active()):
			var message := ""
			if race.has_method("tutorial_message"):
				message = str(race.tutorial_message())
			sync_from_race(true, message)
		return


func _on_tutorial_changed(active: bool, message: String) -> void:
	sync_from_race(active, message)


func _dismiss() -> void:
	SaveManager.set_tutorial_seen(true)
	dismissed.emit()
	queue_free()
