extends Control

## Pick an mp3, ogg, or wav, preview the analyzer grid, then start a custom race.
## Main keeps the request on the race node until gameplay reads configure_custom.

signal closed
signal custom_race_requested(request: Dictionary)

var _path := ""
var _ready_to_race := false
var _handed_off := false
var _dialog: FileDialog
var _popup: AcceptDialog
var _preview_bpm := 0.0


func _ready() -> void:
	UiPalette.paint_header(%BackButton, %Title, %Wallet)
	%Title.text = "CUSTOM"
	%BackButton.pressed.connect(_on_back)
	UiPalette.prepare_scroll(%Scroll)
	UiPalette.style_button(%FileButton, UiPalette.PIT, UiPalette.CYAN, 18)
	%FileButton.custom_minimum_size = Vector2(0, 60)
	%FileButton.pressed.connect(_choose_file)
	UiPalette.style_label(%FileLabel, UiPalette.INK, 16)
	%FileLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(%Preview, UiPalette.MUTED, 16)
	%Preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(%DiffLabel, UiPalette.MAGENTA, 14)
	UiPalette.style_label(%DiffHint, UiPalette.MUTED, 14)
	%DiffHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for button in [%ChillButton, %DriveButton, %HardcoreButton]:
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%ChillButton.pressed.connect(_set_difficulty.bind(GameData.DIFF_CHILL))
	%DriveButton.pressed.connect(_set_difficulty.bind(GameData.DIFF_DRIVE))
	%HardcoreButton.pressed.connect(_set_difficulty.bind(GameData.DIFF_HARDCORE))
	UiPalette.style_button(%StartButton, UiPalette.PIT, UiPalette.MAGENTA, 20)
	%StartButton.custom_minimum_size = Vector2(0, 68)
	%StartButton.pressed.connect(_on_start)
	SaveManager.currency_changed.connect(_on_currency)
	SaveManager.settings_changed.connect(_on_settings)
	_show_empty()
	_refresh_difficulty()
	_sync_wallet()


func _exit_tree() -> void:
	if is_instance_valid(SaveManager):
		if SaveManager.currency_changed.is_connected(_on_currency):
			SaveManager.currency_changed.disconnect(_on_currency)
		if SaveManager.settings_changed.is_connected(_on_settings):
			SaveManager.settings_changed.disconnect(_on_settings)
	if not _handed_off and not _path.is_empty():
		AudioAnalyzer.clear_loaded_audio()


func _on_currency(_cr: int) -> void:
	_sync_wallet()


func _on_settings() -> void:
	_refresh_difficulty()
	_refresh_preview_hint()


func _on_back() -> void:
	closed.emit()


func _choose_file() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.title = "Choose a track"
		_dialog.ok_button_text = "USE TRACK"
		_dialog.min_size = Vector2i(640, 860)
		_dialog.add_filter("*.mp3, *.ogg, *.wav", "Tracks")
		_dialog.add_filter("*.mp3", "MP3")
		_dialog.add_filter("*.ogg", "OGG")
		_dialog.add_filter("*.wav", "WAV")
		_dialog.file_selected.connect(_on_file_selected)
		add_child(_dialog)
		var music := OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
		if music.is_empty() or not DirAccess.dir_exists_absolute(music):
			music = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		if not music.is_empty() and DirAccess.dir_exists_absolute(music):
			_dialog.current_dir = music
	_dialog.popup_centered_ratio(0.92)


func _on_file_selected(path: String) -> void:
	var loaded := AudioAnalyzer.load_user_audio(path)
	if not bool(loaded.get("ok", false)):
		_fail(str(loaded.get("error", "decode_failed")))
		return
	var beat_map := AudioAnalyzer.analyze_to_beat_map()
	if not bool(beat_map.get("ok", false)):
		_fail(str(beat_map.get("error", "no_audio")))
		return
	_path = path
	_ready_to_race = true
	_preview_bpm = float(beat_map.get("bpm", 0.0))
	var hinted := float(loaded.get("bpm_hint", 0.0))
	var beats: Array = beat_map.get("beats", [])
	var bpm_line := "BPM %d" % int(round(_preview_bpm))
	if hinted <= 1.0:
		bpm_line += "  ·  no tag, grid estimate"
	var format := str(loaded.get("format", "")).to_upper()
	var duration := float(beat_map.get("duration_sec", loaded.get("duration_sec", 0.0)))
	%FileLabel.text = path.get_file()
	%Preview.text = "%s  ·  %s\n%s\n%d beats  ·  feels like %s\n%s" % [
		format,
		UiPalette.clock(duration),
		bpm_line,
		beats.size(),
		_feel_name(_preview_bpm),
		_difficulty_sentence(),
	]
	UiPalette.style_label(%Preview, UiPalette.INK, 16)
	%StartButton.disabled = false
	%StartButton.text = "START RACE"
	UiPalette.style_button(%StartButton, UiPalette.PIT, UiPalette.MAGENTA, 20)


