extends Node
## Beat clock + procedural funk/DnB loop (or res://assets/music.ogg).

signal beat_hit(beat_index: int, is_drop: bool)
signal drop_started
signal drop_ended
signal bass_updated(energy: float)

const TARGET_BPM := 130.0
const INTRO_END := 16
const BUILDUP_END := 32
const DROP_END := 64
const LOOP_BEATS := 64

var bpm: float = TARGET_BPM
var beat_duration: float = 60.0 / TARGET_BPM
var beat_index: int = 0
var song_position: float = 0.0
var bass_energy: float = 0.0
var is_playing: bool = false
var is_drop: bool = false
var using_procedural: bool = true

var _player: AudioStreamPlayer
var _generator: AudioStreamGenerator
var _playback: AudioStreamGeneratorPlayback
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _phase: float = 0.0
var _sample_hz: float = 44100.0
var _beat_accum: float = 0.0
var _prev_output_latency: float = 0.0
var _time_begin: float = 0.0
var _time_delay: float = 0.0
var _procedural_beat: float = 0.0
var _hat_phase: float = 0.0
var _started_at_engine: float = 0.0


func _ready() -> void:
	_setup_spectrum()
	_setup_player()
	set_process(true)


func _setup_spectrum() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	var already := false
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectSpectrumAnalyzer:
			already = true
			break
	if not already:
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.1
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(bus_idx, fx)
	_spectrum = AudioServer.get_bus_effect_instance(bus_idx, AudioServer.get_bus_effect_count(bus_idx) - 1) as AudioEffectSpectrumAnalyzerInstance


func _setup_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BeatPlayer"
	_player.bus = "Master"
	add_child(_player)

	if ResourceLoader.exists("res://assets/music.ogg"):
		var stream: AudioStream = load("res://assets/music.ogg")
		_player.stream = stream
		using_procedural = false
		# Assume tagged BPM or default
		bpm = TARGET_BPM
	else:
		using_procedural = true
		_generator = AudioStreamGenerator.new()
		_generator.mix_rate = _sample_hz
		_generator.buffer_length = 0.1
		_player.stream = _generator
		bpm = TARGET_BPM

	beat_duration = 60.0 / bpm


func set_bpm(new_bpm: float) -> void:
	bpm = new_bpm
	beat_duration = 60.0 / bpm


func start() -> void:
	beat_index = 0
	song_position = 0.0
	_beat_accum = 0.0
	_procedural_beat = 0.0
	_phase = 0.0
	is_drop = false
	is_playing = true
	_started_at_engine = Time.get_ticks_usec() / 1_000_000.0
	_time_begin = Time.get_ticks_usec() / 1_000_000.0
	_time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	_player.play()
	if using_procedural:
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		_fill_buffer()
	# Emit first beat immediately for road sync
	_emit_beat(0)


func stop() -> void:
	is_playing = false
	if _player.playing:
		_player.stop()


func restart() -> void:
	stop()
	# Tiny yield-free restart
	start()


func get_calibrated_position() -> float:
	var offset_sec := GameState.audio_offset_ms / 1000.0
	if using_procedural:
		return song_position + offset_sec
	# File-backed stream timing (Godot docs pattern)
	var time := (Time.get_ticks_usec() / 1_000_000.0) - _time_begin - _time_delay + offset_sec
	time += AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	return maxf(0.0, time)


func get_section_for_beat(idx: int) -> String:
	var b := idx % LOOP_BEATS
	if b <= INTRO_END:
		return "intro"
	if b <= BUILDUP_END:
		return "buildup"
	if b <= DROP_END:
		return "drop"
	return "intro"


func get_beats_per_segment(idx: int) -> float:
	var section := get_section_for_beat(idx)
	match section:
		"intro":
			return 4.0
		"buildup":
			return 2.0
		"drop":
			# Peak denser turns mid-drop
			var local := idx % LOOP_BEATS
			if local >= 40 and local <= 56:
				return 0.5
			return 1.0
	return 4.0


func get_road_width(idx: int) -> float:
	var section := get_section_for_beat(idx)
	match section:
		"intro":
			return 170.0
		"buildup":
			return 145.0
		"drop":
			return 125.0
	return 170.0


