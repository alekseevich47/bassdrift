extends Node

## Beat-map facade for campaign charts and user music.
## load_user_audio reads ogg, mp3, and 16-bit PCM wav.
## analyze_to_beat_map / generate_campaign_track return schema version 1:
##   t (seconds), lane (TrackLanes), kind (tap|hold|boost), dur (seconds).
## The grid is deterministic. Spectral onset detection can replace _build_grid later
## without changing these signatures.

signal analysis_started(source: String)
signal analysis_finished(beat_map: Dictionary)
signal analysis_failed(reason: String)

const BEATMAP_VERSION := 1
const DEFAULT_BPM := 120.0
const SUPPORTED_EXTENSIONS: Array = ["ogg", "mp3", "wav"]

var loaded_path := ""
var loaded_stream: AudioStream = null
var loaded_duration_sec := 0.0
var loaded_format := ""
var last_beat_map: Dictionary = {}


func load_user_audio(path: String) -> Dictionary:
	if path.is_empty():
		return _fail("empty_path", path)
	if not FileAccess.file_exists(path):
		return _fail("file_missing", path)
	var ext := path.get_extension().to_lower()
	if not SUPPORTED_EXTENSIONS.has(ext):
		return _fail("unsupported_format", path)
	var loaded := _decode(path, ext)
	if not bool(loaded.get("ok", false)):
		clear_loaded_audio()
		analysis_failed.emit(str(loaded.get("error", "decode_failed")))
		return loaded
	loaded_path = path
	loaded_stream = loaded["stream"]
	loaded_duration_sec = float(loaded["duration_sec"])
	loaded_format = ext
	return {
		"ok": true,
		"path": path,
		"format": ext,
		"duration_sec": loaded_duration_sec,
		"sample_rate": int(loaded.get("sample_rate", 0)),
		"channels": int(loaded.get("channels", 0)),
		"bpm_hint": _bpm_hint(loaded_stream),
	}


func analyze_to_beat_map(audio_path: String = "") -> Dictionary:
	if not audio_path.is_empty():
		var loaded := load_user_audio(audio_path)
		if not bool(loaded.get("ok", false)):
			return {
				"version": BEATMAP_VERSION,
				"ok": false,
				"error": str(loaded.get("error", "load_failed")),
				"path": audio_path,
				"beats": [],
				"sections": [],
			}
	if loaded_stream == null or loaded_path.is_empty():
		analysis_failed.emit("no_audio")
		return {
			"version": BEATMAP_VERSION,
			"ok": false,
			"error": "no_audio",
			"path": "",
			"beats": [],
			"sections": [],
		}
	analysis_started.emit("user")
	var bpm := _bpm_hint(loaded_stream)
	if bpm <= 1.0:
		bpm = DEFAULT_BPM
	var beat_map := _build_grid({
		"style": "user",
		"level_id": "",
		"chapter_id": "",
		"weather": "",
		"bpm": bpm,
		"duration_sec": loaded_duration_sec if loaded_duration_sec > 0.0 else 60.0,
		"display_name": loaded_path.get_file(),
		"source": "user",
		"method": "grid_v1",
		"seed": absi(hash(loaded_path)),
	})
	last_beat_map = beat_map
	analysis_finished.emit(beat_map)
	return beat_map


func generate_campaign_track(style: String) -> Dictionary:
	if not _catalog_ready():
		analysis_failed.emit("catalog_unavailable")
		return {
			"version": BEATMAP_VERSION,
			"ok": false,
			"error": "catalog_unavailable",
			"style": style,
			"beats": [],
			"sections": [],
		}
	var profile := GameData.resolve_track_profile(style)
	if profile.is_empty():
		analysis_failed.emit("unknown_style")
		return {
			"version": BEATMAP_VERSION,
			"ok": false,
			"error": "unknown_style",
			"style": style,
			"beats": [],
			"sections": [],
		}
	analysis_started.emit("campaign")
	profile["method"] = "grid_v1"
	profile["seed"] = absi(hash(str(profile.get("level_id", "")) + ":" + str(profile.get("style", style))))
	var beat_map := _build_grid(profile)
	last_beat_map = beat_map
	analysis_finished.emit(beat_map)
	return beat_map


func get_last_beat_map() -> Dictionary:
	return last_beat_map.duplicate(true)


func get_loaded_stream() -> AudioStream:
	return loaded_stream


func clear_loaded_audio() -> void:
	loaded_path = ""
	loaded_stream = null
	loaded_duration_sec = 0.0
	loaded_format = ""


func beat_map_fields() -> PackedStringArray:
	return PackedStringArray([
		"version", "ok", "source", "style", "level_id", "chapter_id", "weather",
		"bpm", "duration_sec", "offset_ms", "beats", "sections", "method",
	])


func _decode(path: String, ext: String) -> Dictionary:
	match ext:
		"ogg":
			return _load_ogg(path)
		"mp3":
			return _load_mp3(path)
		"wav":
			return _load_wav(path)
		_:
			return _fail("unsupported_format", path)


func _load_ogg(path: String) -> Dictionary:
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		return _fail("decode_failed", path)
	var duration := stream.get_length()
	if duration <= 0.0:
		return _fail("empty_audio", path)
	return {"ok": true, "stream": stream, "duration_sec": duration, "sample_rate": 0, "channels": 0}


