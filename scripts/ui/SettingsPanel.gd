extends VBoxContainer

## Music, SFX, graphics quality, and audio-latency calibration.
## Shared by the menu settings screen and the pause menu.
## Tap calibration plays a 120 BPM click and stores the median offset.

signal tips_requested

const TAPS_TARGET := 8
const TAPS_MINIMUM := 4
const BEAT_MS := 500
const MISS_MS := 250

var _syncing := false
var _dragging_music := false
var _dragging_sfx := false
var _dragging_latency := false
var _calibrating := false
var _player: AudioStreamPlayer
var _start_msec := 0
var _next_index := 0
var _beat_times: Array = []
var _offsets: Array = []
var _lamp_life := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_style()
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	_player.stream = _click_stream()
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	%MusicCheck.toggled.connect(_on_music_enabled)
	%SfxCheck.toggled.connect(_on_sfx_enabled)
	%MusicSlider.value_changed.connect(_on_music_value)
	%SfxSlider.value_changed.connect(_on_sfx_value)
	%MusicSlider.drag_started.connect(func() -> void: _dragging_music = true)
	%SfxSlider.drag_started.connect(func() -> void: _dragging_sfx = true)
	%MusicSlider.drag_ended.connect(_on_music_drag_ended)
	%SfxSlider.drag_ended.connect(_on_sfx_drag_ended)
	%LowButton.pressed.connect(_set_quality.bind("low"))
	%MedButton.pressed.connect(_set_quality.bind("medium"))
	%HighButton.pressed.connect(_set_quality.bind("high"))
	%LatencySlider.value_changed.connect(_on_latency_value)
	%LatencySlider.drag_started.connect(_on_latency_drag_started)
	%LatencySlider.drag_ended.connect(_on_latency_drag_ended)
	%CalibrateButton.pressed.connect(_toggle_calibration)
	%TapButton.pressed.connect(_on_tap)
	%ResetButton.pressed.connect(_reset_latency)
	%TipsButton.pressed.connect(func() -> void: tips_requested.emit())
	SaveManager.settings_changed.connect(_on_settings_changed)
	_apply_from_save()


func _exit_tree() -> void:
	shutdown()
	if is_instance_valid(SaveManager) and SaveManager.settings_changed.is_connected(_on_settings_changed):
		SaveManager.settings_changed.disconnect(_on_settings_changed)


func _process(delta: float) -> void:
	if _lamp_life > 0.0:
		_lamp_life = maxf(_lamp_life - delta, 0.0)
		var alpha := clampf(_lamp_life / 0.08, 0.0, 1.0)
		%BeatLamp.color = Color(UiPalette.CYAN.r, UiPalette.CYAN.g, UiPalette.CYAN.b, alpha)
	if _calibrating:
		_advance_metronome()


func shutdown() -> void:
	_stop_calibration(false)


