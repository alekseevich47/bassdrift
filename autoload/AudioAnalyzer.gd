extends Node

## Beat-map facade for campaign charts and user music.
## load_user_audio reads ogg, mp3, and 16-bit PCM wav.
## analyze_to_beat_map / generate_campaign_track return schema version 1:
##   t, lane, kind, dur, plus dir, energy, and section.
## WAV uses an RMS onset envelope. Ogg/mp3 use a container BPM hint or byte energy.
## Campaign styles render through AudioStreamGenerator.

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

var _pcm := PackedFloat32Array()
var _pcm_rate := 0
var _synth_on := false
var _synth_time := 0.0
var _synth_bpm := 120.0
var _synth_duration := 60.0
var _synth_style := "phonk"

const SYNTH_RATE := 22050
const MUSIC_PHONK := "phonk"
const MUSIC_SYNTHWAVE := "synthwave"
const MUSIC_DNB := "dnb"
const MUSIC_CYBER := "cyberpunk_bass"


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
	_capture_pcm(loaded)
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
	var heard: Dictionary = _detect_tempo()
	var bpm: float = float(heard.get("bpm", 0.0))
	var method: String = str(heard.get("method", "grid_v1"))
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
		"method": method,
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
	var mods: Dictionary = difficulty_modifiers()
	analysis_started.emit("campaign")
	profile["method"] = "campaign_v1"
	profile["difficulty"] = str(mods.get("id", "drive"))
	profile["density"] = float(mods.get("density", 1.0))
	profile["turn_scale"] = float(mods.get("turn_scale", 1.0))
	profile["music_style"] = music_style_for(str(profile.get("style", style)))
	profile["seed"] = absi(hash(str(profile.get("level_id", "")) + ":" + str(profile.get("style", style)) + ":" + str(mods.get("id", "drive"))))
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
	_pcm = PackedFloat32Array()
	_pcm_rate = 0


func beat_map_fields() -> PackedStringArray:
	return PackedStringArray([
		"version", "ok", "source", "style", "level_id", "chapter_id", "weather",
		"bpm", "duration_sec", "offset_ms", "beats", "sections", "method",
		"music_style", "difficulty",
	])


func music_style_for(style_or_level: String) -> String:
	var key := style_or_level
	if _catalog_ready() and GameData.has_level(style_or_level):
		key = str(GameData.get_level(style_or_level).get("style", style_or_level))
	match key:
		"haruna_dry_night", "phonk", MUSIC_PHONK:
			return MUSIC_PHONK
		"shuto_rain", "synthwave", "synth", MUSIC_SYNTHWAVE:
			return MUSIC_SYNTHWAVE
		"docklands_fog", "dnb", "drum_and_bass", MUSIC_DNB:
			return MUSIC_DNB
		"apex_storm", "cyberpunk", "cyberpunk_bass", "cyber", MUSIC_CYBER:
			return MUSIC_CYBER
		_:
			return MUSIC_PHONK


func difficulty_modifiers() -> Dictionary:
	var id := "drive"
	var save := get_node_or_null("/root/SaveManager")
	if save != null and save.has_method("get_difficulty"):
		id = str(save.call("get_difficulty"))
	match id:
		"chill":
			return {"id": "chill", "density": 0.7, "turn_scale": 0.8, "speed_scale": 0.88}
		"hardcore":
			return {"id": "hardcore", "density": 1.3, "turn_scale": 1.16, "speed_scale": 1.1}
		_:
			return {"id": "drive", "density": 1.0, "turn_scale": 1.0, "speed_scale": 1.0}


func begin_campaign_performance(beat_map: Dictionary) -> AudioStreamGenerator:
	end_campaign_performance()
	_synth_on = true
	_synth_time = 0.0
	_synth_bpm = maxf(float(beat_map.get("bpm", DEFAULT_BPM)), 1.0)
	_synth_duration = maxf(float(beat_map.get("duration_sec", 60.0)), 0.5)
	_synth_style = str(beat_map.get("music_style", music_style_for(str(beat_map.get("style", "")))))
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SYNTH_RATE
	generator.buffer_length = 0.25
	return generator


