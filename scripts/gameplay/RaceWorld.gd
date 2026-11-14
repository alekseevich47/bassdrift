extends Control

## Playable portrait race. Main.show_race() instantiates this scene and calls configure(level_id).
## hud_updated and hud_snapshot are omitted on purpose: Main skips its RaceHUD when either exists.
##
## hud_state_changed(state): score, combo, progress (0-1), hp (durability, not a ratio),
##   hp_max, beat_pulse (1 on the beat, decays to 0), speed, nominal_speed, perfects, goods,
##   misses, saves, coins, coin_cr, time, duration, level_id, level_name, holding, slip_deg,
##   finished, paused, judgement, bpm
## judgement_shown(kind, points, combo) — PERFECT, GOOD, SAVE, or MISS
## beat_pulse(intensity, beat_index)
## scrape_feedback(intensity)
## tutorial_changed(active, message)
## pause_requested — the router opens its pause menu
## race_failed(reason) — start error string such as file_missing or decode_failed
## race_finished(result): ok, reason (cleared|wrecked), crashed, wrecked, failed, can_revive,
##   level_id, level_name, score, stars, best_stars, best_score, star_delta, cr_gain, xp_gain,
##   xp_result, coin_cr, perfects, goods, misses, saves, max_combo, progress, duration, saved, payout
## exit_requested — quit back to the menu. Quit does not call SaveManager.
## Cleared and wrecked call record_level_result once. revive() continues a wreck.

signal exit_requested
signal hud_state_changed(state: Dictionary)
signal judgement_shown(kind: String, points: int, combo: int)
signal beat_pulse(intensity: float, beat_index: int)
signal race_finished(result: Dictionary)
signal race_failed(reason: String)
signal tutorial_changed(active: bool, message: String)
signal scrape_feedback(intensity: float)
signal pause_requested

const CAR_SCENE := preload("res://scenes/Car.tscn")
const ROAD_SCRIPT := preload("res://scripts/track/RealisticRoadGenerator.gd")
const SCENERY_SCRIPT := preload("res://scripts/track/ScenerySpawner.gd")
const WEATHER_SCRIPT := preload("res://scripts/gameplay/WeatherController.gd")
const CAMERA_SCRIPT := preload("res://scripts/gameplay/DriftCamera.gd")
const ASPHALT_SHADER := preload("res://shaders/realistic_asphalt.gdshader")
const RAIN_SHADER := preload("res://shaders/rain_particles.gdshader")
const VIGNETTE_SHADER := preload("res://shaders/speed_vignette.gdshader")
const PAUSE_SCENE := preload("res://scenes/overlays/PauseOverlay.tscn")
const TUTORIAL_TEXT := "Release drifts left. Hold drifts right. Clip the apex on the beat."

var _level_id := ""
var _configured := false
var _running := false
var _finished := false
var _paused := false
var _user_mode := false
var _tutorial := false
var _tutorial_s := -1.0
var _chart: Dictionary = {}
var _road: Dictionary = {}
var _apexes: Array = []
var _apex_index := 0
var _pulse_index := 0
var _s := 0.0
var _length := 1.0
var _half := 104.0
var _music_time := 0.0
var _music_pos := 0.0
var _score := 0
var _combo := 0
var _max_combo := 0
var _perfects := 0
var _goods := 0
var _misses := 0
var _saves := 0
var _coin_cr := 0
var _coins_taken := 0
var _coins: Array = []
var _beat_visual := 0.0
var _judgement := ""
var _judgement_time := -10.0
var _window_ms := 90.0
var _score_scale := 1.0
var _drift_mult := 1.0
var _keeper := 0
var _focus_sec := 0.0
var _focus_scale := 0.65
var _slowmo := 0.0
var _magnet_snap := 0.0
var _turbo_boost := 0.0
var _hold_until := -1.0
var _hold_dir := 0
var _hold_bonus := 0
var _miss_bank := 0
var _hud_timer := 0.0
var _campaign_audio := false
var _quality := "medium"

var _world: Node2D
var _track: Node2D
var _ground: Polygon2D
var _camera
var _car
var _weather
var _road_tool
var _curve: Curve2D
var _music: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _asphalt_mat: ShaderMaterial
var _rain_mat: ShaderMaterial
var _vignette_mat: ShaderMaterial
var _fog: ColorRect
var _flash: ColorRect
var _hud: Control
var _score_label: Label
var _combo_label: Label
var _level_label: Label
var _coin_label: Label
var _judge_label: Label
var _tutorial_label: Label
var _error_label: Label
var _hp_fill: ColorRect
var _progress_fill: ColorRect
var _pulse_bar: ColorRect
var _pause_button: Button
var _pause_layer: CanvasLayer
var _results: CanvasLayer
var _sfx_scrape: AudioStreamPlayer
var _sfx_perfect: AudioStreamPlayer
var _sfx_good: AudioStreamPlayer
var _sfx_coin: AudioStreamPlayer
var _mark_left: Line2D
var _mark_right: Line2D
var _marking := false
var _mark_groups: Array = []
var _banked := false
var _payout: Dictionary = {}


func _ready() -> void:
	add_to_group("race_world")
	add_to_group("apex_race")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_road_tool = ROAD_SCRIPT.new()
	_build_shell()
	call_deferred("_ensure_started")


