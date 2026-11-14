extends Control

## Scene router for menu and race.
## Overlays live on OverlayHost so RaceWorld can later instance the same packed scenes.
## Custom races are stored on the race node as meta "apex_race_request" and on get_race_request().
## Campaign handoff remains show_race(level_id).

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const RACE_SCENE := "res://scenes/RaceWorld.tscn"
const RACE_HUD_SCENE := "res://scenes/overlays/RaceHUD.tscn"
const RESULT_SCENE := "res://scenes/overlays/ResultScreen.tscn"
const PAUSE_SCENE := "res://scenes/overlays/PauseMenu.tscn"
const TUTORIAL_SCENE := "res://scenes/overlays/TutorialOverlay.tscn"

const RESULT_SIGNALS: Array = ["race_finished", "run_finished", "result_ready", "race_results", "race_ended", "race_failed"]

signal scene_changed(scene_name: String)

var _active := ""
var _bound_results: Dictionary = {}
var race_request: Dictionary = {"mode": "campaign", "level_id": ""}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var host := CanvasLayer.new()
	host.name = "OverlayHost"
	host.layer = 20
	add_child(host)
	show_menu()
	if OS.get_cmdline_user_args().has("--smoke"):
		var runner: Node = load("res://tools/smoke_check.gd").new()
		add_child(runner)
	elif OS.get_cmdline_user_args().has("--ui-smoke"):
		var runner: Node = load("res://tools/ui_smoke.gd").new()
		add_child(runner)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _active == "race":
		if _overlay("ResultScreen") != null or _overlay("TutorialOverlay") != null:
			return
		if _overlay("PauseMenu") != null:
			_on_resume()
		else:
			show_pause()
		get_viewport().set_input_as_handled()
		return
	if _active != "menu":
		return
	var menu := _menu_node()
	if menu and menu.has_method("handle_back") and bool(menu.handle_back()):
		get_viewport().set_input_as_handled()


func show_menu() -> void:
	_set_paused(false)
	_clear_overlays()
	var node := _swap(MENU_SCENE)
	if node == null:
		return
	if node.has_signal("play_requested"):
		node.play_requested.connect(func(level_id: String) -> void:
			show_race.call_deferred(level_id)
		)
	if node.has_signal("custom_race_requested"):
		node.custom_race_requested.connect(func(request: Dictionary) -> void:
			var copy := request.duplicate(true)
			show_custom_race.call_deferred(copy)
		)
	if node.has_signal("tips_requested"):
		node.tips_requested.connect(show_tutorial)
	_active = "menu"
	scene_changed.emit("menu")
	if not SaveManager.has_seen_tutorial():
		show_tutorial()


func show_race(level_id: String = "", extra: Dictionary = {}) -> void:
	var request := {"mode": "campaign", "level_id": level_id}
	if typeof(extra) == TYPE_DICTIONARY and not extra.is_empty():
		request.merge(extra, true)
		request["level_id"] = level_id if not str(extra.get("level_id", "")).is_empty() else level_id
		if str(request.get("mode", "")).is_empty():
			request["mode"] = "campaign"
	_enter_race(request)


func show_custom_race(request: Dictionary) -> void:
	var payload := request.duplicate(true)
	payload["mode"] = "custom"
	if not payload.has("level_id"):
		payload["level_id"] = ""
	_enter_race(payload)


func show_results(result: Dictionary) -> void:
	var enriched := _decorate_result(result)
	var existing := _overlay("ResultScreen")
	if existing and existing.has_method("present"):
		_set_paused(true)
		existing.present(enriched)
		return
	_set_paused(true)
	var screen := _mount(RESULT_SCENE, 60)
	if screen == null:
		return
	if screen.has_signal("restart_requested"):
		screen.restart_requested.connect(_restart_race)
	if screen.has_signal("garage_requested"):
		screen.garage_requested.connect(_results_to_garage)
	if screen.has_signal("revive_accepted"):
		screen.revive_accepted.connect(_on_revived)
	if screen.has_method("present"):
		screen.present(enriched)


