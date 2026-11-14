extends Camera2D

## Chase camera. Lookahead keeps the apex in view, with shake and a beat punch.

var lookahead := 390.0
var shake := 0.0
var pulse := 0.0

var _ready_frame := false


func follow(anchor: Vector2, forward: Vector2, delta: float, speed_ratio: float, slip: float) -> void:
	var aim := forward
	if aim.length_squared() < 0.0001:
		aim = Vector2.DOWN
	else:
		aim = aim.normalized()
	var lead: float = clampf(lookahead + maxf(speed_ratio - 1.0, 0.0) * 80.0, 280.0, 520.0)
	var target := anchor + aim * lead
	var facing := aim.angle() + PI * 0.5
	if not _ready_frame or delta <= 0.0:
		global_position = target
		rotation = facing
		_ready_frame = true
	else:
		var blend := 1.0 - exp(-delta * 7.5)
		global_position = global_position.lerp(target, blend)
		rotation = lerp_angle(rotation, facing, 1.0 - exp(-delta * 9.0))
	shake = move_toward(shake, 0.0, delta * 36.0)
	pulse = max(pulse - delta * 2.5, 0.0)
	var kick := Vector2.ZERO
	if shake > 0.2:
		kick = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	var lean := clampf(slip, -0.7, 0.7) * 34.0
	offset = Vector2(lean, -pulse * 16.0) + kick
	var punch := 1.0 + pulse * 0.045
	var pull: float = clampf(0.98 - maxf(speed_ratio - 1.0, 0.0) * 0.06, 0.9, 1.02)
	zoom = Vector2(punch * pull, punch * pull)


func add_shake(amount: float) -> void:
	shake = clampf(shake + amount, 0.0, 28.0)


func beat(amount: float) -> void:
	pulse = clampf(max(pulse, amount), 0.0, 1.0)


func reset_follow() -> void:
	_ready_frame = false
