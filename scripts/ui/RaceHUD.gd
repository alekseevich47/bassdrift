extends CanvasLayer

## Minimal score, combo, progress, and rhythm bar.
##
## Telemetry sources, first match wins:
##   groups race_world, apex_race, player_car, then the router's current race node.
## Signals: score_changed, score_updated, combo_changed, combo_updated,
##   progress_changed, track_progress_changed, rhythm_event, beat_hit,
##   rhythm_pulse, telemetry_changed, hud_state_changed.
## RaceWorld: hud_state_changed(state) with score, combo, progress, bpm, beat_pulse,
##   beat_pulse(intensity, beat_index), judgement_shown(kind, points, combo).
## Methods polled at 10 Hz: get_score, get_combo, get_progress,
##   get_track_progress, get_rhythm, get_bpm, hud_snapshot.
## pause_requested comes from the pause button.
## push_result(dict) emits run_finished for the router.

signal pause_requested
signal run_finished(result: Dictionary)

const SCORE_SIGNALS: Array = ["score_changed", "score_updated"]
const COMBO_SIGNALS: Array = ["combo_changed", "combo_updated"]
const PROGRESS_SIGNALS: Array = ["progress_changed", "track_progress_changed"]
const RHYTHM_SIGNALS: Array = ["rhythm_event", "beat_hit", "rhythm_pulse"]
const BUNDLE_SIGNALS: Array = ["telemetry_changed", "hud_state_changed"]

var _bound: Dictionary = {}
var _time := 0.0
var _poll := 0.0
var _score := 0
var _combo := 0
var _progress := 0.0
var _bpm_override := 0.0
var _hint_life := 0.0
var _hint_text := ""
var _external_rhythm := false
var _pulse_latched := false
var _judgement_seen := ""


func _ready() -> void:
	add_to_group("apex_race_hud")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	%Root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiPalette.style_label(%Score, UiPalette.INK, 42, HORIZONTAL_ALIGNMENT_LEFT)
	UiPalette.style_label(%Combo, UiPalette.AMBER, 18, HORIZONTAL_ALIGNMENT_LEFT)
	UiPalette.style_label(%ProgressLabel, UiPalette.CYAN, 13, HORIZONTAL_ALIGNMENT_RIGHT)
	UiPalette.style_label(%RhythmHint, UiPalette.MUTED, 13, HORIZONTAL_ALIGNMENT_LEFT)
	UiPalette.style_bar(%Progress, UiPalette.CYAN)
	%Progress.min_value = 0
	%Progress.max_value = 100
	UiPalette.style_button(%PauseButton, UiPalette.PIT, UiPalette.CYAN, 14)
	%PauseButton.pressed.connect(func() -> void: pause_requested.emit())
	%Marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_score(0)
	set_combo(0)
	set_progress(0.0)
	_bind_available()


func _process(delta: float) -> void:
	_time += delta
	_poll += delta
	if _hint_life > 0.0:
		_hint_life = maxf(_hint_life - delta, 0.0)
	_draw_rhythm()
	if _poll < 0.1:
		return
	_poll = 0.0
	_bind_available()
	_poll_telemetry()


func set_score(score: int) -> void:
	_score = maxi(score, 0)
	if is_node_ready():
		%Score.text = UiPalette.grouped_int(_score)


func set_combo(combo: int) -> void:
	_combo = maxi(combo, 0)
	if not is_node_ready():
		return
	if _combo <= 0:
		%Combo.text = "COMBO —"
		return
	%Combo.text = "COMBO  x%d" % _combo


func set_progress(value: float) -> void:
	var ratio := value
	if value > 1.0:
		ratio = value / 100.0
	_progress = clampf(ratio, 0.0, 1.0)
	if not is_node_ready():
		return
	%Progress.value = _progress * 100.0
	%ProgressLabel.text = "%d%%" % int(round(_progress * 100.0))


func set_bpm(bpm: float) -> void:
	_bpm_override = maxf(bpm, 0.0)


func pulse_rhythm(payload = null) -> void:
	_on_rhythm_signal(payload)


func push_result(result: Dictionary) -> void:
	run_finished.emit(result)


func _bind_available() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for group_name in ["race_world", "apex_race", "player_car"]:
		for node in tree.get_nodes_in_group(group_name):
			_bind_node(node)
	_bind_node(_find_race())