func _style() -> void:
	for label in [%AudioLabel, %GraphicsLabel, %LatencyLabel]:
		UiPalette.style_label(label, UiPalette.MAGENTA, 14)
	UiPalette.style_check(%MusicCheck)
	UiPalette.style_check(%SfxCheck)
	UiPalette.style_slider(%MusicSlider)
	UiPalette.style_slider(%SfxSlider)
	UiPalette.style_slider(%LatencySlider)
	UiPalette.style_label(%MusicValue, UiPalette.INK, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	UiPalette.style_label(%SfxValue, UiPalette.INK, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	UiPalette.style_label(%LatencyReadout, UiPalette.AMBER, 16)
	UiPalette.style_label(%QualityHint, UiPalette.MUTED, 14)
	%QualityHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(%CalibrateStatus, UiPalette.MUTED, 14)
	%CalibrateStatus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for button in [%LowButton, %MedButton, %HighButton, %CalibrateButton, %TapButton, %ResetButton, %TipsButton]:
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.style_button(%CalibrateButton, UiPalette.PIT, UiPalette.CYAN, 16)
	UiPalette.style_button(%ResetButton, UiPalette.PIT, UiPalette.AMBER, 16)
	UiPalette.style_button(%TipsButton, UiPalette.PIT, UiPalette.MAGENTA, 16)
	UiPalette.style_button(%TapButton, UiPalette.PIT, UiPalette.CYAN, 20)
	%LatencySlider.min_value = SaveManager.MIN_AUDIO_LATENCY_MS
	%LatencySlider.max_value = SaveManager.MAX_AUDIO_LATENCY_MS
	%LatencySlider.step = 1
	%MusicSlider.min_value = 0
	%MusicSlider.max_value = 100
	%MusicSlider.step = 1
	%SfxSlider.min_value = 0
	%SfxSlider.max_value = 100
	%SfxSlider.step = 1
	%TapButton.visible = false
	%BeatLamp.custom_minimum_size = Vector2(0, 8)
	%BeatLamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%BeatLamp.color = Color(UiPalette.CYAN.r, UiPalette.CYAN.g, UiPalette.CYAN.b, 0)


func _apply_from_save() -> void:
	_syncing = true
	%MusicCheck.button_pressed = SaveManager.is_music_enabled()
	%SfxCheck.button_pressed = SaveManager.is_sfx_enabled()
	%MusicSlider.value = SaveManager.get_music_volume() * 100.0
	%SfxSlider.value = SaveManager.get_sfx_volume() * 100.0
	%LatencySlider.value = SaveManager.get_audio_latency_ms()
	%MusicValue.text = "%d%%" % int(round(%MusicSlider.value))
	%SfxValue.text = "%d%%" % int(round(%SfxSlider.value))
	_syncing = false
	_refresh_quality()
	_refresh_latency_text()
	if not _calibrating:
		%CalibrateStatus.text = "Shift the beat line to match your speakers. Positive means you tap after the click."


func _on_settings_changed() -> void:
	if _syncing:
		return
	_apply_from_save()


func _on_music_enabled(enabled: bool) -> void:
	if _syncing:
		return
	SaveManager.set_music_enabled(enabled)


func _on_sfx_enabled(enabled: bool) -> void:
	if _syncing:
		return
	SaveManager.set_sfx_enabled(enabled)


func _on_music_value(value: float) -> void:
	%MusicValue.text = "%d%%" % int(round(value))
	if _syncing or _dragging_music:
		return
	SaveManager.set_music_volume(value / 100.0)


func _on_sfx_value(value: float) -> void:
	%SfxValue.text = "%d%%" % int(round(value))
	if _syncing or _dragging_sfx:
		return
	SaveManager.set_sfx_volume(value / 100.0)


func _on_music_drag_ended(_changed: bool) -> void:
	_dragging_music = false
	SaveManager.set_music_volume(%MusicSlider.value / 100.0)


func _on_sfx_drag_ended(_changed: bool) -> void:
	_dragging_sfx = false
	SaveManager.set_sfx_volume(%SfxSlider.value / 100.0)


func _set_quality(quality: String) -> void:
	if not SaveManager.set_graphics_quality(quality):
		%QualityHint.text = "That quality isn't available."
		return
	_refresh_quality()


func _refresh_quality() -> void:
	var current := SaveManager.get_graphics_quality()
	UiPalette.style_choice(%LowButton, current == "low", 15)
	UiPalette.style_choice(%MedButton, current == "medium", 15)
	UiPalette.style_choice(%HighButton, current == "high", 15)
	match current:
		"low":
			%QualityHint.text = "Low keeps the night softer."
		"high":
			%QualityHint.text = "High leaves the neon at full lamp."
		_:
			%QualityHint.text = "Medium is the balanced night."


func _on_latency_drag_started() -> void:
	_dragging_latency = true
	if _calibrating:
		_stop_calibration(false)


func _on_latency_value(value: float) -> void:
	if _syncing:
		_refresh_latency_text()
		return
	if _dragging_latency:
		_refresh_latency_text()
		return
	SaveManager.set_audio_latency_ms(int(round(value)))


func _on_latency_drag_ended(_changed: bool) -> void:
	_dragging_latency = false
	SaveManager.set_audio_latency_ms(int(round(%LatencySlider.value)))


func _reset_latency() -> void:
	_stop_calibration(false)
	SaveManager.set_audio_latency_ms(0)


func _refresh_latency_text() -> void:
	var latency := int(round(%LatencySlider.value))
	if latency > 0:
		%LatencyReadout.text = "+%d ms" % latency
	else:
		%LatencyReadout.text = "%d ms" % latency


func _toggle_calibration() -> void:
	if _calibrating:
		_stop_calibration(true)
		return
	_start_calibration()


func _start_calibration() -> void:
	_calibrating = true
	_offsets.clear()
	_beat_times.clear()
	_start_msec = Time.get_ticks_msec()
	_next_index = 0
	%TapButton.visible = true
	%TapButton.text = "TAP"
	%CalibrateButton.text = "STOP"
	UiPalette.style_button(%CalibrateButton, UiPalette.PIT, UiPalette.AMBER, 16)
	UiPalette.style_button(%TapButton, UiPalette.PIT, UiPalette.CYAN, 20)
	var heard := "Follow the flash."
	if not SaveManager.is_sfx_enabled() or SaveManager.get_sfx_volume() <= 0.01:
		heard = "SFX is off, so follow the flash."
	%CalibrateStatus.text = "Tap TAP on each click. 0/%d. %s" % [TAPS_TARGET, heard]
	_advance_metronome()


func _stop_calibration(apply: bool) -> void:
	var was := _calibrating
	_calibrating = false
	if _player:
		_player.stop()
	%TapButton.visible = false
	%CalibrateButton.text = "CALIBRATE"
	UiPalette.style_button(%CalibrateButton, UiPalette.PIT, UiPalette.CYAN, 16)
	if not was:
		return
	if not apply:
		%CalibrateStatus.text = "Calibration cancelled. The offset is unchanged."
		return
	if _offsets.size() < TAPS_MINIMUM:
		%CalibrateStatus.text = "Need at least %d taps. Latency unchanged." % TAPS_MINIMUM
		return
	var median := _median(_offsets)
	var stored := SaveManager.set_audio_latency_ms(median)
	%CalibrateStatus.text = "Set to %d ms from %d taps." % [stored, _offsets.size()]


func _advance_metronome() -> void:
	var elapsed := Time.get_ticks_msec() - _start_msec
	var index := int(elapsed / BEAT_MS)
	while _next_index <= index:
		_beat_times.append(_start_msec + _next_index * BEAT_MS)
		if _beat_times.size() > 24:
			_beat_times.pop_front()
		_flash()
		if _player and not _player.playing:
			_player.play()
		elif _player:
			_player.play()
		_next_index += 1


func _on_tap() -> void:
	if not _calibrating or _beat_times.is_empty():
		return
	var now := Time.get_ticks_msec()
	var nearest: int = int(_beat_times[0])
	var best := absi(now - nearest)
	for stamp in _beat_times:
		var delta := absi(now - int(stamp))
		if delta < best:
			best = delta
			nearest = int(stamp)
	if best > MISS_MS:
		%CalibrateStatus.text = "Missed the click. Tap closer. %d/%d" % [_offsets.size(), TAPS_TARGET]
		return
	_offsets.append(now - nearest)
	%CalibrateStatus.text = "Tap %d/%d" % [_offsets.size(), TAPS_TARGET]
	if _offsets.size() >= TAPS_TARGET:
		_stop_calibration(true)


func _flash() -> void:
	_lamp_life = 0.08
	%BeatLamp.color = Color(UiPalette.CYAN.r, UiPalette.CYAN.g, UiPalette.CYAN.b, 1)


func _median(values: Array) -> int:
	var copy: Array = values.duplicate()
	copy.sort()
	if copy.is_empty():
		return 0
	var mid := int(copy.size() / 2)
	if copy.size() % 2 == 1:
		return int(copy[mid])
	return int(round((float(copy[mid - 1]) + float(copy[mid])) * 0.5))


func _click_stream() -> AudioStreamWAV:
	var rate := 22050
	var frames := int(rate * 0.045)
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in frames:
		var env := 1.0 - float(i) / float(frames)
		var sample := int(sin(float(i) / float(rate) * TAU * 1400.0) * 14000.0 * env * env)
		pcm.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = pcm
	return stream