func _load_mp3(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("file_missing", path)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		return _fail("empty_audio", path)
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	var duration := stream.get_length()
	if duration <= 0.0:
		return _fail("decode_failed", path)
	return {"ok": true, "stream": stream, "duration_sec": duration, "sample_rate": 0, "channels": 0}


func _load_wav(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("file_missing", path)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 44:
		return _fail("wav_too_small", path)
	if _fourcc(bytes, 0) != "RIFF" or _fourcc(bytes, 8) != "WAVE":
		return _fail("wav_header", path)
	var channels := 0
	var sample_rate := 0
	var bits := 0
	var audio_format := 0
	var pcm := PackedByteArray()
	var cursor := 12
	while cursor + 8 <= bytes.size():
		var chunk := _fourcc(bytes, cursor)
		var size := bytes.decode_u32(cursor + 4)
		var start := cursor + 8
		if size < 0 or start + size > bytes.size():
			return _fail("wav_chunk", path)
		if chunk == "fmt ":
			if size < 16:
				return _fail("wav_format", path)
			audio_format = bytes.decode_u16(start)
			channels = bytes.decode_u16(start + 2)
			sample_rate = bytes.decode_u32(start + 4)
			bits = bytes.decode_u16(start + 14)
		elif chunk == "data":
			pcm = bytes.slice(start, start + size)
		var padded := size + (size % 2)
		cursor = start + padded
	if audio_format != 1 or bits != 16 or (channels != 1 and channels != 2) or sample_rate <= 0 or pcm.is_empty():
		return _fail("wav_unsupported", path)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = channels == 2
	stream.data = pcm
	var bytes_per_frame := 2 * channels
	var duration := float(pcm.size()) / float(bytes_per_frame * sample_rate)
	if duration <= 0.0:
		return _fail("empty_audio", path)
	return {
		"ok": true,
		"stream": stream,
		"duration_sec": duration,
		"sample_rate": sample_rate,
		"channels": channels,
	}


func _build_grid(profile: Dictionary) -> Dictionary:
	var bpm: float = float(max(float(profile.get("bpm", DEFAULT_BPM)), 1.0))
	var duration: float = float(max(float(profile.get("duration_sec", 60.0)), 0.05))
	var beat_sec: float = 60.0 / bpm
	var lead_in: float = beat_sec
	if duration <= beat_sec * 2.0:
		lead_in = float(max(duration * 0.25, 0.01))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.get("seed", 1))
	var beats: Array = []
	var t: float = lead_in
	var index := 0
	while t < duration - 0.001 and index < 10000:
		var lane := rng.randi_range(TrackLanes.LEFT, TrackLanes.RIGHT)
		var kind := TrackLanes.KIND_TAP
		var dur := 0.0
		if index % 8 == 7:
			lane = TrackLanes.APEX
			kind = TrackLanes.KIND_HOLD
			dur = beat_sec * 2.0
		elif index % 4 == 0:
			lane = TrackLanes.CENTER
			kind = TrackLanes.KIND_BOOST
		beats.append({
			"t": snappedf(t, 0.0001),
			"lane": lane,
			"kind": kind,
			"dur": snappedf(dur, 0.0001),
		})
		t += beat_sec
		index += 1
	return {
		"version": BEATMAP_VERSION,
		"ok": true,
		"source": str(profile.get("source", "campaign")),
		"style": str(profile.get("style", "")),
		"level_id": str(profile.get("level_id", "")),
		"chapter_id": str(profile.get("chapter_id", "")),
		"weather": str(profile.get("weather", "")),
		"display_name": str(profile.get("display_name", "")),
		"bpm": bpm,
		"duration_sec": duration,
		"offset_ms": 0,
		"beats": beats,
		"sections": _sections(duration),
		"method": str(profile.get("method", "grid_v1")),
	}


func _sections(duration: float) -> Array:
	var intro: float = float(min(8.0, duration * 0.15))
	var build: float = float(min(16.0, duration * 0.25))
	var drop: float = float(max(duration * 0.4, 0.0))
	var used: float = intro + build + drop
	if used > duration:
		drop = float(max(duration - intro - build, 0.0))
		used = intro + build + drop
	return [
		{"id": "intro", "t": 0.0, "dur": intro},
		{"id": "build", "t": intro, "dur": build},
		{"id": "drop", "t": intro + build, "dur": drop},
		{"id": "outro", "t": used, "dur": max(duration - used, 0.0)},
	]


func _bpm_hint(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	var hinted := 0.0
	if stream is AudioStreamOggVorbis:
		hinted = float((stream as AudioStreamOggVorbis).bpm)
	elif stream is AudioStreamMP3:
		hinted = float((stream as AudioStreamMP3).bpm)
	if hinted >= 40.0 and hinted <= 240.0:
		return hinted
	return 0.0


func _fourcc(bytes: PackedByteArray, offset: int) -> String:
	if offset < 0 or offset + 4 > bytes.size():
		return ""
	return bytes.slice(offset, offset + 4).get_string_from_ascii()


func _fail(reason: String, path: String) -> Dictionary:
	return {"ok": false, "error": reason, "path": path, "duration_sec": 0.0}


func _catalog_ready() -> bool:
	return get_node_or_null("/root/GameData") != null