func _bind_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _bound.has(id):
		return
	_bound[id] = true
	for sig_name in SCORE_SIGNALS:
		_connect_loose(node, sig_name, _on_score_signal)
	for sig_name in COMBO_SIGNALS:
		_connect_loose(node, sig_name, _on_combo_signal)
	for sig_name in PROGRESS_SIGNALS:
		_connect_loose(node, sig_name, _on_progress_signal)
	for sig_name in RHYTHM_SIGNALS:
		_connect_loose(node, sig_name, _on_rhythm_signal)
	for sig_name in BUNDLE_SIGNALS:
		_connect_loose(node, sig_name, _on_bundle_signal)
	_bind_raceworld(node)


func _bind_raceworld(node: Node) -> void:
	var hud_argc := _signal_argc(node, "hud_updated")
	if hud_argc >= 5:
		node.hud_updated.connect(_on_hud_updated)
	elif hud_argc == 1:
		node.hud_updated.connect(_on_bundle_signal)
	var beat_argc := _signal_argc(node, "beat_pulse")
	if beat_argc >= 2:
		node.beat_pulse.connect(_on_beat_pulse)
	elif beat_argc >= 0:
		_connect_loose(node, "beat_pulse", _on_rhythm_signal)
	var judge_argc := _signal_argc(node, "judgement_shown")
	if judge_argc >= 3:
		node.judgement_shown.connect(_on_judgement)
	elif judge_argc >= 1:
		node.judgement_shown.connect(func(kind) -> void: _on_rhythm_signal(kind))


func _signal_argc(node: Node, sig_name: String) -> int:
	if node == null or not node.has_signal(sig_name):
		return -1
	for entry in node.get_signal_list():
		if str(entry.get("name", "")) != sig_name:
			continue
		return (entry.get("args", []) as Array).size()
	return -1


func _on_hud_updated(score: int, combo: int, progress: float, _hp: float, beat_pulse: float) -> void:
	set_score(score)
	set_combo(combo)
	set_progress(progress)
	if beat_pulse >= 0.65:
		_on_rhythm_signal("LOCK")


func _on_beat_pulse(intensity: float, _beat_index: int = 0) -> void:
	_on_rhythm_signal(intensity)


func _on_judgement(kind: String, _points: int = 0, combo: int = 0) -> void:
	if combo > 0:
		set_combo(combo)
	_on_rhythm_signal(kind)


func _connect_loose(node: Node, sig_name: String, method: Callable) -> void:
	if not node.has_signal(sig_name):
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
	node.connect(sig_name, callback)


func _poll_telemetry() -> void:
	var nodes: Array = []
	var race := _find_race()
	if race:
		nodes.append(race)
	var tree := get_tree()
	if tree:
		for group_name in ["race_world", "apex_race", "player_car"]:
			for node in tree.get_nodes_in_group(group_name):
				nodes.append(node)
	for node in nodes:
		var score = _call(node, "get_score")
		if _is_number(score):
			set_score(int(score))
		var combo = _call(node, "get_combo")
		if _is_number(combo):
			set_combo(int(combo))
		var progress = _call(node, "get_progress")
		if not _is_number(progress):
			progress = _call(node, "get_track_progress")
		if _is_number(progress):
			set_progress(float(progress))
		var rhythm = _call(node, "get_rhythm")
		if rhythm != null:
			pulse_rhythm(rhythm)
		var bpm = _call(node, "get_bpm")
		if _is_number(bpm) and float(bpm) > 1.0:
			set_bpm(float(bpm))
		var snap = _call(node, "hud_snapshot")
		if typeof(snap) == TYPE_DICTIONARY:
			_on_bundle_signal(snap)


func _on_score_signal(payload = null) -> void:
	if _is_number(payload):
		set_score(int(payload))
	elif typeof(payload) == TYPE_DICTIONARY and (payload as Dictionary).has("score"):
		set_score(int((payload as Dictionary)["score"]))


func _on_combo_signal(payload = null) -> void:
	if _is_number(payload):
		set_combo(int(payload))
	elif typeof(payload) == TYPE_DICTIONARY and (payload as Dictionary).has("combo"):
		set_combo(int((payload as Dictionary)["combo"]))


func _on_progress_signal(payload = null) -> void:
	if _is_number(payload):
		set_progress(float(payload))
	elif typeof(payload) == TYPE_DICTIONARY and (payload as Dictionary).has("progress"):
		set_progress(float((payload as Dictionary)["progress"]))