func _notification(what: int) -> void:
	if _music == null:
		return
	if what == NOTIFICATION_PAUSED:
		_music.stream_paused = true
	elif what == NOTIFICATION_UNPAUSED and _running and not _finished:
		_music.stream_paused = false


func _exit_tree() -> void:
	_running = false
	if is_inside_tree() and get_tree().paused:
		get_tree().paused = false
	if _music != null:
		_music.stop()
	AudioAnalyzer.end_campaign_performance()


func configure(level_id: String) -> void:
	_configured = true
	var resolved := level_id
	if resolved.is_empty() or not GameData.has_level(resolved) or not SaveManager.is_level_unlocked(resolved):
		resolved = SaveManager.get_continue_level_id()
	_level_id = resolved
	_user_mode = false
	var chart := AudioAnalyzer.generate_campaign_track(resolved)
	if not bool(chart.get("ok", false)):
		_fail_start(str(chart.get("error", "chart_failed")))
		return
	_boot(chart, null, true)


func configure_user_audio(path: String = "") -> void:
	_configured = true
	_user_mode = true
	_level_id = "user"
	if not path.is_empty():
		var loaded := AudioAnalyzer.load_user_audio(path)
		if not bool(loaded.get("ok", false)):
			_fail_start(str(loaded.get("error", "load_failed")))
			return
	var chart := AudioAnalyzer.analyze_to_beat_map()
	if not bool(chart.get("ok", false)):
		_fail_start(str(chart.get("error", "analyze_failed")))
		return
	var stream := AudioAnalyzer.get_loaded_stream()
	_boot(chart, stream, stream == null)


func configure_beat_map(beat_map: Dictionary, stream: AudioStream = null) -> void:
	_configured = true
	_level_id = str(beat_map.get("level_id", "custom"))
	if _level_id.is_empty():
		_level_id = "custom"
	_user_mode = str(beat_map.get("source", "")) == "user"
	if not bool(beat_map.get("ok", false)):
		_fail_start(str(beat_map.get("error", "bad_chart")))
		return
	var play_stream := stream
	if play_stream == null and _user_mode:
		play_stream = AudioAnalyzer.get_loaded_stream()
	_boot(beat_map, play_stream, play_stream == null)


func current_level_id() -> String:
	return _level_id


func is_tutorial_active() -> bool:
	return _tutorial


func set_holding(held: bool) -> void:
	_set_hold(held)


func get_score() -> int:
	return _score


func get_combo() -> int:
	return _combo


func get_progress() -> float:
	return clampf(_s / maxf(_length, 1.0), 0.0, 1.0)


func get_bpm() -> float:
	return float(_chart.get("bpm", 120.0))


func get_time() -> float:
	return _music_time


func get_hp() -> float:
	if _car == null:
		return 0.0
	return float(_car.hp)


func revive() -> void:
	if _car == null:
		return
	_finished = false
	_running = true
	_paused = false
	_car.alive = true
	if float(_car.hp) <= 0.0:
		_car.hp = maxf(float(_car.max_hp) * 0.5, 1.0)
	_car.speed = maxf(float(_car.speed), float(_car.nominal_speed) * 0.85)
	if _music != null:
		_music.stream_paused = false
	_emit_hud()


func _telemetry() -> Dictionary:
	var hp := 0.0
	var hp_max := 1.0
	var speed := 0.0
	var nominal := 1.0
	var slip_deg := 0.0
	var holding := false
	if _car != null:
		hp = _car.hp
		hp_max = _car.max_hp
		speed = _car.speed
		nominal = _car.nominal_speed
		slip_deg = rad_to_deg(_car.slip)
		holding = _car.holding
	return {
		"score": _score,
		"combo": _combo,
		"progress": clampf(_s / max(_length, 1.0), 0.0, 1.0),
		"hp": hp,
		"hp_max": hp_max,
		"beat_pulse": _beat_visual,
		"speed": speed,
		"nominal_speed": nominal,
		"perfects": _perfects,
		"goods": _goods,
		"misses": _misses,
		"saves": _saves,
		"coins": _coins_taken,
		"coin_cr": _coin_cr,
		"time": _music_time,
		"duration": float(_chart.get("duration_sec", 0.0)),
		"level_id": _level_id,
		"level_name": str(_chart.get("display_name", _level_id)),
		"holding": holding,
		"slip_deg": slip_deg,
		"finished": _finished,
		"paused": _paused,
		"judgement": _judgement,
	}


func _ensure_started() -> void:
	if _configured:
		return
	configure("")


