extends Node2D

## One-finger drift car. Hold steers to the right edge, release to the left.
## Guardrail contact costs speed and durability. It never ends the run by itself.

signal scraped(force: float)
signal wrecked
signal hp_changed(hp: float, hp_max: float)

var lateral := 0.0
var lateral_vel := 0.0
var slip := 0.0
var speed := 0.0
var nominal_speed := 420.0
var holding := false
var half_width := 104.0
var hp := 3.0
var max_hp := 3.0
var alive := true
var boost_left := 0.0

var _grip := 0.58
var _drift := 0.62
var _weight := 1.0
var _accel := 0.7
var _angle := 0.0
var _armor := 0.0
var _magnet := 0.0
var _turbo_boost := 0.0
var _scrape_cd := 0.0
var _spark_time := 0.0
var _paint_shift := false
var _paint_time := 0.0
var _primary := Color(0.9, 0.9, 0.92)
var _secondary := Color(0.1, 0.1, 0.12)
var _accent := Color(1.0, 0.18, 0.54)
var _visuals := false
var _body: Polygon2D
var _cabin: Polygon2D
var _stripe: Polygon2D
var _brake_l: Polygon2D
var _brake_r: Polygon2D
var _brake_glow: PointLight2D
var _smoke_l: CPUParticles2D
var _smoke_r: CPUParticles2D
var _sparks: CPUParticles2D


func configure(profile: Dictionary) -> void:
	var stats: Dictionary = profile.get("stats", {})
	_grip = clampf(float(stats.get("grip", 58.0)) / 100.0, 0.05, 1.0)
	_drift = clampf(float(stats.get("drift", 62.0)) / 100.0, 0.05, 1.0)
	_weight = clampf(float(stats.get("weight", 100.0)) / 110.0, 0.6, 1.45)
	_accel = clampf(float(stats.get("accel", 70.0)) / 100.0, 0.05, 1.0)
	_angle = float(profile.get("drift_angle", 0.0))
	_armor = clampf(float(profile.get("armor_durability", 0.0)), 0.0, 0.75)
	_magnet = clampf(float(profile.get("magnet_snap", 0.0)), 0.0, 0.6)
	_turbo_boost = max(float(profile.get("turbo_boost_sec", 0.0)), 0.0)
	nominal_speed = max(float(profile.get("nominal_speed", 420.0)), 40.0)
	half_width = max(float(profile.get("half_width", 104.0)), 40.0)
	speed = nominal_speed
	var extra := float(profile.get("extra_hits", 0.0))
	max_hp = 3.0 + max(extra, 0.0)
	hp = max_hp
	alive = true
	lateral = 0.0
	lateral_vel = 0.0
	slip = 0.0
	boost_left = 0.0
	var paint: Dictionary = profile.get("paint", {})
	_primary = Color.html(str(paint.get("primary", "#e6e6ea")))
	_secondary = Color.html(str(paint.get("secondary", "#16161c")))
	_accent = Color.html(str(paint.get("accent", "#ff2d8a")))
	_paint_shift = bool(profile.get("color_shift", false))
	if str(paint.get("style", "gloss")) == "metallic":
		_primary = _primary.lightened(0.12)
	_apply_colors()
	hp_changed.emit(hp, max_hp)


func set_holding(held: bool) -> void:
	holding = held


func add_boost(seconds: float) -> void:
	boost_left = max(boost_left, seconds + _turbo_boost)


func set_quality(quality: String) -> void:
	var amount := 12
	if quality == "low":
		amount = 5
	elif quality == "high":
		amount = 18
	if _smoke_l != null:
		_smoke_l.amount = amount
		_smoke_r.amount = amount


func holds_line(dir: int) -> bool:
	if not alive:
		return false
	if dir > 0:
		return holding and lateral > half_width * 0.18
	if dir < 0:
		return (not holding) and lateral < -half_width * 0.18
	return abs(lateral) <= half_width * 0.4


