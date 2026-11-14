extends Node

## UI pass over the menu, garage, pilot, campaign, settings, HUD, and results.
## godot --headless --path . --rendering-driver opengl3 --rendering-method gl_compatibility -- --ui-smoke


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var errors: PackedStringArray = []
	var main := get_parent()
	SaveManager.reset_save()
	SaveManager.set_tutorial_seen(true)
	main.show_menu()
	_expect(main.current_scene_name() == "menu", "menu boot", errors)
	var menu := main.get_node("Host/MainMenu")
	_expect(str(menu.get_node("Margin/Layout/Title").text) == "APEX BEAT", "hero title", errors)
	_expect(str(menu.get_node("Margin/Layout/Stage/CarName").text) == "Street 86", "hero car", errors)
	menu.open_campaign()
	var campaign := _living(menu.get_node("ScreenHost"))
	_expect(campaign != null, "campaign open", errors)
	if campaign != null:
		var levels := _with_meta(campaign, "level_id")
		var chapters := _with_meta(campaign, "chapter_id")
		_expect(levels.size() == 16, "16 levels", errors)
		_expect(chapters.size() == 4, "4 chapters", errors)
		var haruna_open := false
		var shuto_locked := false
		for chapter in chapters:
			if str(chapter.get_meta("chapter_id")) == "haruna":
				haruna_open = bool(chapter.get_meta("unlocked"))
			if str(chapter.get_meta("chapter_id")) == "shuto":
				shuto_locked = not bool(chapter.get_meta("unlocked"))
		_expect(haruna_open, "haruna open", errors)
		_expect(shuto_locked, "shuto locked", errors)
		for level in levels:
			if str(level.get_meta("level_id")) == "haruna_02":
				_expect(level.disabled, "haruna 2 locked", errors)
			if str(level.get_meta("level_id")) == "haruna_01":
				_expect(not level.disabled, "haruna 1 open", errors)
	_expect(menu.handle_back(), "campaign back", errors)
	_expect(menu.get_node("Margin").visible, "home visible", errors)
	menu.open_garage()
	var garage := _living(menu.get_node("ScreenHost"))
	_expect(garage != null, "garage open", errors)
	if garage != null:
		var cars := _with_meta(garage, "car_id")
		_expect(cars.size() == 4, "4 car buttons", errors)
		for car in cars:
			if str(car.get_meta("car_id")) == "silvia_s_spec":
				car.pressed.emit()
		var action := garage.find_child("ActionButton", true, false) as Button
		_expect(action != null and action.disabled, "silvia locked out", errors)
		var upgrades := _with_meta(garage, "upgrade_id")
		_expect(upgrades.size() == 4, "4 upgrades", errors)
	menu.open_pilot()
	var pilot := _living(menu.get_node("ScreenHost"))
	_expect(pilot != null, "pilot open", errors)
	if pilot != null:
		var perks := _with_meta(pilot, "perk_id")
		_expect(perks.size() == 4, "4 perks", errors)
		for perk in perks:
			_expect(perk.disabled, "perks locked at 0 sp", errors)
		SaveManager.add_xp(GameData.xp_to_next(1), "ui-smoke")
		await get_tree().process_frame
		var beat: Button = null
		for perk in perks:
			if str(perk.get_meta("perk_id")) == "beat_window":
				beat = perk
		_expect(beat != null and not beat.disabled, "perk affordable", errors)
		if beat != null:
			beat.pressed.emit()
		_expect(SaveManager.get_perk_level("beat_window") == 1, "perk spent", errors)
		_expect(str(pilot.find_child("LevelLabel", true, false).text).begins_with("LV "), "level label", errors)
	menu.open_settings()
	var settings := _living(menu.get_node("ScreenHost"))
	_expect(settings != null, "settings open", errors)
	if settings != null:
		var latency := settings.find_child("LatencySlider", true, false) as HSlider
		var music := settings.find_child("MusicSlider", true, false) as HSlider
		var high := settings.find_child("HighButton", true, false) as Button
		_expect(latency != null and music != null and high != null, "settings controls", errors)
		if latency != null:
			latency.value = 125
		if music != null:
			music.value = 40
		if high != null:
			high.pressed.emit()
		_expect(SaveManager.get_audio_latency_ms() == 125, "latency saved", errors)
		_expect(is_equal_approx(SaveManager.get_music_volume(), 0.4), "music saved", errors)
		_expect(SaveManager.get_graphics_quality() == "high", "graphics saved", errors)
		var tips := settings.find_child("TipsButton", true, false) as Button
		_expect(tips != null, "tips button", errors)
	menu.open_custom()
	var custom := _living(menu.get_node("ScreenHost"))
	_expect(custom != null, "custom open", errors)
	if custom != null:
		var start := custom.find_child("StartButton", true, false) as Button
		_expect(start != null and start.disabled, "custom start locked", errors)
		var tone_path := "user://ui_smoke_tone.wav"
		var tone := FileAccess.open(tone_path, FileAccess.WRITE)
		if tone == null:
			errors.append("wav write")
		else:
			tone.store_buffer(_wav_bytes(_tone_pcm(22050), 22050, 1))
			tone.close()
			custom._on_file_selected(tone_path)
			_expect(not start.disabled, "custom start ready", errors)
			_expect(str(custom.find_child("Preview", true, false).text).contains("BPM"), "bpm preview", errors)
		custom._on_file_selected("user://missing-track.ogg")
		_expect(start.disabled, "bad file locks start", errors)
		var preview := str(custom.find_child("Preview", true, false).text)
		_expect(preview.contains("isn't there") or preview.contains("Pick"), "friendly missing file", errors)
	if not errors.is_empty():
		_fail(errors)
		return
	var level_button: Button = null
	menu.open_campaign()
	campaign = _living(menu.get_node("ScreenHost"))
	for level in _with_meta(campaign, "level_id"):
		if str(level.get_meta("level_id")) == "haruna_01":
			level_button = level
	_expect(level_button != null, "haruna button", errors)
	if level_button != null:
		level_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(main.current_scene_name() == "race", "campaign race", errors)
	var race := main.get_node("Host").get_child(0)
	_expect(race.current_level_id() == "haruna_01", "campaign level id", errors)
	var hud := _living(main.get_node("OverlayHost"))
	_expect(hud != null and hud.name == "RaceHUD", "hud mounted", errors)
	if hud != null:
		hud.set_score(1500)
		hud.set_combo(3)
		hud.set_progress(0.4)
		_expect(str(hud.find_child("Score", true, false).text) == "1,500", "hud score", errors)
		_expect(str(hud.find_child("Combo", true, false).text).contains("x3"), "hud combo", errors)
		_expect(str(hud.find_child("ProgressLabel", true, false).text) == "40%", "hud progress", errors)
		hud.find_child("PauseButton", true, false).pressed.emit()
	_expect(get_tree().paused, "paused", errors)
	var pause := _overlay(main, "PauseMenu")
	_expect(pause != null, "pause menu", errors)
	if pause != null:
		pause.find_child("ResumeButton", true, false).pressed.emit()
	_expect(not get_tree().paused, "resumed", errors)
	AdMonetizationStub.editor_delay_sec = 0.05
	AdMonetizationStub.export_delay_sec = 0.05
	AdMonetizationStub.simulate_success = true
	AdMonetizationStub.ads_enabled = true
	var before := SaveManager.get_cr()
	main.show_results({
		"level_id": "haruna_01",
		"score": 20000,
		"stars": 3,
		"best_score": 20000,
		"star_delta": 1,
		"cr_gain": 100,
		"xp_gain": 80,
		"crashed": true,
		"can_revive": true,
		"xp_result": {"levels_gained": 1, "level": 3, "skill_points_gained": 1},
	})
	_expect(get_tree().paused, "results pause", errors)
	await get_tree().create_timer(1.05, true, false, true).timeout
	var results := _overlay(main, "ResultScreen")
	_expect(results != null, "results", errors)
	if results != null:
		_expect(str(results.find_child("Score", true, false).text) == "20,000", "score count", errors)
		_expect(str(results.find_child("Star1", true, false).text) == "★", "star filled", errors)
		_expect(str(results.find_child("Heading", true, false).text) == "Touge Gate", "result name", errors)
		results.find_child("DoubleButton", true, false).pressed.emit()
		await get_tree().create_timer(0.4, true, false, true).timeout
		_expect(SaveManager.get_cr() == before + 100, "double cr", errors)
		results = _overlay(main, "ResultScreen")
		if results != null:
			results.find_child("ReviveButton", true, false).pressed.emit()
			await get_tree().create_timer(0.4, true, false, true).timeout
	_expect(not get_tree().paused, "revived unpauses", errors)
	_expect(_overlay(main, "ResultScreen") == null, "results closed", errors)
	_expect(race.has_meta("apex_revive_token"), "revive token", errors)
	main.show_custom_race({
		"audio_path": "user://ui_smoke_tone.wav",
		"display_name": "ui_smoke_tone.wav",
		"bpm": 140,
		"difficulty": "hardcore",
	})
	race = main.get_node("Host").get_child(0)
	var request: Dictionary = race.get_meta("apex_race_request")
	_expect(str(request.get("mode", "")) == "custom", "custom mode", errors)
	_expect(is_equal_approx(float(request.get("bpm", 0.0)), 140.0), "custom bpm", errors)
	_expect(str(main.get_race_request().get("difficulty", "")) == "hardcore", "custom difficulty", errors)
	SaveManager.set_tutorial_seen(false)
	main.show_menu()
	await get_tree().process_frame
	var tip := _overlay(main, "TutorialOverlay")
	_expect(tip != null, "tutorial", errors)
	_expect(not SaveManager.has_seen_tutorial(), "tutorial not seen yet", errors)
	if tip != null:
		tip.find_child("OkButton", true, false).pressed.emit()
	_expect(SaveManager.has_seen_tutorial(), "tutorial saved", errors)
	if errors.is_empty():
		print("UI SMOKE OK")
		get_tree().quit(0)
		return
	_fail(errors)