func _process(delta: float) -> void:
	if not _running or _paused or _finished or _car == null or _curve == null:
		return
	delta = min(delta, 0.05)
	var scale := _clock_scale(delta)
	if _music != null:
		_music.pitch_scale = scale
	if _campaign_audio and _playback != null:
		AudioAnalyzer.render_campaign(_playback)
	var music_dt := _advance_clock(delta, scale)
	if _weather != null:
		_weather.update(delta)
	_car.tick(music_dt, _steer_target())
	if not _car.alive:
		_finish("wrecked")
		return
	_s = min(_s + _car.speed * music_dt, _length)
	var frame: Dictionary = _road_tool.sample(_curve, _s)
	_place_car(frame)
	_camera.follow(_car.global_position, frame["forward"], music_dt, _car.speed / max(_car.nominal_speed, 1.0), _car.slip)
	_sync_ground()
	_lay_marks()
	_attract_coins(music_dt)
	_decay_hold()
	_pulse_beats()
	_judge_crossed()
	_update_tutorial()
	_beat_visual = max(_beat_visual - delta * 2.4, 0.0)
	_refresh_hud_widgets()
	_hud_timer += delta
	if _hud_timer >= 0.1:
		_hud_timer = 0.0
		_emit_hud()
	if _vignette_mat != null:
		_vignette_mat.set_shader_parameter("speed", clampf(_car.speed / max(_car.nominal_speed, 1.0), 0.0, 1.5))
	if _s >= _length - 4.0:
		_finish("cleared")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE and not event.echo:
		if _paused or _finished:
			return
		_set_hold((event as InputEventKey).pressed)
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if _ignore_pointer(touch.position):
			return
		_set_hold(touch.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mouse := event as InputEventMouseButton
		if _ignore_pointer(mouse.position):
			return
		_set_hold(mouse.pressed)
		get_viewport().set_input_as_handled()


func _build_shell() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_ground = Polygon2D.new()
	_ground.polygon = PackedVector2Array([
		Vector2(-2200, -2200), Vector2(2200, -2200), Vector2(2200, 2200), Vector2(-2200, 2200),
	])
	_ground.z_index = -40
	_ground.color = Color(0.05, 0.06, 0.05)
	_world.add_child(_ground)
	_camera = CAMERA_SCRIPT.new()
	_camera.name = "DriftCamera"
	_world.add_child(_camera)
	_camera.make_current()
	_asphalt_mat = ShaderMaterial.new()
	_asphalt_mat.shader = ASPHALT_SHADER
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = RAIN_SHADER
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = VIGNETTE_SHADER
	var fx := CanvasLayer.new()
	fx.layer = 6
	add_child(fx)
	_fog = ColorRect.new()
	_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.color = Color(0, 0, 0, 0)
	fx.add_child(_fog)
	var rain := ColorRect.new()
	rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rain.material = _rain_mat
	rain.color = Color(1, 1, 1, 1)
	fx.add_child(rain)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	fx.add_child(_flash)
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = _vignette_mat
	fx.add_child(vignette)
	_unlit(fx)
	_weather = WEATHER_SCRIPT.new()
	add_child(_weather)
	_weather.apply_preset("dry_night")
	_weather.bind(_asphalt_mat, _rain_mat, _vignette_mat, _fog, _flash)
	_build_hud()
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	if AudioServer.get_bus_index("Music") >= 0:
		_music.bus = "Music"
	add_child(_music)
	_sfx_scrape = _sfx_player(_noise_wav(90.0, 0.18, 0.7, 0.85))
	_sfx_perfect = _sfx_player(_noise_wav(660.0, 0.12, 0.45, 0.05))
	_sfx_good = _sfx_player(_noise_wav(440.0, 0.08, 0.32, 0.0))
	_sfx_coin = _sfx_player(_noise_wav(880.0, 0.06, 0.28, 0.0))


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_pulse_bar = ColorRect.new()
	_pulse_bar.offset_left = 28.0
	_pulse_bar.offset_top = 28.0
	_pulse_bar.offset_right = 692.0
	_pulse_bar.offset_bottom = 34.0
	_pulse_bar.color = UiPalette.MAGENTA
	_pulse_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_pulse_bar)
	_level_label = _label(28, 40, 480, 28, 16, UiPalette.MUTED)
	_score_label = _label(28, 68, 480, 52, 40, UiPalette.INK)
	_combo_label = _label(28, 122, 480, 28, 20, UiPalette.AMBER)
	_coin_label = _label(28, 150, 360, 24, 16, UiPalette.CYAN)
	_hp_fill = ColorRect.new()
	_hp_fill.offset_left = 28.0
	_hp_fill.offset_top = 182.0
	_hp_fill.offset_right = 220.0
	_hp_fill.offset_bottom = 194.0
	_hp_fill.color = UiPalette.MAGENTA
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hp_fill)
	var track := ColorRect.new()
	track.offset_left = 28.0
	track.offset_top = 204.0
	track.offset_right = 560.0
	track.offset_bottom = 212.0
	track.color = Color(1, 1, 1, 0.16)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.visible = false
	_hud.add_child(track)
	_progress_fill = ColorRect.new()
	_progress_fill.offset_left = 28.0
	_progress_fill.offset_top = 204.0
	_progress_fill.offset_right = 28.0
	_progress_fill.offset_bottom = 212.0
	_progress_fill.color = UiPalette.CYAN
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_progress_fill)
	_judge_label = _label(40, 520, 640, 72, 42, UiPalette.INK)
	_judge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_label = _label(40, 1080, 640, 90, 18, UiPalette.INK)
	_tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label = _label(48, 560, 624, 120, 22, UiPalette.AMBER)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	_pause_button = Button.new()
	_pause_button.text = "PAUSE"
	_pause_button.offset_left = 540.0
	_pause_button.offset_top = 56.0
	_pause_button.offset_right = 688.0
	_pause_button.offset_bottom = 112.0
	UiPalette.style_button(_pause_button, UiPalette.PIT, UiPalette.CYAN, 16)
	_pause_button.pressed.connect(func() -> void: pause_requested.emit())
	_pause_button.visible = false
	_hud.add_child(_pause_button)
	_score_label.visible = false
	_combo_label.visible = false
	_coin_label.visible = false
	_pulse_bar.visible = false
	_progress_fill.visible = false
	_hp_fill.offset_top = 1210.0
	_hp_fill.offset_bottom = 1224.0
	_unlit(layer)
	_score_label.text = "0"
	_combo_label.text = "COMBO 0"
	_coin_label.text = "0 CR"