func tick(delta: float, target_lateral: float) -> void:
	if not alive:
		return
	var remaining: float = minf(maxf(delta, 0.0), 0.05)
	var omega := lerpf(7.2, 10.5, _grip) / _weight
	var zeta := lerpf(1.05, 0.48, _drift)
	var magnet := clampf(_magnet * 2.4, 0.0, 1.4)
	while remaining > 0.0:
		var step: float = minf(remaining, 0.008)
		var aimed := target_lateral
		if magnet > 0.0:
			lateral = lerpf(lateral, target_lateral, 1.0 - exp(-magnet * step))
		var accel := (aimed - lateral) * omega * omega - lateral_vel * 2.0 * zeta * omega
		lateral_vel += accel * step
		lateral_vel = clampf(lateral_vel, -640.0, 640.0)
		lateral += lateral_vel * step
		remaining -= step
	var max_slip := deg_to_rad(12.0 + _drift * 22.0 + _angle)
	var slip_target := clampf(-lateral_vel * 0.0045, -max_slip, max_slip)
	slip = lerpf(slip, slip_target, 1.0 - exp(-12.0 * delta))
	var boost := 1.12 if boost_left > 0.0 else 1.0
	var desired := nominal_speed * boost
	var accel_rate := lerpf(90.0, 240.0, _accel)
	if speed < desired:
		speed = min(speed + accel_rate * delta, desired)
	else:
		speed = max(speed - accel_rate * 0.45 * delta, desired)
	boost_left = max(boost_left - delta, 0.0)
	_scrape_cd = max(_scrape_cd - delta, 0.0)
	var limit := half_width - 18.0
	if abs(lateral) > limit:
		_contact(abs(lateral) - limit)
		lateral = clampf(lateral, -limit, limit)
		if abs(lateral_vel) > 40.0:
			lateral_vel *= -0.25
	_paint_time += delta
	if _paint_shift:
		var shifted := _primary
		shifted.h = fposmod(_primary.h + _paint_time * 0.08, 1.0)
		if _body != null:
			_body.color = shifted
	_update_fx(delta)


func rear_points() -> Array:
	var back := global_position - Vector2.from_angle(rotation) * 24.0
	var side := Vector2.from_angle(rotation + PI * 0.5) * 12.0
	return [back + side, back - side]


func _contact(overlap: float) -> void:
	if _scrape_cd > 0.0 or not alive:
		_spark_time = max(_spark_time, 0.05)
		return
	_scrape_cd = 0.42
	var damage := (1.0 - _armor) * clampf(0.75 + overlap * 0.04, 0.75, 1.35)
	hp = max(hp - damage, 0.0)
	speed = max(speed * 0.84, nominal_speed * 0.4)
	_spark_time = 0.28
	scraped.emit(clampf(overlap / 18.0, 0.25, 1.0))
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		alive = false
		speed = 0.0
		wrecked.emit()


func _ready() -> void:
	_build_visuals()
	_visuals = true
	_apply_colors()


