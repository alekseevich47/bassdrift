extends SceneTree

## Headless gameplay check. godot --headless --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tools/gameplay_check.gd


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var errors: PackedStringArray = []
	var save = root.get_node("SaveManager")
	var audio = root.get_node("AudioAnalyzer")
	_expect(root.get_node_or_null("GameData") != null, "gamedata", errors)
	save.reset_save()
	save.set_difficulty("drive")
	save.set_tutorial_seen(true)
	for style in ["haruna_dry_night", "shuto_rain", "docklands_fog", "apex_storm", "haruna_01", "apex_04"]:
		var chart = audio.generate_campaign_track(style)
		_expect(bool(chart.get("ok", false)), "chart %s" % style, errors)
		var beats: Array = chart.get("beats", [])
		_expect(beats.size() > 8, "beats %s" % style, errors)
		if not beats.is_empty():
			var first: Dictionary = beats[0]
			_expect(first.has("t") and first.has("lane") and first.has("kind") and first.has("dur"), "fields %s" % style, errors)
		var again = audio.generate_campaign_track(style)
		_expect(str(again.get("beats")) == str(chart.get("beats")), "stable %s" % style, errors)
		var road_tool = load("res://scripts/track/RealisticRoadGenerator.gd").new()
		var speed := 460.0
		var road = road_tool.generate(chart, speed)
		_expect(bool(road.get("ok", false)) and float(road.get("length", 0.0)) > 500.0, "road %s" % style, errors)
		var spacing = road_tool.apex_spacing_error(road)
		_expect(spacing < 0.18, "spacing %s %.3f" % [style, spacing], errors)
	var broken := FileAccess.open("user://broken.wav", FileAccess.WRITE)
	if broken != null:
		broken.store_string("not a wav")
		broken.close()
		var bad = audio.load_user_audio("user://broken.wav")
		_expect(not bool(bad.get("ok", true)), "broken wav", errors)
	var missing = audio.load_user_audio("user://no-such-track.ogg")
	_expect(not bool(missing.get("ok", true)), "missing", errors)
	var empty = audio.load_user_audio("")
	_expect(not bool(empty.get("ok", true)), "empty path", errors)
	var generator = audio.begin_campaign_performance(audio.generate_campaign_track("haruna_01"))
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	player.stream = generator
	player.play()
	var playback := player.get_stream_playback()
	if playback is AudioStreamGeneratorPlayback:
		audio.render_campaign(playback)
		_expect(playback.get_frames_available() < 22050, "synth filled", errors)
	else:
		errors.append("no generator playback")
	player.queue_free()
	audio.end_campaign_performance()
	for diff in ["chill", "drive", "hardcore"]:
		save.set_difficulty(diff)
		var mods = audio.difficulty_modifiers()
		_expect(str(mods.get("id", "")) == diff, "diff %s" % diff, errors)
	save.set_difficulty("drive")
	save.set_tutorial_seen(false)
	var race_scene := load("res://scenes/RaceWorld.tscn") as PackedScene
	_expect(race_scene != null, "race scene", errors)
	if race_scene != null:
		var race := race_scene.instantiate()
		root.add_child(race)
		race.configure("haruna_01")
		_expect(race.current_level_id() == "haruna_01", "level id", errors)
		_expect(race.is_tutorial_active(), "tutorial", errors)
		_expect(race.has_signal("hud_state_changed") and race.has_signal("race_finished") and race.has_signal("exit_requested"), "signals", errors)
		race.set_holding(true)
		for _i in 40:
			await process_frame
		_expect(float(race.get_progress()) > 0.0 or float(race.get_time()) > 0.0, "race advanced", errors)
		_expect(float(race.get_hp()) > 0.0, "hp", errors)
		var image := root.get_viewport().get_texture().get_image()
		if image != null and image.get_width() > 0:
			image.save_png("/tmp/apex_race.png")
		race.queue_free()
	if errors.is_empty():
		print("GAMEPLAY OK")
		quit(0)
		return
	for entry in errors:
		push_error("GAMEPLAY: %s" % entry)
	quit(1)


func _expect(condition: bool, label: String, errors: PackedStringArray) -> void:
	if not condition:
		errors.append(label)