func _boot(chart: Dictionary, stream: AudioStream, campaign: bool) -> void:
	_clear_track()
	_chart = chart
	_finished = false
	_error_label.visible = false
	_quality = SaveManager.get_graphics_quality()
	var profile := _car_profile(chart)
	var speed := float(profile["nominal_speed"])
	_road = _road_tool.generate(chart, speed)
	if not bool(_road.get("ok", false)):
		_fail_start("road_failed")
		return
	_curve = _road["curve"]
	_length = max(float(_road["length"]), 1.0)
	_half = float(_road["half_width"])
	_apexes = _road["apexes"]
	_weather.apply_preset(str(chart.get("weather", "dry_night")))
	var visual: Dictionary = _weather.palette()
	_ground.color = visual["ground"]
	_track = Node2D.new()
	_track.name = "Track"
	_world.add_child(_track)
	var shoulder := MeshInstance2D.new()
	shoulder.mesh = _road["shoulder_mesh"]
	shoulder.z_index = -2
	shoulder.modulate = Color(visual["ground"]).lightened(0.05)
	_track.add_child(shoulder)
	var asphalt := MeshInstance2D.new()
	asphalt.mesh = _road["road_mesh"]
	asphalt.material = _asphalt_mat
	asphalt.z_index = 0
	_track.add_child(asphalt)
	SCENERY_SCRIPT.new().populate(_track, _road, visual, _quality)
	_spawn_markers()
	_spawn_coins(int(profile["coin_value"]))
	_car = CAR_SCENE.instantiate()
	_track.add_child(_car)
	_car.configure(profile)
	_car.set_quality(_quality)
	_car.scraped.connect(_on_scrape)
	_car.wrecked.connect(_on_wreck)
	_camera.reset_follow()
	var origin_frame: Dictionary = _road_tool.sample(_curve, 0.0)
	_place_car(origin_frame)
	_camera.follow(_car.global_position, origin_frame["forward"], 0.0, 1.0, 0.0)
	_sync_ground()
	_reset_run_stats()
	_arm_tutorial()
	_level_label.text = str(chart.get("display_name", _level_id))
	_setup_audio(chart, stream, campaign)
	_running = true
	_emit_hud()


func _car_profile(chart: Dictionary) -> Dictionary:
	var car_id := SaveManager.get_selected_car()
	var car := GameData.get_car(car_id)
	var stats: Dictionary = car.get("stats", {})
	var diff_id := str(chart.get("difficulty", SaveManager.get_difficulty()))
	var diff := GameData.get_difficulty(diff_id)
	if diff.is_empty():
		diff = GameData.get_difficulty(SaveManager.get_difficulty())
	var drift_level := SaveManager.get_upgrade_level(car_id, GameData.UPGRADE_DRIFT_ANGLE)
	var turbo_level := SaveManager.get_upgrade_level(car_id, GameData.UPGRADE_TURBO)
	var armor_level := SaveManager.get_upgrade_level(car_id, GameData.UPGRADE_ARMOR)
	var magnet_level := SaveManager.get_upgrade_level(car_id, GameData.UPGRADE_MAGNET)
	var drift_fx := GameData.upgrade_effect(GameData.UPGRADE_DRIFT_ANGLE, drift_level)
	var turbo_fx := GameData.upgrade_effect(GameData.UPGRADE_TURBO, turbo_level)
	var armor_fx := GameData.upgrade_effect(GameData.UPGRADE_ARMOR, armor_level)
	var magnet_fx := GameData.upgrade_effect(GameData.UPGRADE_MAGNET, magnet_level)
	var window_perk := SaveManager.get_perk_level(GameData.PERK_BEAT_WINDOW)
	var combo_perk := GameData.perk_effect(GameData.PERK_COMBO, SaveManager.get_perk_level(GameData.PERK_COMBO))
	var focus := GameData.perk_effect(GameData.PERK_FOCUS, SaveManager.get_perk_level(GameData.PERK_FOCUS))
	_window_ms = GameData.timing_window_ms(window_perk, diff_id)
	_score_scale = float(diff.get("score_scale", 1.0))
	_drift_mult = 1.0 + float(drift_fx.get("score_mult", 0.0))
	_keeper = int(round(float(combo_perk.get("misses_kept", 0.0))))
	if bool(diff.get("combo_keeper_disabled", false)):
		_keeper = 0
	_focus_sec = float(focus.get("slowmo_sec", 0.0))
	_focus_scale = float(focus.get("time_scale", 0.65))
	_magnet_snap = float(magnet_fx.get("snap", 0.0))
	_turbo_boost = float(turbo_fx.get("boost_sec", 0.0))
	var bpm := float(chart.get("bpm", 120.0))
	var beat: float = 60.0 / maxf(bpm, 1.0)
	var from_car: float = (210.0 + float(stats.get("speed", 70.0)) * 2.35) * (1.0 + float(turbo_fx.get("speed_mult", 0.0)))
	var nominal: float = maxf(from_car, 220.0 / beat) * float(diff.get("speed_scale", 1.0))
	var paint := SaveManager.get_paint(car_id)
	var style := GameData.get_paint_style(str(paint.get("style", "gloss")))
	var cr_scale := float(diff.get("cr_scale", 1.0))
	var coin_value := int(round(8.0 * cr_scale * (1.0 + float(magnet_fx.get("pickup_mult", 0.0)))))
	return {
		"stats": stats,
		"paint": paint,
		"color_shift": bool(style.get("color_shift", false)),
		"drift_angle": float(drift_fx.get("angle_deg", 0.0)),
		"armor_durability": float(armor_fx.get("wall_durability", 0.0)),
		"extra_hits": float(armor_fx.get("extra_hits", 0.0)) + float(diff.get("extra_armor", 0.0)),
		"magnet_snap": _magnet_snap,
		"turbo_boost_sec": _turbo_boost,
		"nominal_speed": nominal,
		"half_width": float(ROAD_SCRIPT.HALF_WIDTH),
		"coin_value": max(coin_value, 1),
	}


