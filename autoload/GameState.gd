extends Node
## Persistent game state, scoring, skins, and user://save.json.

signal score_changed(score: int)
signal combo_changed(combo: int)
signal game_started
signal game_over(final_score: int, best: int, track_percent: float)
signal skin_changed(skin_index: int)
signal settings_changed

const SAVE_PATH := "user://save.json"
const SKIN_UNLOCK_SCORES := [0, 5000, 15000]

enum Phase { MENU, PLAYING, CRASHING, GAME_OVER }

var phase: Phase = Phase.MENU
var score: int = 0
var combo: int = 0
var best_score: int = 0
var track_progress: float = 0.0  # 0..1 across beat 0..64
var score_multiplier: float = 1.0
var perfect_drifts: int = 0

var volume_db: float = -6.0
var audio_offset_ms: float = 0.0
var selected_skin: int = 0
var unlocked_skins: Array[bool] = [true, false, false]

## Neon car skin palettes: [body, accent, headlight]
const SKINS := [
	[Color(0.05, 0.12, 0.22), Color(0.0, 0.94, 1.0), Color(1.0, 0.95, 0.7)],
	[Color(0.12, 0.04, 0.14), Color(1.0, 0.0, 0.33), Color(1.0, 0.6, 0.9)],
	[Color(0.04, 0.14, 0.08), Color(0.2, 1.0, 0.45), Color(0.85, 1.0, 0.7)],
]

const BPM_PRESETS := [
	{"name": "FUNK 130", "bpm": 130.0},
	{"name": "DnB 174", "bpm": 174.0},
	{"name": "HOUSE 128", "bpm": 128.0},
]

var selected_preset: int = 0


func _ready() -> void:
	load_save()


func get_bpm() -> float:
	return BPM_PRESETS[selected_preset]["bpm"]


func get_skin_colors() -> Array:
	return SKINS[clampi(selected_skin, 0, SKINS.size() - 1)]


func reset_run() -> void:
	score = 0
	combo = 0
	track_progress = 0.0
	score_multiplier = 1.0
	perfect_drifts = 0
	phase = Phase.PLAYING
	score_changed.emit(score)
	combo_changed.emit(combo)
	game_started.emit()


func add_score(base_points: int) -> void:
	if phase != Phase.PLAYING:
		return
	var gained := int(base_points * maxf(1, combo) * score_multiplier)
	score += gained
	score_changed.emit(score)
	_check_skin_unlocks()


func bump_combo() -> void:
	combo += 1
	combo_changed.emit(combo)


func break_combo() -> void:
	combo = 0
	combo_changed.emit(combo)


func register_perfect_drift() -> void:
	perfect_drifts += 1
	bump_combo()
	add_score(250)


func set_drop_multiplier(active: bool) -> void:
	score_multiplier = 4.0 if active else 1.0


func update_track_progress(beat_index: float, total_beats: float = 64.0) -> void:
	track_progress = clampf(beat_index / total_beats, 0.0, 1.0)


func trigger_game_over() -> void:
	if phase == Phase.GAME_OVER:
		return
	phase = Phase.GAME_OVER
	if score > best_score:
		best_score = score
	_check_skin_unlocks()
	save()
	game_over.emit(score, best_score, track_progress)


func set_volume(linear: float) -> void:
	volume_db = linear_to_db(clampf(linear, 0.001, 1.0))
	AudioServer.set_bus_volume_db(0, volume_db)
	settings_changed.emit()
	save()


func get_volume_linear() -> float:
	return db_to_linear(volume_db)


func set_audio_offset(ms: float) -> void:
	audio_offset_ms = clampf(ms, -200.0, 200.0)
	settings_changed.emit()
	save()


func select_skin(index: int) -> void:
	if index < 0 or index >= unlocked_skins.size():
		return
	if not unlocked_skins[index]:
		return
	selected_skin = index
	skin_changed.emit(selected_skin)
	save()


func select_preset(index: int) -> void:
	selected_preset = clampi(index, 0, BPM_PRESETS.size() - 1)
	save()


func _check_skin_unlocks() -> void:
	for i in SKIN_UNLOCK_SCORES.size():
		if best_score >= SKIN_UNLOCK_SCORES[i] or score >= SKIN_UNLOCK_SCORES[i]:
			unlocked_skins[i] = true


func save() -> void:
	var data := {
		"best_score": best_score,
		"volume_db": volume_db,
		"audio_offset_ms": audio_offset_ms,
		"selected_skin": selected_skin,
		"unlocked_skins": unlocked_skins.duplicate(),
		"selected_preset": selected_preset,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		AudioServer.set_bus_volume_db(0, volume_db)
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	best_score = int(data.get("best_score", 0))
	volume_db = float(data.get("volume_db", -6.0))
	audio_offset_ms = float(data.get("audio_offset_ms", 0.0))
	selected_skin = int(data.get("selected_skin", 0))
	selected_preset = int(data.get("selected_preset", 0))
	var unlocked: Variant = data.get("unlocked_skins", [true, false, false])
	if typeof(unlocked) == TYPE_ARRAY:
		unlocked_skins = [true, false, false]
		for i in mini(3, unlocked.size()):
			unlocked_skins[i] = bool(unlocked[i])
	_check_skin_unlocks()
	AudioServer.set_bus_volume_db(0, volume_db)
