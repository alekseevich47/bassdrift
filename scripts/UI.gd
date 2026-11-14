extends CanvasLayer
## Start / HUD / Game Over / Settings.

signal start_pressed
signal restart_pressed

@onready var start_screen: Control = $StartScreen
@onready var hud: Control = $HUD
@onready var game_over_screen: Control = $GameOver
@onready var settings_panel: Control = $Settings
@onready var hold_label: Label = $StartScreen/HoldHint
@onready var bpm_label: Label = $StartScreen/BpmLabel
@onready var title_label: Label = $StartScreen/Title
@onready var score_label: Label = $HUD/ScoreLabel
@onready var combo_plaque: Label = $HUD/ComboPlaque
@onready var progress_bar: ProgressBar = $HUD/TrackProgress
@onready var go_score: Label = $GameOver/ScoreValue
@onready var go_best: Label = $GameOver/BestValue
@onready var go_percent: Label = $GameOver/PercentValue
@onready var again_btn: Button = $GameOver/AgainButton
@onready var play_btn: Button = $StartScreen/PlayButton
@onready var settings_btn: Button = $SettingsButton
@onready var vol_slider: HSlider = $Settings/VolumeSlider
@onready var offset_slider: HSlider = $Settings/OffsetSlider
@onready var offset_value: Label = $Settings/OffsetValue
@onready var metronome: ColorRect = $Settings/Metronome
@onready var skin_box: HBoxContainer = $Settings/SkinBox
@onready var close_settings: Button = $Settings/CloseButton
@onready var preset_option: OptionButton = $StartScreen/PresetOption

var _hint_pulse: float = 0.0
var _metro_flash: float = 0.0


func _ready() -> void:
	show_start()
	play_btn.pressed.connect(func(): start_pressed.emit())
	again_btn.pressed.connect(func(): restart_pressed.emit())
	settings_btn.pressed.connect(_toggle_settings)
	close_settings.pressed.connect(func(): settings_panel.visible = false)

	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.01
	vol_slider.value = GameState.get_volume_linear()
	vol_slider.value_changed.connect(func(v): GameState.set_volume(v))

	offset_slider.min_value = -200.0
	offset_slider.max_value = 200.0
	offset_slider.step = 1.0
	offset_slider.value = GameState.audio_offset_ms
	offset_slider.value_changed.connect(_on_offset_changed)
	_on_offset_changed(GameState.audio_offset_ms)

	preset_option.clear()
	for p in GameState.BPM_PRESETS:
		preset_option.add_item(p["name"])
	preset_option.selected = GameState.selected_preset
	preset_option.item_selected.connect(func(i):
		GameState.select_preset(i)
		_refresh_bpm_label()
	)
	_refresh_bpm_label()
	_build_skin_buttons()

	GameState.score_changed.connect(_on_score)
	GameState.combo_changed.connect(_on_combo)
	GameState.game_over.connect(_on_game_over)
	AudioBeatManager.beat_hit.connect(_on_beat)

	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	combo_plaque.visible = false


func _refresh_bpm_label() -> void:
	var p: Dictionary = GameState.BPM_PRESETS[GameState.selected_preset]
	bpm_label.text = "%s  ·  HOLD TO DRIFT" % p["name"]


func _build_skin_buttons() -> void:
	for c in skin_box.get_children():
		c.queue_free()
	for i in GameState.SKINS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(72, 40)
		var unlocked: bool = GameState.unlocked_skins[i]
		var col: Color = GameState.SKINS[i][1]
		b.text = "◆" if unlocked else "🔒"
		b.modulate = col if unlocked else Color(0.4, 0.4, 0.4)
		b.disabled = not unlocked
		var idx := i
		b.pressed.connect(func(): GameState.select_skin(idx))
		skin_box.add_child(b)


func show_start() -> void:
	start_screen.visible = true
	hud.visible = false
	game_over_screen.visible = false
	settings_panel.visible = false
	_refresh_bpm_label()
	_build_skin_buttons()


func show_hud() -> void:
	start_screen.visible = false
	hud.visible = true
	game_over_screen.visible = false
	score_label.text = "0"
	combo_plaque.visible = false
	progress_bar.value = 0.0


func _on_score(s: int) -> void:
	score_label.text = str(s)


func _on_combo(c: int) -> void:
	if c >= 2:
		combo_plaque.visible = true
		combo_plaque.text = "COMBO x%d" % c
	else:
		combo_plaque.visible = false


func _on_game_over(final_score: int, best: int, track_percent: float) -> void:
	hud.visible = false
	game_over_screen.visible = true
	go_score.text = str(final_score)
	go_best.text = "BEST  %d" % best
	go_percent.text = "%d%% TRACK" % int(track_percent * 100.0)
	_build_skin_buttons()


func _toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		_build_skin_buttons()
		vol_slider.value = GameState.get_volume_linear()
		offset_slider.value = GameState.audio_offset_ms


func _on_offset_changed(v: float) -> void:
	GameState.set_audio_offset(v)
	offset_value.text = "%+d ms" % int(v)


func _on_beat(_idx: int, _is_drop: bool) -> void:
	_metro_flash = 1.0


func _process(delta: float) -> void:
	_hint_pulse += delta * 3.0
	var a := 0.55 + sin(_hint_pulse) * 0.35
	hold_label.modulate.a = a
	title_label.modulate = Color(0.7 + AudioBeatManager.bass_energy * 0.3, 0.95, 1.0)

	progress_bar.value = GameState.track_progress

	if settings_panel.visible:
		_metro_flash = maxf(0.0, _metro_flash - delta * 4.0)
		metronome.color = Color(0.0, 0.94, 1.0, _metro_flash)