func _setup_audio(chart: Dictionary, stream: AudioStream, campaign: bool) -> void:
	_campaign_audio = campaign and stream == null
	_music_time = 0.0
	_music_pos = 0.0
	_playback = null
	AudioAnalyzer.end_campaign_performance()
	if _campaign_audio:
		var generator := AudioAnalyzer.begin_campaign_performance(chart)
		_music.stream = generator
		_music.pitch_scale = 1.0
		_music.play()
		var playback := _music.get_stream_playback()
		if playback is AudioStreamGeneratorPlayback:
			_playback = playback
			AudioAnalyzer.render_campaign(_playback)
	elif stream != null:
		_music.stream = stream
		_music.pitch_scale = 1.0
		_music.play()
	else:
		_campaign_audio = false


func _reset_run_stats() -> void:
	_s = 0.0
	_apex_index = 0
	_pulse_index = 0
	_score = 0
	_combo = 0
	_max_combo = 0
	_perfects = 0
	_goods = 0
	_misses = 0
	_saves = 0
	_coin_cr = 0
	_coins_taken = 0
	_beat_visual = 0.0
	_judgement = ""
	_slowmo = 0.0
	_hold_until = -1.0
	_hold_bonus = 0
	_miss_bank = 0
	_music_time = 0.0
	_music_pos = 0.0
	_marking = false


func _arm_tutorial() -> void:
	_tutorial = not SaveManager.has_seen_tutorial()
	_tutorial_s = -1.0
	if not _tutorial:
		_tutorial_label.visible = false
		tutorial_changed.emit(false, "")
		return
	for apex in _apexes:
		if int(apex.get("dir", 0)) != 0:
			_tutorial_s = float(apex.get("s", 0.0))
			break
	if _tutorial_s < 0.0:
		_tutorial = false
		_tutorial_label.visible = false
		tutorial_changed.emit(false, "")
		return
	_tutorial_label.visible = true
	_tutorial_label.text = TUTORIAL_TEXT
	tutorial_changed.emit(true, TUTORIAL_TEXT)


func _clock_scale(delta: float) -> float:
	if _tutorial:
		return 0.46
	if _slowmo > 0.0:
		_slowmo = max(_slowmo - delta, 0.0)
		if _slowmo > 0.0:
			return _focus_scale
	return 1.0


func _advance_clock(delta: float, scale: float) -> float:
	var music_dt := delta * scale
	if _music != null and _music.playing:
		var position := _music.get_playback_position()
		var duration := float(_chart.get("duration_sec", 9999.0))
		if position + 0.04 < duration:
			music_dt = max(position - _music_pos, 0.0)
			_music_pos = position
		else:
			_music_pos += music_dt
	else:
		_music_pos += music_dt
	_music_time = _music_pos
	return min(max(music_dt, 0.0), 0.08)


func _steer_target() -> float:
	var edge := _half - 36.0
	var input_target := edge if (_car != null and _car.holding) else -edge
	var ideal := 0.0
	if _apex_index < _apexes.size():
		var dir := int(_apexes[_apex_index].get("dir", 0))
		if dir != 0:
			ideal = float(dir) * (_half - 40.0)
	var pull := clampf(_magnet_snap * 1.7, 0.0, 0.55)
	return lerpf(input_target, ideal, pull)


func _place_car(frame: Dictionary) -> void:
	if _car == null:
		return
	var origin: Vector2 = frame["origin"]
	var right: Vector2 = frame["right"]
	var forward: Vector2 = frame["forward"]
	_car.global_position = origin + right * _car.lateral
	_car.rotation = forward.angle() + _car.slip


func _sync_ground() -> void:
	if _ground == null or _camera == null:
		return
	_ground.global_position = _camera.global_position
	_ground.global_rotation = _camera.global_rotation


func _spawn_markers() -> void:
	for apex in _apexes:
		var at: float = float(apex.get("s", 0.0))
		var frame: Dictionary = _road_tool.sample(_curve, at)
		var dir := int(apex.get("dir", 0))
		var lane := int(apex.get("lane", TrackLanes.CENTER))
		var ideal := 0.0 if dir == 0 else float(dir) * (_half - 46.0)
		var marker := Polygon2D.new()
		marker.polygon = PackedVector2Array([
			Vector2(22, 0), Vector2(-14, -12), Vector2(-6, 0), Vector2(-14, 12),
		])
		if lane == TrackLanes.APEX:
			marker.color = Color(1.0, 0.78, 0.28)
			marker.scale = Vector2(1.45, 1.15)
		elif lane == TrackLanes.CENTER:
			marker.color = Color(0.45, 0.9, 1.0)
		else:
			marker.color = Color(0.95, 0.95, 0.9, 0.85)
		var right: Vector2 = frame["right"]
		var forward: Vector2 = frame["forward"]
		marker.position = (frame["origin"] as Vector2) + right * ideal
		marker.rotation = forward.angle()
		marker.z_index = 4
		_track.add_child(marker)