func _fail(errors: PackedStringArray) -> void:
	for entry in errors:
		push_error("UI SMOKE: %s" % entry)
	get_tree().quit(1)


func _expect(condition: bool, label: String, errors: PackedStringArray) -> void:
	if not condition:
		errors.append(label)


func _living(host: Node) -> Node:
	if host == null:
		return null
	for child in host.get_children():
		if not child.is_queued_for_deletion():
			return child
	return null


func _overlay(main: Node, node_name: String) -> Node:
	var host := main.get_node_or_null("OverlayHost")
	if host == null:
		return null
	for child in host.get_children():
		if child.name == node_name and not child.is_queued_for_deletion():
			return child
	return null


func _with_meta(root: Node, key: String) -> Array:
	var found: Array = []
	_walk(root, key, found)
	return found


func _walk(node: Node, key: String, found: Array) -> void:
	if node.has_meta(key):
		found.append(node)
	for child in node.get_children():
		_walk(child, key, found)


func _tone_pcm(sample_rate: int) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(sample_rate * 2)
	for i in sample_rate:
		var sample := int(sin(float(i) / float(sample_rate) * TAU * 440.0) * 8000.0)
		pcm.encode_s16(i * 2, sample)
	return pcm


func _wav_bytes(pcm: PackedByteArray, sample_rate: int, channels: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_u32(36 + pcm.size()))
	out.append_array("WAVE".to_ascii_buffer())
	out.append_array("fmt ".to_ascii_buffer())
	out.append_array(_u32(16))
	out.append_array(_u16(1))
	out.append_array(_u16(channels))
	out.append_array(_u32(sample_rate))
	out.append_array(_u32(sample_rate * channels * 2))
	out.append_array(_u16(channels * 2))
	out.append_array(_u16(16))
	out.append_array("data".to_ascii_buffer())
	out.append_array(_u32(pcm.size()))
	out.append_array(pcm)
	return out


func _u16(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(2)
	bytes.encode_u16(0, value)
	return bytes


func _u32(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, value)
	return bytes
