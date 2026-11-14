extends Camera2D
## Lead-follow camera with beat micro-zoom and drop shake.

@export var follow_target: Node2D
@export var lead_distance: float = 220.0
@export var follow_lerp: float = 6.0

var _zoom_pulse: float = 1.0
var _shake_amp: float = 0.0
var _shake_time: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE
var _drop_shake: bool = false


func _ready() -> void:
	_base_zoom = zoom
	AudioBeatManager.beat_hit.connect(_on_beat)
	AudioBeatManager.drop_started.connect(func(): _drop_shake = true)
	AudioBeatManager.drop_ended.connect(func(): _drop_shake = false)
	AudioBeatManager.bass_updated.connect(_on_bass)


func _on_beat(_idx: int, is_drop: bool) -> void:
	_zoom_pulse = 1.04
	if is_drop:
		_shake_amp = maxf(_shake_amp, 6.0)
		_shake_time = 0.12


func _on_bass(energy: float) -> void:
	if _drop_shake:
		_shake_amp = maxf(_shake_amp, energy * 4.0)


func _process(delta: float) -> void:
	if follow_target and is_instance_valid(follow_target):
		var lead := Vector2.ZERO
		if follow_target.get("velocity_dir") != null:
			lead = follow_target.velocity_dir * lead_distance
		var desired := follow_target.global_position + lead
		global_position = global_position.lerp(desired, clampf(follow_lerp * delta, 0.0, 1.0))

	# Beat micro-zoom 1.0 → 1.04 return ~0.15s
	_zoom_pulse = lerpf(_zoom_pulse, 1.0, clampf(delta / 0.15, 0.0, 1.0))
	var bass_boost := 1.0 + AudioBeatManager.bass_energy * 0.02
	zoom = _base_zoom * _zoom_pulse * bass_boost

	# Shake
	if _shake_time > 0.0:
		_shake_time -= delta
		offset = Vector2(
			randf_range(-_shake_amp, _shake_amp),
			randf_range(-_shake_amp, _shake_amp)
		)
		_shake_amp = lerpf(_shake_amp, 0.0, delta * 8.0)
	else:
		offset = offset.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		if _drop_shake:
			offset += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