func _spawn_coins(value: int) -> void:
	_coins.clear()
	var spawned := 0
	for i in _apexes.size():
		if spawned >= 80:
			break
		var apex: Dictionary = _apexes[i]
		var kind := str(apex.get("kind", ""))
		if kind != TrackLanes.KIND_BOOST and i % 5 != 2:
			continue
		var at: float = maxf(float(apex.get("s", 0.0)) - 36.0, 0.0)
		var frame: Dictionary = _road_tool.sample(_curve, at)
		var dir := int(apex.get("dir", 0))
		var ideal := 0.0 if dir == 0 else float(dir) * (_half * 0.35)
		var coin := Polygon2D.new()
		coin.polygon = _coin_shape()
		coin.color = Color(0.98, 0.78, 0.22)
		coin.z_index = 8
		var right: Vector2 = frame["right"]
		coin.position = (frame["origin"] as Vector2) + right * ideal
		_track.add_child(coin)
		_coins.append({"node": coin, "alive": true, "value": value})
		spawned += 1


func _coin_shape() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		var angle := float(i) / 8.0 * TAU
		points.append(Vector2(cos(angle), sin(angle)) * 10.0)
	return points


func _attract_coins(step: float) -> void:
	if _car == null:
		return
	var radius := 34.0 + _magnet_snap * 860.0
	var car_pos: Vector2 = _car.global_position
	for coin in _coins:
		if not bool(coin.get("alive", false)):
			continue
		var node: Node2D = coin["node"]
		var offset: Vector2 = car_pos - node.position
		var distance := offset.length()
		if distance < radius and distance > 0.5:
			node.position += offset.normalized() * min(radius * 2.4 * step, distance)
			distance = node.position.distance_to(car_pos)
		if distance <= 26.0:
			coin["alive"] = false
			_coin_cr += int(coin.get("value", 0))
			_coins_taken += 1
			node.visible = false
			_play(_sfx_coin)


func _lay_marks() -> void:
	if _car == null or _track == null:
		return
	var sliding: bool = absf(float(_car.slip)) > 0.14 or absf(float(_car.lateral_vel)) > 90.0
	if not sliding:
		_marking = false
		return
	if not _marking or _mark_left == null or _mark_left.get_point_count() > 80:
		_marking = true
		_mark_left = _new_mark()
		_mark_right = _new_mark()
		_mark_groups.append(_mark_left)
		_mark_groups.append(_mark_right)
		while _mark_groups.size() > 28:
			var old: Line2D = _mark_groups.pop_front()
			if is_instance_valid(old):
				old.queue_free()
	var tires: Array = _car.rear_points()
	_mark_left.add_point(tires[0])
	_mark_right.add_point(tires[1])


func _new_mark() -> Line2D:
	var line := Line2D.new()
	line.width = 7.0
	line.default_color = Color(0.02, 0.02, 0.025, 0.5)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 3
	_track.add_child(line)
	return line


func _pulse_beats() -> void:
	while _pulse_index < _apexes.size() and _music_time >= float(_apexes[_pulse_index].get("t", 0.0)):
		var lane := int(_apexes[_pulse_index].get("lane", TrackLanes.CENTER))
		var intensity := 1.0 if lane == TrackLanes.APEX else 0.5
		_beat_visual = 1.0
		_camera.beat(intensity)
		beat_pulse.emit(intensity, _pulse_index)
		_pulse_index += 1


func _judge_crossed() -> void:
	while _apex_index < _apexes.size() and _s >= float(_apexes[_apex_index].get("s", 0.0)):
		_judge(_apexes[_apex_index])
		_apex_index += 1


func _judge(apex: Dictionary) -> void:
	var beat_t := float(apex.get("t", 0.0))
	var latency := float(SaveManager.get_audio_latency_ms()) / 1000.0
	var error_ms: float = absf(_music_time - (beat_t + latency)) * 1000.0
	var dir := int(apex.get("dir", 0))
	var lane := int(apex.get("lane", TrackLanes.CENTER))
	var aligned := _aligned(dir, lane)
	var close := _close_to_line(dir)
	var perfect_ms := _window_ms * 0.45
	var kind := "MISS"
	var points := 0
	if aligned and close and error_ms <= perfect_ms:
		kind = "PERFECT"
		_combo += 1
		points = _points(1000)
		_perfects += 1
		_on_perfect()
	elif aligned and error_ms <= _window_ms:
		kind = "GOOD"
		_combo += 1
		points = _points(420)
		_goods += 1
	elif _miss_bank_ok():
		kind = "SAVE"
		points = _points(120)
		_saves += 1
	else:
		kind = "MISS"
		_combo = 0
		_misses += 1
	if kind == "PERFECT" or kind == "GOOD":
		_clear_miss_bank()
	_score += points
	_max_combo = maxi(_max_combo, _combo)
	if str(apex.get("kind", "")) == TrackLanes.KIND_BOOST and kind != "MISS":
		_car.add_boost(0.45)
	if str(apex.get("kind", "")) == TrackLanes.KIND_HOLD and kind == "PERFECT":
		var good := _points(420)
		_hold_until = beat_t + max(float(apex.get("dur", 0.0)), 0.0)
		_hold_dir = dir
		_hold_bonus = max(points - good, 0)
	_beat_visual = 1.0
	_camera.beat(1.0 if kind == "PERFECT" else 0.4)
	_show_judgement(kind)
	judgement_shown.emit(kind, points, _combo)
	if kind == "PERFECT":
		_play(_sfx_perfect)
	elif kind == "GOOD" or kind == "SAVE":
		_play(_sfx_good)
	_emit_hud()