func _on_rhythm_signal(payload = null) -> void:
	_external_rhythm = true
	var label := "BEAT"
	var accuracy := 1.0
	if typeof(payload) == TYPE_STRING:
		label = str(payload).to_upper()
	elif _is_number(payload):
		var number := float(payload)
		if absf(number) > 1.5:
			accuracy = clampf(1.0 - absf(number) / 90.0, 0.0, 1.0)
			label = "EARLY" if number < 0.0 else "LATE"
			if absf(number) <= 25.0:
				label = "PERFECT"
		else:
			accuracy = clampf(number, 0.0, 1.0)
			label = "LOCK" if accuracy >= 0.85 else "DRIFT"
	elif typeof(payload) == TYPE_DICTIONARY:
		var data: Dictionary = payload
		if data.has("offset_ms"):
			_on_rhythm_signal(float(data["offset_ms"]))
			return
		if data.has("accuracy"):
			_on_rhythm_signal(float(data["accuracy"]))
			return
		label = str(data.get("kind", data.get("label", "BEAT"))).to_upper()
	elif typeof(payload) == TYPE_BOOL:
		label = "LOCK" if bool(payload) else "MISS"
		accuracy = 1.0 if bool(payload) else 0.2
	_hint_text = label
	_hint_life = 0.35
	%Marker.color = UiPalette.AMBER.lerp(UiPalette.MAGENTA, 1.0 - accuracy)


func _on_bundle_signal(payload = null) -> void:
	if typeof(payload) != TYPE_DICTIONARY:
		return
	var data: Dictionary = payload
	if data.has("score"):
		set_score(int(data["score"]))
	if data.has("combo"):
		set_combo(int(data["combo"]))
	if data.has("progress"):
		set_progress(float(data["progress"]))
	if data.has("bpm"):
		set_bpm(float(data["bpm"]))
	if data.has("beat_pulse"):
		var pulse := float(data["beat_pulse"])
		if pulse >= 0.65 and not _pulse_latched:
			_on_rhythm_signal(pulse)
		_pulse_latched = pulse >= 0.65
	if data.has("judgement"):
		var kind := str(data["judgement"])
		if kind != "" and kind != _judgement_seen:
			_judgement_seen = kind
			_on_rhythm_signal(kind)
		elif kind == "":
			_judgement_seen = ""
	if data.has("rhythm"):
		pulse_rhythm(data["rhythm"])


func _draw_rhythm() -> void:
	if not is_node_ready():
		return
	var bpm := _bpm()
	var beat := 60.0 / maxf(bpm, 1.0)
	var latency := float(SaveManager.get_audio_latency_ms()) / 1000.0
	var phase := fposmod(_time - latency, beat) / beat
	var width := maxf(%RhythmTrack.size.x - %Marker.size.x, 0.0)
	%Marker.position.x = phase * width
	var on_beat := phase < 0.08 or phase > 0.92
	if _hint_life > 0.0 and _external_rhythm:
		%RhythmHint.text = _hint_text
		return
	%Marker.color = UiPalette.MAGENTA if on_beat else UiPalette.CYAN
	%RhythmHint.text = "RELEASE" if on_beat else "HOLD"


func _bpm() -> float:
	if _bpm_override > 1.0:
		return _bpm_override
	var main := get_tree().root.get_node_or_null("Main") if get_tree() else null
	if main and main.has_method("get_race_request"):
		var request: Dictionary = main.get_race_request()
		if str(request.get("mode", "")) == "custom" and float(request.get("bpm", 0.0)) > 1.0:
			return float(request["bpm"])
	var race := _find_race()
	if race and race.has_method("current_level_id"):
		var level_id := str(race.call("current_level_id"))
		if GameData.has_level(level_id):
			return float(GameData.get_level(level_id).get("bpm", 120))
	return 120.0


func _find_race() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for group_name in ["race_world", "apex_race"]:
		var grouped := tree.get_first_node_in_group(group_name)
		if grouped and not grouped.is_queued_for_deletion():
			return grouped
	var main := tree.root.get_node_or_null("Main")
	if main == null:
		return null
	var host := main.get_node_or_null("Host")
	if host and host.get_child_count() > 0:
		var child := host.get_child(0)
		if child and not child.is_queued_for_deletion():
			return child
	return null


func _call(node: Node, method: String):
	if node == null or not node.has_method(method):
		return null
	return node.call(method)


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