func render_campaign(playback: AudioStreamPlayback) -> void:
	if not _synth_on or playback == null or not (playback is AudioStreamGeneratorPlayback):
		return
	var gen := playback as AudioStreamGeneratorPlayback
	var available := gen.get_frames_available()
	if available <= 0:
		return
	var frames := PackedVector2Array()
	frames.resize(available)
	var index := 0
	while index < available:
		var sample := _synth_sample()
		frames[index] = Vector2(sample, sample)
		_synth_time += 1.0 / float(SYNTH_RATE)
		index += 1
	if gen.has_method("push_buffer"):
		gen.push_buffer(frames)
		return
	for frame in frames:
		gen.push_frame(frame)


func end_campaign_performance() -> void:
	_synth_on = false


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
	if bytes.size() > 64 * 1024 * 1024:
		return _fail("file_too_large", path)
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
		"pcm": _mono_pcm(pcm, channels, sample_rate),
	}


func _build_grid(profile: Dictionary) -> Dictionary:
	var mods: Dictionary = difficulty_modifiers()
	var bpm: float = float(maxf(float(profile.get("bpm", DEFAULT_BPM)), 1.0))
	var duration: float = float(maxf(float(profile.get("duration_sec", 60.0)), 0.05))
	var density: float = float(profile.get("density", mods.get("density", 1.0)))
	var turn_scale: float = float(profile.get("turn_scale", mods.get("turn_scale", 1.0)))
	var difficulty: String = str(profile.get("difficulty", mods.get("id", "drive")))
	var style: String = str(profile.get("style", ""))
	var beats: Array = _compose_beats(bpm, duration, density, difficulty, absi(int(profile.get("seed", 1))))
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
		"method": str(profile.get("method", "campaign_v1")),
		"music_style": str(profile.get("music_style", music_style_for(style))),
		"difficulty": difficulty,
		"turn_scale": turn_scale,
		"density": density,
	}