func _build_visuals() -> void:
	var shadow := Polygon2D.new()
	shadow.polygon = _body_shape()
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.position = Vector2(5, 7)
	shadow.z_index = -1
	add_child(shadow)
	for wheel in [Vector2(14, -16), Vector2(14, 16), Vector2(-18, -16), Vector2(-18, 16)]:
		var tire := Polygon2D.new()
		tire.polygon = PackedVector2Array([
			Vector2(-7, -4), Vector2(8, -4), Vector2(8, 4), Vector2(-7, 4),
		])
		tire.color = Color(0.08, 0.08, 0.09)
		tire.position = wheel
		add_child(tire)
	_body = Polygon2D.new()
	_body.polygon = _body_shape()
	add_child(_body)
	_cabin = Polygon2D.new()
	_cabin.polygon = PackedVector2Array([
		Vector2(8, -9), Vector2(-8, -10), Vector2(-16, 0), Vector2(-8, 10), Vector2(8, 9),
	])
	add_child(_cabin)
	_stripe = Polygon2D.new()
	_stripe.polygon = PackedVector2Array([
		Vector2(30, -3), Vector2(-30, -3), Vector2(-30, 3), Vector2(30, 3),
	])
	add_child(_stripe)
	_brake_l = _lamp(Vector2(-30, -10))
	_brake_r = _lamp(Vector2(-30, 10))
	add_child(_brake_l)
	add_child(_brake_r)
	var head_l := _headlight(Vector2(30, -9))
	var head_r := _headlight(Vector2(30, 9))
	add_child(head_l)
	add_child(head_r)
	_brake_glow = PointLight2D.new()
	_brake_glow.texture = preload("res://scripts/track/ScenerySpawner.gd").light_texture()
	_brake_glow.texture_scale = 1.6
	_brake_glow.color = Color(1.0, 0.16, 0.08)
	_brake_glow.energy = 0.0
	_brake_glow.position = Vector2(-30, 0)
	add_child(_brake_glow)
	_smoke_l = _smoke(Vector2(-22, -12))
	_smoke_r = _smoke(Vector2(-22, 12))
	add_child(_smoke_l)
	add_child(_smoke_r)
	_sparks = _spark_fx()
	add_child(_sparks)


func _body_shape() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(34, 0), Vector2(22, -12), Vector2(4, -16), Vector2(-24, -16),
		Vector2(-32, -10), Vector2(-32, 10), Vector2(-24, 16), Vector2(4, 16), Vector2(22, 12),
	])


func _lamp(at: Vector2) -> Polygon2D:
	var lamp := Polygon2D.new()
	lamp.polygon = PackedVector2Array([
		Vector2(-4, -3), Vector2(3, -2), Vector2(3, 2), Vector2(-4, 3),
	])
	lamp.position = at
	lamp.color = Color(0.35, 0.05, 0.04)
	return lamp


func _headlight(at: Vector2) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = preload("res://scripts/track/ScenerySpawner.gd").light_texture()
	light.texture_scale = 6.5
	light.color = Color(1.0, 0.95, 0.82)
	light.energy = 1.25
	light.position = at
	return light


func _smoke(at: Vector2) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.amount = 12
	particles.lifetime = 0.55
	particles.explosiveness = 0.05
	particles.direction = Vector2(-1, 0)
	particles.spread = 26.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 16.0
	particles.initial_velocity_max = 42.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.7
	particles.color = Color(0.75, 0.75, 0.78, 0.38)
	particles.local_coords = false
	particles.emitting = false
	return particles


func _spark_fx() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.position = Vector2(0, 16)
	particles.amount = 18
	particles.lifetime = 0.22
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.direction = Vector2(0.2, 1)
	particles.spread = 40.0
	particles.gravity = Vector2(0, 80)
	particles.initial_velocity_min = 70.0
	particles.initial_velocity_max = 160.0
	particles.scale_amount_min = 0.4
	particles.scale_amount_max = 1.1
	particles.color = Color(1.0, 0.62, 0.22, 0.95)
	particles.local_coords = false
	particles.emitting = false
	return particles


func _apply_colors() -> void:
	if not _visuals:
		return
	_body.color = _primary
	_cabin.color = _secondary
	_stripe.color = _accent


func _update_fx(delta: float) -> void:
	if not _visuals:
		return
	var drifting: bool = absf(slip) > 0.12 or absf(lateral_vel) > 80.0
	var brake := 0.35
	if holding or drifting:
		brake = 1.0
	_brake_l.color = Color(1.0, 0.08, 0.05, brake)
	_brake_r.color = _brake_l.color
	_brake_glow.energy = 0.15 + brake * 0.7
	var smoke_on := drifting and alive
	_smoke_l.emitting = smoke_on
	_smoke_r.emitting = smoke_on
	if _spark_time > 0.0:
		_spark_time = maxf(_spark_time - delta, 0.0)
		if not _sparks.emitting:
			if _sparks.has_method("restart"):
				_sparks.restart()
			_sparks.emitting = true
	elif _sparks.emitting and _sparks.one_shot:
		_sparks.emitting = false