func _aligned(dir: int, lane: int) -> bool:
	var lateral: float = float(_car.lateral)
	if lane == TrackLanes.CENTER or dir == 0:
		return abs(lateral) <= _half * 0.42
	if dir < 0:
		return lateral < -_half * 0.16
	return lateral > _half * 0.16


func _close_to_line(dir: int) -> bool:
	var ideal := 0.0 if dir == 0 else float(dir) * (_half - 40.0)
	var band := _half * (0.38 if _window_ms > 110.0 else 0.28)
	return abs(_car.lateral - ideal) <= band


func _points(base: int) -> int:
	var combo_mult := 1.0 + float(maxi(_combo, 1) - 1) * 0.08
	return int(round(float(base) * _score_scale * _drift_mult * combo_mult))


func _on_perfect() -> void:
	_clear_miss_bank()
	if _tutorial:
		return
	if _focus_sec > 0.0 and _combo > 0 and _combo % 8 == 0:
		_slowmo = _focus_sec


func _miss_bank_ok() -> bool:
	if _keeper <= 0 or _miss_bank >= _keeper:
		return false
	_miss_bank += 1
	return true


func _clear_miss_bank() -> void:
	_miss_bank = 0


func _decay_hold() -> void:
	if _hold_until < 0.0 or _car == null:
		return
	if _music_time >= _hold_until:
		_hold_until = -1.0
		return
	if not _car.holds_line(_hold_dir):
		_score = maxi(_score - _hold_bonus, 0)
		_hold_until = -1.0
		_show_judgement("GOOD")
		_emit_hud()


func _update_tutorial() -> void:
	if not _tutorial:
		return
	if _tutorial_s >= 0.0 and _s >= _tutorial_s:
		_tutorial = false
		_tutorial_label.visible = false
		SaveManager.set_tutorial_seen(true)
		tutorial_changed.emit(false, "")


func _on_scrape(force: float) -> void:
	_camera.add_shake(8.0 + force * 10.0)
	scrape_feedback.emit(force)
	_play(_sfx_scrape)
	_emit_hud()


func _on_wreck() -> void:
	_finish("wrecked")


func _finish(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_running = false
	if _music != null:
		_music.stream_paused = true
	var payout: Dictionary = _payout
	var saved := _banked
	if not _banked and GameData.has_level(_level_id) and SaveManager.is_level_unlocked(_level_id) and _score > 0:
		payout = SaveManager.record_level_result(_level_id, _score)
		_payout = payout
		saved = bool(payout.get("ok", false))
		_banked = true
		if _coin_cr > 0:
			SaveManager.add_cr(_coin_cr, "coins:%s" % _level_id)
	var coin_grant := 0
	if _coin_cr > 0:
		coin_grant = _coin_cr
	var crashed := reason == "wrecked"
	var level_name := str(_chart.get("display_name", _level_id))
	if GameData.has_level(_level_id):
		level_name = str(GameData.get_level(_level_id).get("name", level_name))
	var result := {
		"ok": not crashed,
		"reason": reason,
		"crashed": crashed,
		"wrecked": crashed,
		"failed": crashed,
		"can_revive": crashed,
		"level_id": _level_id,
		"level_name": level_name,
		"score": _score,
		"stars": int(payout.get("stars", 0)),
		"best_stars": int(payout.get("best_stars", 0)),
		"best_score": int(payout.get("best_score", _score)),
		"star_delta": int(payout.get("star_delta", 0)),
		"cr_gain": int(payout.get("cr_gain", 0)),
		"xp_gain": int(payout.get("xp_gain", 0)),
		"coin_cr": coin_grant,
		"perfects": _perfects,
		"goods": _goods,
		"misses": _misses,
		"saves": _saves,
		"max_combo": _max_combo,
		"progress": clampf(_s / max(_length, 1.0), 0.0, 1.0),
		"duration": _music_time,
		"saved": saved,
		"payout": payout,
		"xp_result": payout.get("xp_result", {}),
	}
	race_finished.emit(result)


func _show_results(result: Dictionary) -> void:
	if _results != null:
		_results.queue_free()
	_results = CanvasLayer.new()
	_results.layer = 24
	add_child(_results)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.04, 0.72)
	_results.add_child(dim)
	var panel := VBoxContainer.new()
	panel.offset_left = 70.0
	panel.offset_top = 360.0
	panel.offset_right = 650.0
	panel.offset_bottom = 980.0
	panel.add_theme_constant_override("separation", 10)
	_results.add_child(panel)
	var title := Label.new()
	title.text = "WRECKED" if str(result.get("reason", "")) == "wrecked" else "FINISH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UiPalette.MAGENTA if title.text == "WRECKED" else UiPalette.INK)
	panel.add_child(title)
	var body := Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", UiPalette.INK)
	body.text = "Score %d\nStars %d\n+%d CR   +%d XP\nCoins +%d CR\nPerfect %d   Good %d   Miss %d\nMax combo %d" % [
		int(result.get("score", 0)),
		int(result.get("stars", 0)),
		int(result.get("cr_gain", 0)),
		int(result.get("xp_gain", 0)),
		int(result.get("coin_cr", 0)),
		int(result.get("perfects", 0)),
		int(result.get("goods", 0)),
		int(result.get("misses", 0)),
		int(result.get("max_combo", 0)),
	]
	panel.add_child(body)
	var button := Button.new()
	button.text = "CONTINUE"
	button.custom_minimum_size = Vector2(0, 64)
	UiPalette.style_button(button, UiPalette.PIT, UiPalette.CYAN, 22)
	button.pressed.connect(_leave)
	panel.add_child(button)
	_unlit(_results)