func _sections(duration: float) -> Array:
	var intro: float = float(minf(8.0, duration * 0.15))
	var build: float = float(minf(16.0, duration * 0.25))
	var drop: float = float(maxf(duration * 0.4, 0.0))
	var used: float = intro + build + drop
	if used > duration:
		drop = float(maxf(duration - intro - build, 0.0))
		used = intro + build + drop
	return [
		{"id": "intro", "t": 0.0, "dur": intro},
		{"id": "build", "t": intro, "dur": build},
		{"id": "drop", "t": intro + build, "dur": drop},
		{"id": "outro", "t": used, "dur": maxf(duration - used, 0.0)},
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


func _capture_pcm(loaded: Dictionary) -> void:
	_pcm = PackedFloat32Array()
	_pcm_rate = 0
	var samples = loaded.get("pcm", null)
	if samples is PackedFloat32Array:
		_pcm = samples
		_pcm_rate = int(loaded.get("sample_rate", 0))


func _mono_pcm(pcm: PackedByteArray, channels: int, sample_rate: int) -> PackedFloat32Array:
	var bytes_per_frame := 2 * channels
	if bytes_per_frame <= 0 or sample_rate <= 0:
		return PackedFloat32Array()
	var frames: int = pcm.size() / bytes_per_frame
	var limit: int = mini(frames, sample_rate * 90)
	var mono := PackedFloat32Array()
	mono.resize(limit)
	var index := 0
	while index < limit:
		var base: int = index * bytes_per_frame
		var sample: float = float(pcm.decode_s16(base)) / 32768.0
		if channels == 2 and base + 2 < pcm.size():
			sample = (sample + float(pcm.decode_s16(base + 2)) / 32768.0) * 0.5
		mono[index] = sample
		index += 1
	return mono


func _detect_tempo() -> Dictionary:
	if _pcm.size() > 64 and _pcm_rate > 0:
		var hop: int = maxi(int(float(_pcm_rate) / 100.0), 64)
		var from_pcm: float = _bpm_from_envelope(_rms_envelope(_pcm, _pcm_rate), float(hop) / float(_pcm_rate))
		if from_pcm > 1.0:
			return {"bpm": from_pcm, "method": "pcm_onset_v1"}
	var hinted: float = _bpm_hint(loaded_stream)
	if hinted > 1.0:
		return {"bpm": hinted, "method": "bpm_hint_v1"}
	if loaded_format == "ogg" or loaded_format == "mp3":
		var from_bytes: float = _container_bpm(loaded_path, loaded_duration_sec)
		if from_bytes > 1.0:
			return {"bpm": from_bytes, "method": "container_energy_v1"}
	return {"bpm": 0.0, "method": "grid_v1"}


func _rms_envelope(samples: PackedFloat32Array, sample_rate: int) -> PackedFloat32Array:
	var hop: int = maxi(int(float(sample_rate) / 100.0), 64)
	var windows: int = samples.size() / hop
	var env := PackedFloat32Array()
	env.resize(windows)
	var index := 0
	while index < windows:
		var start := index * hop
		var energy := 0.0
		var step := 0
		while step < hop:
			var sample: float = samples[start + step]
			energy += sample * sample
			step += 1
		env[index] = sqrt(energy / float(hop))
		index += 1
	return env


func _container_bpm(path: String, duration: float) -> float:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0.0
	var length := file.get_length()
	if length < 4096 or duration <= 0.05:
		file.close()
		return 0.0
	var windows: int = mini(int(length / 2048), 480)
	var env := PackedFloat32Array()
	env.resize(windows)
	var index := 0
	while index < windows:
		file.seek(index * 2048)
		var chunk := file.get_buffer(2048)
		var energy := 0.0
		var cursor := 0
		while cursor < chunk.size():
			energy += absf(float(chunk[cursor]) - 128.0)
			cursor += 8
		env[index] = energy
		index += 1
	file.close()
	return _bpm_from_envelope(env, duration / float(maxi(windows, 1)))


func _bpm_from_envelope(env: PackedFloat32Array, hop_sec: float) -> float:
	if env.size() < 8 or hop_sec <= 0.0:
		return 0.0
	var flux := PackedFloat32Array()
	flux.resize(env.size())
	flux[0] = 0.0
	var low: float = env[0]
	var high: float = env[0]
	var index := 1
	while index < env.size():
		flux[index] = maxf(env[index] - env[index - 1], 0.0)
		low = minf(low, env[index])
		high = maxf(high, env[index])
		index += 1
	if high <= 0.00001 or (high - low) / maxf(high, 0.000001) < 0.08:
		return 0.0
	var best_bpm := 0.0
	var best_score := 0.0
	var bpm := 80.0
	while bpm <= 170.0:
		var lag: int = int(round((60.0 / bpm) / hop_sec))
		if lag >= 2 and lag < flux.size() / 2:
			var score := 0.0
			var count := 0
			var cursor := lag
			while cursor < flux.size():
				score += flux[cursor] * flux[cursor - lag]
				count += 1
				cursor += 1
			if count > 0:
				score /= float(count)
			if score > best_score:
				best_score = score
				best_bpm = bpm
		bpm += 1.0
	return best_bpm


func _compose_beats(bpm: float, duration: float, density: float, difficulty: String, seed: int) -> Array:
	var beat_sec: float = 60.0 / maxf(bpm, 1.0)
	var beats: Array = []
	var t: float = beat_sec
	var index := 0
	var run := 0
	var dir: int = -1 if seed % 2 == 0 else 1
	var sections: Array = _sections(duration)
	while t < duration - 0.02 and index < 20000:
		var section: String = _section_at(sections, t)
		var step: float = beat_sec
		if difficulty == "hardcore" and (section == "drop" or section == "build"):
			step = beat_sec * 0.5
		var skip := false
		if difficulty == "chill" and section != "drop" and index % 2 == 1:
			skip = true
		elif density < 0.95 and section != "drop" and index % 3 == 2:
			skip = true
		if skip:
			t += step
			index += 1
			continue
		var run_len := 6
		if section == "intro" or section == "outro":
			run_len = 8
		elif section == "drop":
			run_len = 4
		run += 1
		var lane := TrackLanes.RIGHT if dir > 0 else TrackLanes.LEFT
		var kind := TrackLanes.KIND_TAP
		var dur := 0.0
		var note_dir := dir
		if run >= run_len:
			lane = TrackLanes.CENTER
			kind = TrackLanes.KIND_TAP
			note_dir = 0
			dir = -dir
			run = 0
		elif section == "drop" and run == run_len - 1:
			lane = TrackLanes.APEX
			kind = TrackLanes.KIND_HOLD
			dur = step * 1.25
		elif index % 11 == 5 and section != "intro":
			lane = TrackLanes.CENTER
			kind = TrackLanes.KIND_BOOST
			note_dir = 0
		var energy := 0.45
		if section == "drop":
			energy = 0.9
		elif section == "build":
			energy = 0.65
		beats.append({
			"t": snappedf(t, 0.0001),
			"lane": lane,
			"kind": kind,
			"dur": snappedf(dur, 0.0001),
			"dir": note_dir,
			"energy": energy,
			"section": section,
		})
		t += step
		index += 1
	if beats.is_empty():
		beats.append({
			"t": snappedf(minf(duration * 0.5, maxf(duration - 0.02, 0.02)), 0.0001),
			"lane": TrackLanes.CENTER,
			"kind": TrackLanes.KIND_TAP,
			"dur": 0.0,
			"dir": 0,
			"energy": 0.4,
			"section": "intro",
		})
	return beats


func _section_at(sections: Array, time_sec: float) -> String:
	var name := "build"
	for section in sections:
		if typeof(section) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = section
		var start: float = float(spec.get("t", 0.0))
		var span: float = maxf(float(spec.get("dur", 0.0)), 0.0)
		if time_sec >= start and time_sec < start + span:
			name = str(spec.get("id", name))
	return name


func _synth_sample() -> float:
	if _synth_time > _synth_duration:
		return 0.0
	var beat_len: float = 60.0 / maxf(_synth_bpm, 1.0)
	var beat_pos: float = _synth_time / beat_len
	var beat_idx: int = int(floor(beat_pos))
	var frac: float = beat_pos - float(beat_idx)
	var eighth: float = fposmod(frac, 0.5)
	var kick: float = exp(-frac * 14.0) if frac < 0.45 else 0.0
	var snare := 0.0
	if beat_idx % 2 == 1 and frac < 0.3:
		snare = exp(-frac * 20.0)
	var hat := 0.12 if eighth < 0.035 else 0.0
	var bass: float = _synth_bass(beat_idx, frac)
	var mix: float = bass * 0.42 + kick * 0.55 + snare * 0.28 + hat
	return tanh(clampf(mix, -1.4, 1.4))


func _synth_bass(beat_idx: int, frac: float) -> float:
	var freq := 55.0
	match _synth_style:
		MUSIC_SYNTHWAVE:
			freq = 65.0 if beat_idx % 4 < 2 else 49.0
		MUSIC_DNB:
			freq = 49.0 if frac < 0.5 else 73.5
		MUSIC_CYBER:
			freq = 41.0 + (8.0 if beat_idx % 3 == 2 else 0.0)
		_:
			freq = 55.0 if beat_idx % 2 == 0 else 41.0
	var phase: float = _synth_time * TAU * freq
	if _synth_style == MUSIC_PHONK:
		return 0.85 if sin(phase) >= 0.0 else -0.85
	if _synth_style == MUSIC_DNB:
		return sin(phase) * 0.7 + sin(phase * 1.012) * 0.3
	if _synth_style == MUSIC_CYBER:
		return sin(phase + sin(_synth_time * TAU * 18.0) * 1.4)
	var saw: float = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
	return saw * 0.55 + sin(phase * 2.0) * 0.2