func show_pause() -> void:
	if _active != "race":
		return
	if _overlay("PauseMenu") != null or _overlay("ResultScreen") != null:
		return
	_set_paused(true)
	var pause := _mount(PAUSE_SCENE, 50)
	if pause == null:
		_set_paused(false)
		return
	if pause.has_signal("resume_requested"):
		pause.resume_requested.connect(_on_resume)
	if pause.has_signal("quit_requested"):
		pause.quit_requested.connect(show_menu)
	if pause.has_signal("tips_requested"):
		pause.tips_requested.connect(show_tutorial)


func show_tutorial() -> void:
	if get_tree() and get_tree().get_first_node_in_group("apex_tutorial") != null:
		return
	if _overlay("TutorialOverlay") != null:
		return
	_mount(TUTORIAL_SCENE, 80)


func get_race_request() -> Dictionary:
	return race_request.duplicate(true)


func current_scene_name() -> String:
	return _active


func _enter_race(request: Dictionary) -> void:
	_set_paused(false)
	_clear_overlays()
	_bound_results.clear()
	race_request = request.duplicate(true)
	var node := _swap(RACE_SCENE)
	if node == null:
		return
	var payload := race_request.duplicate(true)
	node.set_meta("apex_race_request", payload)
	get_tree().root.set_meta("apex_race_request", payload)
	var custom := str(payload.get("mode", "")) == "custom"
	if custom and node.has_method("configure_user_audio"):
		node.configure_user_audio(str(payload.get("audio_path", "")))
	elif custom and node.has_method("configure_custom"):
		node.configure_custom(payload)
	elif node.has_method("configure"):
		node.configure(str(payload.get("level_id", "")))
	if node.has_signal("exit_requested"):
		node.exit_requested.connect(show_menu)
	_bind_race(node)
	_mount_hud(node)
	_active = "race"
	scene_changed.emit("race")


func _mount_hud(race: Node) -> void:
	# Gameplay draws its own readout and emits hud_updated. A second bar would stack.
	if race and (race.has_signal("hud_updated") or race.has_method("hud_snapshot")):
		return
	if _living_group("apex_race_hud") != null:
		return
	if race and race.find_child("RaceHUD", true, false) != null:
		return
	var hud := _mount(RACE_HUD_SCENE, 40)
	if hud == null:
		return
	if hud.has_signal("pause_requested"):
		hud.pause_requested.connect(show_pause)
	if hud.has_signal("run_finished"):
		hud.run_finished.connect(show_results)


func _bind_race(node: Node) -> void:
	_bind_result_node(node)
	var tree := get_tree()
	if tree == null:
		return
	for group_name in ["race_world", "apex_race"]:
		for grouped in tree.get_nodes_in_group(group_name):
			_bind_result_node(grouped)


func _bind_result_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _bound_results.has(id):
		return
	_bound_results[id] = true
	for sig_name in RESULT_SIGNALS:
		_connect_loose(node, sig_name, _on_race_result_signal)
	if node.has_signal("pause_requested"):
		_connect_loose(node, "pause_requested", _on_pause_signal)


func _connect_loose(node: Node, sig_name: String, method: Callable) -> void:
	if node == null or not node.has_signal(sig_name):
		return
	var argc := 0
	for entry in node.get_signal_list():
		if str(entry.get("name", "")) != sig_name:
			continue
		argc = (entry.get("args", []) as Array).size()
		break
	var callback: Callable
	if argc <= 0:
		callback = func() -> void: method.call(null)
	elif argc == 1:
		callback = func(first) -> void: method.call(first)
	else:
		callback = func(first, _second = null) -> void: method.call(first)
	var err := node.connect(sig_name, callback)
	if err != OK:
		push_warning("APEX UI: skipped %s (%s)" % [sig_name, err])


func _on_race_result_signal(payload = null) -> void:
	show_results(_coerce_result(payload))


func _on_pause_signal(_payload = null) -> void:
	show_pause()


func _coerce_result(payload) -> Dictionary:
	if typeof(payload) == TYPE_DICTIONARY:
		return payload
	if typeof(payload) == TYPE_STRING:
		return {
			"crashed": true,
			"can_revive": false,
			"reason": str(payload),
			"status": _start_failure_copy(str(payload)),
			"level_name": "Couldn't start",
			"level_id": str(race_request.get("level_id", "")),
			"score": 0,
		}
	if typeof(payload) == TYPE_INT or typeof(payload) == TYPE_FLOAT:
		return {"score": int(payload), "level_id": str(race_request.get("level_id", ""))}
	if typeof(payload) == TYPE_ARRAY and not (payload as Array).is_empty():
		return _coerce_result((payload as Array)[0])
	return {"level_id": str(race_request.get("level_id", ""))}