func _pause() -> void:
	if _paused or _finished or not is_inside_tree():
		return
	_paused = true
	if _music != null:
		_music.stream_paused = true
	_pause_layer = PAUSE_SCENE.instantiate() as CanvasLayer
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.layer = 30
	add_child(_pause_layer)
	if _pause_layer.has_signal("resume_requested"):
		_pause_layer.resume_requested.connect(_resume)
	if _pause_layer.has_signal("quit_requested"):
		_pause_layer.quit_requested.connect(_leave)
	_unlit(_pause_layer)
	get_tree().paused = true


func _resume() -> void:
	_set_paused(false)


func _leave() -> void:
	_set_paused(false)
	_running = false
	_finished = true
	if _music != null:
		_music.stop()
	AudioAnalyzer.end_campaign_performance()
	exit_requested.emit()


func _set_paused(paused: bool) -> void:
	_paused = paused
	if get_tree() != null:
		get_tree().paused = paused
	if _music != null:
		_music.stream_paused = paused
	if not paused and _pause_layer != null:
		var layer := _pause_layer
		_pause_layer = null
		layer.queue_free()


func _fail_start(reason: String) -> void:
	_running = false
	_error_label.visible = true
	_error_label.text = "Could not start the race (%s)." % reason
	race_failed.emit(reason)


func _clear_track() -> void:
	_running = false
	_set_paused(false)
	if _music != null:
		_music.stop()
	AudioAnalyzer.end_campaign_performance()
	_playback = null
	_campaign_audio = false
	if _track != null:
		var old := _track
		_track = null
		old.queue_free()
	_car = null
	_curve = null
	_apexes = []
	_coins.clear()
	_mark_left = null
	_mark_right = null
	_mark_groups.clear()
	if _results != null:
		var old_results := _results
		_results = null
		old_results.queue_free()


func _set_hold(held: bool) -> void:
	if _car != null and not _finished:
		_car.set_holding(held)


func _ignore_pointer(point: Vector2) -> bool:
	if _paused or _finished or _error_label.visible:
		return true
	if _pause_button != null and _pause_button.get_global_rect().has_point(point):
		return true
	return false


func _show_judgement(kind: String) -> void:
	_judgement = kind
	_judgement_time = _music_time
	_judge_label.text = kind


func _refresh_hud_widgets() -> void:
	_score_label.text = str(_score)
	_combo_label.text = "COMBO %d" % _combo
	_coin_label.text = "%d CR" % _coin_cr
	var progress := clampf(_s / max(_length, 1.0), 0.0, 1.0)
	_progress_fill.offset_right = 28.0 + 532.0 * progress
	var ratio := 0.0
	if _car != null and _car.max_hp > 0.0:
		ratio = clampf(_car.hp / _car.max_hp, 0.0, 1.0)
	_hp_fill.offset_right = 28.0 + 192.0 * ratio
	_hp_fill.color = UiPalette.MAGENTA.lerp(UiPalette.AMBER, 1.0 - ratio)
	_pulse_bar.color.a = 0.15 + _beat_visual * 0.7
	if _judgement_time >= 0.0 and _music_time - _judgement_time > 0.55:
		_judge_label.text = ""


func _emit_hud() -> void:
	hud_state_changed.emit(_telemetry())


func _label(x: float, y: float, w: float, h: float, size: int, color: Color) -> Label:
	var label := Label.new()
	label.offset_left = x
	label.offset_top = y
	label.offset_right = x + w
	label.offset_bottom = y + h
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_hud.add_child(label)
	return label


func _sfx_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	if AudioServer.get_bus_index("SFX") >= 0:
		player.bus = "SFX"
	add_child(player)
	return player


func _play(player: AudioStreamPlayer) -> void:
	if player == null or _paused:
		return
	player.play()


func _noise_wav(freq: float, seconds: float, volume: float, noise_amt: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := maxi(int(float(rate) * seconds), 1)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var state := 19
	for i in frames:
		var env := 1.0 - float(i) / float(frames)
		env *= env
		state = int((state * 1103515245 + 12345) & 2147483647)
		var noise := float(state % 2000 - 1000) / 1000.0
		var tone := sin(TAU * freq * float(i) / float(rate))
		var sample := int(clampf((tone * (1.0 - noise_amt) + noise * noise_amt) * env * volume, -1.0, 1.0) * 30000.0)
		bytes.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _unlit(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).light_mask = 0
	for child in node.get_children():
		_unlit(child)