func _on_start() -> void:
	if not _ready_to_race or _path.is_empty():
		_fail("no_audio")
		return
	_handed_off = true
	var beat_map := AudioAnalyzer.get_last_beat_map()
	custom_race_requested.emit({
		"mode": "custom",
		"audio_path": _path,
		"display_name": _path.get_file(),
		"format": _path.get_extension().to_lower(),
		"duration_sec": float(beat_map.get("duration_sec", 0.0)),
		"bpm": float(beat_map.get("bpm", _preview_bpm)),
		"beat_count": (beat_map.get("beats", []) as Array).size(),
		"difficulty": SaveManager.get_difficulty(),
		"stream_ready": AudioAnalyzer.get_loaded_stream() != null,
	})


func _set_difficulty(difficulty_id: String) -> void:
	if not SaveManager.set_difficulty(difficulty_id):
		_popup_message("That difficulty isn't available.")
		return
	_refresh_difficulty()
	_refresh_preview_hint()


func _refresh_difficulty() -> void:
	var current := SaveManager.get_difficulty()
	%ChillButton.text = "CHILL"
	%DriveButton.text = "DRIVE"
	%HardcoreButton.text = "HARDCORE"
	UiPalette.style_choice(%ChillButton, current == GameData.DIFF_CHILL, 15)
	UiPalette.style_choice(%DriveButton, current == GameData.DIFF_DRIVE, 15)
	UiPalette.style_choice(%HardcoreButton, current == GameData.DIFF_HARDCORE, 15)
	%DiffHint.text = _difficulty_sentence()


func _refresh_preview_hint() -> void:
	if not _ready_to_race:
		return
	var lines: PackedStringArray = %Preview.text.split("\n")
	if lines.size() >= 4:
		lines[3] = _difficulty_sentence()
		%Preview.text = "\n".join(lines)
	else:
		%Preview.text = "%s\n%s" % [%Preview.text, _difficulty_sentence()]


func _difficulty_sentence() -> String:
	var diff := GameData.get_difficulty(SaveManager.get_difficulty())
	if diff.is_empty():
		return "Pick a difficulty."
	var sentence := "%s on the line  ·  timing x%s  ·  score x%s" % [
		str(diff.get("name", "")),
		UiPalette.trim_number(diff.get("window_scale", 1.0)),
		UiPalette.trim_number(diff.get("score_scale", 1.0)),
	]
	if bool(diff.get("combo_keeper_disabled", false)):
		sentence += "  ·  combo keeper off"
	return sentence


func _feel_name(bpm: float) -> String:
	var id := GameData.DIFF_DRIVE
	if bpm < 128.0:
		id = GameData.DIFF_CHILL
	elif bpm >= 150.0:
		id = GameData.DIFF_HARDCORE
	return str(GameData.get_difficulty(id).get("name", "Drive"))


func _show_empty() -> void:
	_ready_to_race = false
	_path = ""
	_preview_bpm = 0.0
	%FileLabel.text = "No track loaded"
	%Preview.text = "Pick an MP3, OGG, or WAV to preview the beat line.\nStart stays locked until a track loads."
	UiPalette.style_label(%Preview, UiPalette.MUTED, 16)
	%StartButton.disabled = true
	%StartButton.text = "START RACE"
	UiPalette.style_button(%StartButton, UiPalette.PIT, UiPalette.MAGENTA, 20)


func _fail(reason: String) -> void:
	_ready_to_race = false
	_path = ""
	_preview_bpm = 0.0
	AudioAnalyzer.clear_loaded_audio()
	var message := _friendly(reason)
	%FileLabel.text = "No track loaded"
	%Preview.text = message
	UiPalette.style_label(%Preview, UiPalette.DANGER, 16)
	%StartButton.disabled = true
	%StartButton.text = "START RACE"
	_popup_message(message)


func _friendly(reason: String) -> String:
	match reason:
		"empty_path":
			return "Choose a music file first."
		"file_missing":
			return "That file isn't there anymore. Pick it again."
		"unsupported_format":
			return "Use an MP3, OGG, or WAV file."
		"decode_failed":
			return "Couldn't read that audio. Export it again as MP3, OGG, or 16-bit WAV."
		"empty_audio":
			return "That file doesn't contain any audio."
		"wav_too_small", "wav_header", "wav_chunk", "wav_format":
			return "That WAV looks damaged. Re-export it and try again."
		"wav_unsupported":
			return "WAVs need to be 16-bit PCM, mono or stereo. Convert it and try again."
		"no_audio":
			return "Nothing is loaded yet."
		_:
			return "Couldn't use that file (%s)." % reason


func _popup_message(message: String) -> void:
	if _popup == null:
		_popup = AcceptDialog.new()
		_popup.title = "Can't read that track"
		_popup.ok_button_text = "OK"
		add_child(_popup)
	_popup.dialog_text = message
	_popup.popup_centered()


func _sync_wallet() -> void:
	%Wallet.text = UiPalette.money(SaveManager.get_cr())
