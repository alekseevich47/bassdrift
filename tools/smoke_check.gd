extends Node

## Headless foundation check. Run with: godot --headless --path . -- --smoke


func _ready() -> void:
	var errors := _sync_checks()
	var ad_error := await _ad_checks()
	if not ad_error.is_empty():
		errors.append(ad_error)
	if errors.is_empty():
		print("SMOKE OK")
		get_tree().quit(0)
		return
	for entry in errors:
		push_error("SMOKE: %s" % entry)
	get_tree().quit(1)


func _sync_checks() -> PackedStringArray:
	var errors: PackedStringArray = []
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 720, "viewport width", errors)
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 1280, "viewport height", errors)
	_expect(str(ProjectSettings.get_setting("display/window/stretch/mode")) == "canvas_items", "stretch mode", errors)
	_expect(str(ProjectSettings.get_setting("display/window/stretch/aspect")) == "expand", "stretch aspect", errors)
	_expect(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == 1, "portrait orientation", errors)
	_expect(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "mobile", "mobile renderer", errors)
	_expect(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/Main.tscn", "main scene", errors)
	for autoload_name in ["SaveManager", "AudioAnalyzer", "GameData", "AdMonetizationStub"]:
		_expect(get_node_or_null("/root/" + autoload_name) != null, "autoload %s" % autoload_name, errors)
	var catalog := GameData.validate_catalog()
	for problem in catalog:
		errors.append("catalog: %s" % problem)
	_expect(GameData.car_ids().size() == 4, "4 cars", errors)
	_expect(str(GameData.get_car(GameData.CAR_STREET_86).get("name")) == "Street 86", "Street 86", errors)
	_expect(str(GameData.get_car(GameData.CAR_SILVIA).get("name")) == "Silvia S-Spec", "Silvia", errors)
	_expect(str(GameData.get_car(GameData.CAR_GTR).get("name")) == "GT-R Skyline", "GT-R", errors)
	_expect(str(GameData.get_car(GameData.CAR_HYPERION).get("name")) == "Apex Hyperion", "Hyperion", errors)
	_expect(GameData.upgrade_ids() == ["drift_angle", "turbo_boost", "armor", "magnet"], "upgrade ids", errors)
	_expect(GameData.perk_ids() == ["beat_window", "combo_keeper", "cash_flow", "focus_slowmo"], "perk ids", errors)
	_expect(GameData.MAX_UPGRADE_LEVEL == 5 and GameData.MAX_PERK_LEVEL == 5, "level caps", errors)
	_expect(GameData.MAX_PILOT_LEVEL == 50, "pilot cap", errors)
	_expect(SaveManager.MAX_PILOT_LEVEL == GameData.MAX_PILOT_LEVEL, "save pilot cap", errors)
	_expect(SaveManager.MAX_UPGRADE_LEVEL == GameData.MAX_UPGRADE_LEVEL, "save upgrade cap", errors)
	_expect(SaveManager.GRAPHICS_QUALITIES == GameData.GRAPHICS_QUALITIES, "graphics list", errors)
	_expect(SaveManager.DIFFICULTIES == GameData.difficulty_ids(), "difficulty list", errors)
	_expect(SaveManager.PAINT_STYLES == GameData.paint_ids(), "paint list", errors)
	var rank_names: Array = []
	for rank in GameData.ranks():
		rank_names.append(rank["name"])
	_expect(rank_names == ["Novice", "Street Racer", "Touge King", "Apex Legend"], "ranks", errors)
	_expect(GameData.get_chapter("haruna").get("bpm_min") == 115 and GameData.get_chapter("haruna").get("bpm_max") == 125, "haruna bpm", errors)
	_expect(GameData.get_chapter("shuto").get("bpm_min") == 130 and GameData.get_chapter("shuto").get("bpm_max") == 140, "shuto bpm", errors)
	_expect(GameData.get_chapter("docklands").get("bpm_min") == 145 and GameData.get_chapter("docklands").get("bpm_max") == 155, "docklands bpm", errors)
	_expect(GameData.get_chapter("apex").get("bpm_min") == 160 and GameData.get_chapter("apex").get("bpm_max") == 175, "apex bpm", errors)
	_expect(GameData.stars_for_score("haruna_01", 20000) == 3, "three stars", errors)
	_expect(GameData.stars_for_score("haruna_01", 5000) == 1, "one star", errors)
	_expect(GameData.timing_window_ms(0, "drive") == 90.0, "base window", errors)
	var migrated := SaveManager.migrate({
		"version": 1,
		"cr": 42,
		"pilot": {"xp": 10, "level": 2, "skill_points": 1},
		"owned_cars": ["street_86", "silvia_s_spec"],
		"selected_car": "silvia_s_spec",
		"upgrades": {"street_86": {"drift_angle": 2}},
		"perks": {"beat_window": 1},
		"stars": {"haruna_01": 3},
		"settings": {"music": 0.5, "sfx": 0.25},
		"tutorial_seen": true,
	})
	_expect(int(migrated["version"]) == 2, "migrated version", errors)
	_expect(int(migrated["currency"]["cr"]) == 42, "migrated cr", errors)
	_expect(int(migrated["campaign"]["stars"]["haruna_01"]) == 3, "migrated stars", errors)
	_expect(is_equal_approx(float(migrated["settings"]["music_volume"]), 0.5), "migrated music", errors)
	_expect(int(migrated["settings"]["audio_latency_ms"]) == 0, "migrated latency", errors)
	_expect(str(migrated["settings"]["graphics_quality"]) == "medium", "migrated graphics", errors)
	_expect(int(migrated["upgrades"]["street_86"]["drift_angle"]) == 2, "migrated upgrade", errors)
	_expect(str(migrated["difficulty"]) == "drive", "migrated difficulty", errors)
	_expect((migrated["paint"]["owned_styles"] as Array).has("gloss"), "migrated gloss", errors)
	_expect(bool(migrated["tutorial_seen"]), "migrated tutorial", errors)

	SaveManager.reset_save()
	_expect(SaveManager.get_cr() == 0, "reset cr", errors)
	_expect(SaveManager.get_pilot_level() == 1, "reset level", errors)
	_expect(not SaveManager.has_seen_tutorial(), "reset tutorial", errors)
	_expect(SaveManager.add_cr(80, "smoke") == 80, "add cr", errors)
	_expect(not SaveManager.spend_cr(81, "too much"), "overspend", errors)
	_expect(SaveManager.spend_cr(30, "spent"), "spend cr", errors)
	_expect(SaveManager.get_cr() == 50, "cr balance", errors)
	var broke := SaveManager.try_upgrade("street_86", "drift_angle")
	_expect(not bool(broke.get("ok", true)) and str(broke.get("reason")) == "not_enough_cr", "upgrade blocked", errors)
	SaveManager.add_cr(5000, "fund")
	var bought := SaveManager.try_upgrade("street_86", "drift_angle")
	_expect(bool(bought.get("ok", false)) and int(bought.get("level", 0)) == 1, "upgrade bought", errors)
	_expect(SaveManager.get_upgrade_level("street_86", "drift_angle") == 1, "upgrade stored", errors)
	var xp_result := SaveManager.add_xp(GameData.xp_to_next(1), "level")
	_expect(int(xp_result.get("levels_gained", 0)) == 1, "level up", errors)
	_expect(SaveManager.get_skill_points() >= 1, "skill point", errors)
	var perk := SaveManager.try_upgrade_perk("beat_window")
	_expect(bool(perk.get("ok", false)) and int(perk.get("level", 0)) == 1, "perk bought", errors)
	var clear := SaveManager.record_level_result("haruna_01", 20000)
	_expect(bool(clear.get("ok", false)) and int(clear.get("best_stars", 0)) == 3, "haruna clear", errors)
	var second := SaveManager.record_level_result("haruna_02", 25000)
	_expect(bool(second.get("ok", false)), "haruna 2", errors)
	_expect(SaveManager.get_total_stars() == 6, "six stars", errors)
	var locked := SaveManager.record_level_result("apex_04", 999999)
	_expect(str(locked.get("reason", "")) == "locked", "finale locked", errors)
	SaveManager.add_cr(20000, "garage")
	var car := SaveManager.try_purchase_car("silvia_s_spec")
	_expect(bool(car.get("ok", false)), "buy silvia: %s" % str(car.get("reason", "")), errors)
	_expect(SaveManager.get_selected_car() == "silvia_s_spec", "selected silvia", errors)
	var paint := SaveManager.try_purchase_paint("chameleon")
	_expect(bool(paint.get("ok", false)), "buy chameleon", errors)
	var painted := SaveManager.set_car_paint("silvia_s_spec", "chameleon", Color("#112233"), Color("#445566"), Color("#778899"))
	_expect(bool(painted.get("ok", false)), "apply paint", errors)
	_expect(str(SaveManager.get_paint("silvia_s_spec").get("style")) == "chameleon", "paint style", errors)
	_expect(SaveManager.set_audio_latency_ms(900) == 250, "latency high", errors)
	_expect(SaveManager.set_audio_latency_ms(-900) == -250, "latency low", errors)
	_expect(not SaveManager.set_graphics_quality("ultra"), "reject graphics", errors)
	_expect(SaveManager.set_graphics_quality("high"), "set graphics", errors)
	_expect(SaveManager.set_difficulty("hardcore"), "set hardcore", errors)
	_expect(not SaveManager.set_difficulty("sleep"), "reject difficulty", errors)
	SaveManager.set_tutorial_seen(true)
	_expect(SaveManager.has_seen_tutorial(), "tutorial seen", errors)
	_expect(FileAccess.file_exists(SaveManager.get_backup_path()), "backup exists", errors)
	var snapshot := SaveManager.get_cr()
	_expect(snapshot > 0, "cr before corrupt", errors)
	_expect(SaveManager.add_cr(7, "backup-probe") == snapshot + 7, "backup probe", errors)
	var corrupt := FileAccess.open(SaveManager.get_save_path(), FileAccess.WRITE)
	if corrupt == null:
		errors.append("could not open save for corrupt test")
	else:
		corrupt.store_string("{not-json")
		corrupt.close()
		_expect(SaveManager.load_save(), "reload after corrupt", errors)
		_expect(SaveManager.recovered_from_backup, "recovered backup", errors)
		_expect(SaveManager.get_cr() == snapshot, "backup restored previous CR", errors)

	var tone_path := "user://smoke_tone.wav"
	var tone := FileAccess.open(tone_path, FileAccess.WRITE)
	if tone == null:
		errors.append("could not write wav")
	else:
		tone.store_buffer(_wav_bytes(_tone_pcm(22050), 22050, 1))
		tone.close()
		var loaded := AudioAnalyzer.load_user_audio(tone_path)
		_expect(bool(loaded.get("ok", false)), "wav load %s" % str(loaded.get("error", "")), errors)
		_expect(abs(float(loaded.get("duration_sec", 0.0)) - 1.0) < 0.05, "wav duration", errors)
		var analyzed := AudioAnalyzer.analyze_to_beat_map()
		_expect(bool(analyzed.get("ok", false)) and (analyzed.get("beats", []) as Array).size() > 0, "analyze beats", errors)
		var missing := AudioAnalyzer.load_user_audio("user://missing-track.ogg")
		_expect(not bool(missing.get("ok", true)), "missing audio", errors)
	for style in ["haruna_dry_night", "shuto_rain", "docklands_fog", "apex_storm", "haruna_03"]:
		var chart := AudioAnalyzer.generate_campaign_track(style)
		_expect(bool(chart.get("ok", false)), "chart %s" % style, errors)
		_expect((chart.get("beats", []) as Array).size() > 8, "chart beats %s" % style, errors)
		var again := AudioAnalyzer.generate_campaign_track(style)
		_expect(str(again.get("beats")) == str(chart.get("beats")), "chart stable %s" % style, errors)
	var unknown := AudioAnalyzer.generate_campaign_track("not_a_style")
	_expect(not bool(unknown.get("ok", true)) and str(unknown.get("error")) == "unknown_style", "unknown style", errors)
	var first_beat: Dictionary = (AudioAnalyzer.generate_campaign_track("haruna_01").get("beats", [{}]) as Array)[0]
	_expect(first_beat.has("t") and first_beat.has("lane") and first_beat.has("kind"), "beat fields", errors)

	var main := get_parent()
	main.show_race("haruna_01")
	_expect(main.current_scene_name() == "race", "show race", errors)
	var race := main.get_node("Host").get_child(0)
	_expect(race.name == "RaceWorld" and race.current_level_id() == "haruna_01", "race level", errors)
	main.show_menu()
	_expect(main.current_scene_name() == "menu", "show menu", errors)
	_expect(main.get_node("Host").get_child(0).name == "MainMenu", "menu node", errors)
	_expect(str(main.get_node("Host/MainMenu/Margin/Layout/Title").text) == "APEX BEAT", "title", errors)

	var pause_scene := load("res://scenes/overlays/PauseOverlay.tscn") as PackedScene
	_expect(pause_scene != null, "pause scene", errors)
	if pause_scene != null:
		var pause := pause_scene.instantiate()
		add_child(pause)
		var resumed := {"ok": false}
		pause.resume_requested.connect(func() -> void: resumed["ok"] = true)
		(pause.get_node("Panel/ResumeButton") as Button).pressed.emit()
		_expect(bool(resumed["ok"]), "pause resume", errors)
		pause.queue_free()

	SaveManager.reset_save()
	var climb := 0
	var climb_level := 1
	while climb_level < 31:
		climb += GameData.xp_to_next(climb_level)
		climb_level += 1
	var climbed: Dictionary = SaveManager.add_xp(climb, "past-thirty")
	_expect(int(climbed.get("level", 0)) == 31, "pilot passes 30", errors)
	_expect(SaveManager.get_pilot_level() == 31, "pilot level 31", errors)
	var to_cap := 0
	climb_level = SaveManager.get_pilot_level()
	while climb_level < GameData.MAX_PILOT_LEVEL:
		to_cap += GameData.xp_to_next(climb_level)
		climb_level += 1
	var capped: Dictionary = SaveManager.add_xp(to_cap + 5000, "pilot-cap")
	_expect(int(capped.get("level", 0)) == 50, "pilot caps at 50", errors)
	_expect(SaveManager.get_pilot_level() == 50, "pilot level 50", errors)
	_expect(SaveManager.get_pilot_xp() == 0, "xp cleared at cap", errors)
	var high: Dictionary = SaveManager.migrate({
		"version": 2,
		"pilot": {"level": 80, "xp": 40, "skill_points": 4},
		"currency": {"cr": 12},
		"owned_cars": ["street_86"],
		"selected_car": "street_86",
		"tutorial_seen": true,
	})
	_expect(int(high["pilot"]["level"]) == 50, "normalize clamps pilot", errors)
	_expect(int(high["pilot"]["xp"]) == 0, "normalize clears overflow xp", errors)
	_expect(int(high["pilot"]["skill_points"]) == 4, "clamp keeps skill points", errors)
	_expect(int(high["currency"]["cr"]) == 12, "clamp keeps cr", errors)
	_expect(bool(high.get("driving_tutorial_done", true)) == false, "coach flag default", errors)
	_expect(bool(high.get("tutorial_seen", false)), "clamp keeps tutorial", errors)
	return errors


func _ad_checks() -> String:
	AdMonetizationStub.editor_delay_sec = 0.05
	AdMonetizationStub.export_delay_sec = 0.05
	AdMonetizationStub.simulate_success = true
	AdMonetizationStub.ads_enabled = true
	var state := {"first": null, "blocked": null, "revive": null, "doubled": null, "failed": null}
	if not AdMonetizationStub.show_rewarded_ad(func(success: bool) -> void:
		state["first"] = success
	):
		return "rewarded did not open"
	var second: bool = AdMonetizationStub.show_rewarded_ad(func(success: bool) -> void:
		state["blocked"] = success
	)
	if second or state["blocked"] == null or bool(state["blocked"]):
		return "busy rewarded ad should fail closed"
	if not await _wait_key(state, "first") or not bool(state["first"]):
		return "rewarded ad did not succeed"
	if not AdMonetizationStub.show_revive_ad(func(success: bool) -> void:
		state["revive"] = success
	):
		return "revive did not open"
	if not await _wait_key(state, "revive") or not bool(state["revive"]):
		return "revive did not succeed"
	var before := SaveManager.get_cr()
	if not AdMonetizationStub.show_double_reward_ad(40, func(success: bool, bonus: int) -> void:
		state["doubled"] = [success, bonus]
	):
		return "x2 did not open"
	if not await _wait_key(state, "doubled"):
		return "x2 timed out"
	var doubled: Array = state["doubled"]
	if doubled.size() != 2 or not bool(doubled[0]) or int(doubled[1]) != 40:
		return "x2 callback mismatch"
	if SaveManager.get_cr() != before + 40:
		return "x2 did not grant CR"
	AdMonetizationStub.simulate_success = false
	if not AdMonetizationStub.show_rewarded_ad(func(success: bool) -> void:
		state["failed"] = success
	):
		return "failure path did not open"
	if not await _wait_key(state, "failed") or bool(state["failed"]):
		return "simulate_success false still rewarded"
	AdMonetizationStub.simulate_success = true
	return ""


func _wait_key(bucket: Dictionary, key: String) -> bool:
	var frames := 0
	while bucket[key] == null and frames < 240:
		await get_tree().process_frame
		frames += 1
	return bucket[key] != null


func _expect(condition: bool, label: String, errors: PackedStringArray) -> void:
	if not condition:
		errors.append(label)


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