func _start_failure_copy(reason: String) -> String:
	match reason:
		"file_missing", "empty_path":
			return "That track isn't there."
		"unsupported_format":
			return "Use an mp3, ogg, or wav."
		"decode_failed", "empty_audio", "wav_too_small", "wav_header", "wav_chunk", "wav_format", "wav_unsupported", "no_audio":
			return "That file didn't play."
		_:
			return "The race couldn't start."


func _decorate_result(result: Dictionary) -> Dictionary:
	var out := result.duplicate(true)
	if str(out.get("level_id", "")).is_empty():
		out["level_id"] = str(race_request.get("level_id", ""))
	if str(out.get("mode", "")).is_empty():
		out["mode"] = str(race_request.get("mode", "campaign"))
	if str(out.get("display_name", "")).is_empty() and race_request.has("display_name"):
		out["display_name"] = race_request["display_name"]
	if str(out.get("difficulty", "")).is_empty():
		out["difficulty"] = str(race_request.get("difficulty", SaveManager.get_difficulty()))
	return out


func _restart_race() -> void:
	if str(race_request.get("mode", "")) == "custom":
		show_custom_race(race_request)
		return
	show_race(str(race_request.get("level_id", "")))


func _results_to_garage() -> void:
	show_menu()
	var menu := _menu_node()
	if menu and menu.has_method("open_garage"):
		menu.open_garage()


func _on_revived() -> void:
	_close_named("ResultScreen")
	_set_paused(false)
	var race := _race_node()
	if race == null:
		return
	race.set_meta("apex_revive_token", Time.get_ticks_msec())
	if race.has_method("revive"):
		race.revive()
	elif race.has_method("resume_run"):
		race.resume_run()
	_mount_hud(race)


func _on_resume() -> void:
	_set_paused(false)
	_close_named("PauseMenu")


func _mount(scene_path: String, layer: int) -> Node:
	var host := get_node_or_null("OverlayHost")
	if host == null:
		push_error("APEX UI: OverlayHost missing")
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Missing overlay: %s" % scene_path)
		return null
	var node := packed.instantiate()
	if node is CanvasLayer:
		(node as CanvasLayer).layer = layer
	host.add_child(node)
	return node


func _clear_overlays() -> void:
	var host := get_node_or_null("OverlayHost")
	if host == null:
		return
	for child in host.get_children():
		_retire(child)


func _close_named(node_name: String) -> void:
	var node := _overlay(node_name)
	if node:
		_retire(node)


func _retire(node: Node) -> void:
	if node == null or node.is_queued_for_deletion():
		return
	if node.has_method("shutdown"):
		node.shutdown()
	for group_name in ["apex_race_hud", "apex_result_screen", "apex_pause_menu"]:
		if node.is_in_group(group_name):
			node.remove_from_group(group_name)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CanvasLayer:
		(node as CanvasLayer).layer = -50
	node.name = "retired_%d" % node.get_instance_id()
	node.queue_free()


func _overlay(node_name: String) -> Node:
	var host := get_node_or_null("OverlayHost")
	if host == null:
		return null
	for child in host.get_children():
		if child.name == node_name and not child.is_queued_for_deletion():
			return child
	return null


func _living_group(group_name: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(group_name):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			return node
	return null


func _swap(scene_path: String) -> Node:
	var host := $Host
	for child in host.get_children():
		host.remove_child(child)
		child.free()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Missing scene: %s" % scene_path)
		return null
	var node := packed.instantiate()
	host.add_child(node)
	return node


func _menu_node() -> Node:
	var host := get_node_or_null("Host")
	if host == null or host.get_child_count() == 0:
		return null
	var node := host.get_child(0)
	if node == null or node.is_queued_for_deletion():
		return null
	return node


func _race_node() -> Node:
	return _menu_node()


func _set_paused(value: bool) -> void:
	var tree := get_tree()
	if tree:
		tree.paused = value