func _process(delta: float) -> void:
	_update_bass()
	if not is_playing:
		return

	if using_procedural and _playback:
		_fill_buffer()

	var pos := get_calibrated_position()
	if using_procedural:
		song_position += delta
		pos = song_position + GameState.audio_offset_ms / 1000.0

	var next_beat_time := (beat_index + 1) * beat_duration
	while pos >= next_beat_time:
		beat_index += 1
		_emit_beat(beat_index)
		next_beat_time = (beat_index + 1) * beat_duration

	GameState.update_track_progress(float(beat_index % LOOP_BEATS), float(LOOP_BEATS))


func _emit_beat(idx: int) -> void:
	var section := get_section_for_beat(idx)
	var was_drop := is_drop
	is_drop = section == "drop"
	if is_drop and not was_drop:
		drop_started.emit()
		GameState.set_drop_multiplier(true)
	elif not is_drop and was_drop:
		drop_ended.emit()
		GameState.set_drop_multiplier(false)
	beat_hit.emit(idx, is_drop)


func _update_bass() -> void:
	if _spectrum == null:
		# Soft pulse fallback from beat phase
		var t := fmod(song_position, beat_duration) / beat_duration
		bass_energy = exp(-t * 6.0) * 0.8
		bass_updated.emit(bass_energy)
		return
	var mag := _spectrum.get_magnitude_for_frequency_range(20.0, 140.0)
	bass_energy = clampf((mag.x + mag.y) * 8.0, 0.0, 1.0)
	# Blend with kick envelope for procedural
	if using_procedural:
		var t := fmod(song_position, beat_duration) / beat_duration
		bass_energy = maxf(bass_energy, exp(-t * 8.0) * 0.9)
	bass_updated.emit(bass_energy)


func _fill_buffer() -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for i in frames:
		var sample := _synth_sample()
		_playback.push_frame(Vector2(sample, sample))
		_phase += 1.0 / _sample_hz
		_procedural_beat += 1.0 / _sample_hz


func _synth_sample() -> float:
	## Procedural funk / light DnB at bpm: kick, snare, hats, overdriven sub.
	var t := _phase
	var beat_pos := fmod(t, beat_duration)
	var sixteenth := beat_duration * 0.25
	var step := int(fmod(t, beat_duration * 4.0) / sixteenth)  # 0..15 in bar

	var out := 0.0

	# Kick every quarter
	var kick_env := _hit_env(beat_pos, 0.08)
	var kick := sin(TAU * (55.0 + 80.0 * kick_env) * beat_pos) * kick_env
	out += kick * 0.85

	# Snare on 2 and 4
	if step == 4 or step == 12:
		var sn_t := fmod(beat_pos, sixteenth)
		var sn_env := _hit_env(sn_t, 0.06)
		var snare := (randf() * 2.0 - 1.0) * sn_env * 0.55
		snare += sin(TAU * 180.0 * sn_t) * sn_env * 0.25
		out += snare

	# Hats every eighth, open-ish on offbeats
	var hat_step_t := fmod(t, sixteenth * 0.5)
	if int(t / (sixteenth * 0.5)) % 2 == 1:
		var hat_env := _hit_env(hat_step_t, 0.02)
		out += (randf() * 2.0 - 1.0) * hat_env * 0.18

	# Overdriven sub bass — funky offbeat accents
	var sub_hz := 55.0
	if step == 3 or step == 6 or step == 10 or step == 14:
		sub_hz = 73.0
	var sub := sin(TAU * sub_hz * t)
	sub = clampf(sub * 2.4, -1.0, 1.0) * 0.35  # soft clip / overdrive
	# Sidechain ducking with kick
	sub *= (1.0 - kick_env * 0.85)
	out += sub

	# Soft vinyl noise bed
	out += (randf() * 2.0 - 1.0) * 0.015

	return clampf(out, -1.0, 1.0)


func _hit_env(t: float, dur: float) -> float:
	if t < 0.0 or t > dur:
		return 0.0
	return exp(-t / dur * 5.0)
