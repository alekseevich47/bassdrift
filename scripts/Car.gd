extends Node2D
## One-finger isometric drift car.

signal crashed
signal perfect_drift

const DIR_LEFT := Vector2(-0.70710678118, -0.70710678118)
const DIR_RIGHT := Vector2(0.70710678118, -0.70710678118)
const BASE_SPEED := 520.0
const VEL_LERP := 8.5
const HULL_LERP := 14.0
const SKID_SLIP_THRESHOLD := 0.15
const SKID_FADE := 3.0

var velocity_dir: Vector2 = DIR_LEFT
var target_dir: Vector2 = DIR_LEFT
var slip_angle: float = 0.0
var alive: bool = true
var autopilot: bool = true
var finger_down: bool = false
var road: Node2D = null
var _prev_target: Vector2 = DIR_LEFT
var _turn_edge: bool = false

@onready var hull: Polygon2D = $HullPolygon
@onready var cabin: Polygon2D = $Cabin
@onready var headlight_l: Polygon2D = $HeadlightL
@onready var headlight_r: Polygon2D = $HeadlightR
@onready var spark_particles: GPUParticles2D = $SparkTrail
@onready var crash_particles: GPUParticles2D = $CrashBurst

## World-space parent for skid Line2D (must NOT rotate/move with the car).
var skid_world: Node2D = null
var _skid_left: Line2D
var _skid_right: Line2D
var _active_skids: Array[Dictionary] = []
var _holding_skid: bool = false
var _skids_built: bool = false


func _ready() -> void:
	_apply_skin(GameState.get_skin_colors())
	GameState.skin_changed.connect(_on_skin_changed)
	spark_particles.emitting = false
	crash_particles.emitting = false
	_setup_particles()
	_make_additive(headlight_l)
	_make_additive(headlight_r)
	if has_node("HeadlightGlowL"):
		_make_additive($HeadlightGlowL)
	if has_node("HeadlightGlowR"):
		_make_additive($HeadlightGlowR)
	# Hide legacy child if present — skids live in world layer.
	if has_node("SkidMarks"):
		$SkidMarks.visible = false


func _make_additive(node: CanvasItem) -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	node.material = mat


func _setup_particles() -> void:
	spark_particles.amount = 24
	spark_particles.lifetime = 0.35
	spark_particles.explosiveness = 0.1
	spark_particles.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 40.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 120.0
	mat.gravity = Vector3(0, 80, 0)
	mat.scale_min = 1.5
	mat.scale_max = 3.0
	mat.color = Color(0.0, 0.94, 1.0, 1.0)
	spark_particles.process_material = mat
	spark_particles.z_index = 5

	crash_particles.amount = 48
	crash_particles.lifetime = 0.6
	crash_particles.one_shot = true
	crash_particles.explosiveness = 1.0
	crash_particles.local_coords = false
	var cmat := ParticleProcessMaterial.new()
	cmat.direction = Vector3(0, 0, 0)
	cmat.spread = 180.0
	cmat.initial_velocity_min = 80.0
	cmat.initial_velocity_max = 280.0
	cmat.gravity = Vector3(0, 120, 0)
	cmat.scale_min = 2.0
	cmat.scale_max = 5.0
	cmat.color = Color(1.0, 0.3, 0.6, 1.0)
	crash_particles.process_material = cmat


func set_skid_parent(parent: Node2D) -> void:
	skid_world = parent
	_build_skid_emitters()


func _build_skid_emitters() -> void:
	if skid_world == null:
		return
	# Tear down previous emitters if rebinding
	if _skid_left and is_instance_valid(_skid_left):
		_skid_left.queue_free()
	if _skid_right and is_instance_valid(_skid_right):
		_skid_right.queue_free()
	_clear_frozen_skids()

	_skid_left = _make_skid_line()
	_skid_right = _make_skid_line()
	skid_world.add_child(_skid_left)
	skid_world.add_child(_skid_right)
	_skids_built = true


func _make_skid_line() -> Line2D:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.7, 0.7, 0.85, 0.55)
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = -1
	line.top_level = false
	return line


func _on_skin_changed(_idx: int) -> void:
	_apply_skin(GameState.get_skin_colors())


func _apply_skin(colors: Array) -> void:
	hull.color = colors[0]
	cabin.color = colors[0].lightened(0.15)
	headlight_l.color = colors[2]
	headlight_r.color = colors[2]
	hull.modulate = Color(1, 1, 1, 1)
	if has_node("AccentStripe"):
		$AccentStripe.color = colors[1]


func reset_car(pos: Vector2) -> void:
	global_position = pos
	velocity_dir = DIR_LEFT
	target_dir = DIR_LEFT
	_prev_target = DIR_LEFT
	slip_angle = 0.0
	alive = true
	finger_down = false
	rotation = velocity_dir.angle() + PI * 0.5
	hull.rotation = 0.0
	spark_particles.emitting = false
	visible = true
	modulate = Color.WHITE
	_holding_skid = false
	if _skid_left and is_instance_valid(_skid_left):
		_skid_left.clear_points()
	if _skid_right and is_instance_valid(_skid_right):
		_skid_right.clear_points()
	_clear_frozen_skids()


func _clear_frozen_skids() -> void:
	for entry in _active_skids:
		var left: Line2D = entry.get("left")
		var right: Line2D = entry.get("right")
		if left and is_instance_valid(left):
			left.queue_free()
		if right and is_instance_valid(right):
			right.queue_free()
	_active_skids.clear()
	# Also wipe any leftover children on the world layer (except active emitters)
	if skid_world:
		for child in skid_world.get_children():
			if child != _skid_left and child != _skid_right:
				child.queue_free()


func set_road(r: Node2D) -> void:
	road = r


func _unhandled_input(event: InputEvent) -> void:
	if autopilot or not alive or GameState.phase != GameState.Phase.PLAYING:
		return
	if event.is_action_pressed("drift"):
		finger_down = true
		get_viewport().set_input_as_handled()
	elif event.is_action_released("drift"):
		finger_down = false
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not alive:
		return

	_update_target_dir()
	_detect_turn_edge()

	velocity_dir = velocity_dir.lerp(target_dir, clampf(VEL_LERP * delta, 0.0, 1.0)).normalized()
	global_position += velocity_dir * BASE_SPEED * delta

	var vel_angle := velocity_dir.angle()
	var tgt_angle := target_dir.angle()
	slip_angle = wrapf(tgt_angle - vel_angle, -PI, PI)

	hull.rotation = lerp_angle(hull.rotation, slip_angle, clampf(HULL_LERP * delta, 0.0, 1.0))
	rotation = vel_angle + PI * 0.5

	_update_skids(delta)
	_check_crash()
	_check_perfect()
	_score_tick(delta)


func _update_target_dir() -> void:
	if autopilot and road and road.has_method("get_autopilot_dir"):
		target_dir = road.get_autopilot_dir(global_position)
		return
	if finger_down:
		target_dir = DIR_RIGHT
	else:
		target_dir = DIR_LEFT


func _detect_turn_edge() -> void:
	_turn_edge = false
	if _prev_target.dot(target_dir) < 0.9:
		_turn_edge = true
	_prev_target = target_dir


func _update_skids(delta: float) -> void:
	if not _skids_built or skid_world == null:
		return

	var slipping := absf(slip_angle) > SKID_SLIP_THRESHOLD
	if slipping and alive:
		if not _holding_skid:
			_holding_skid = true
			_skid_left.clear_points()
			_skid_right.clear_points()
		# World-space points — skid_world stays at identity under Main.
		var side := velocity_dir.orthogonal().normalized() * 8.0
		var gp := global_position
		_skid_left.add_point(skid_world.to_local(gp - side))
		_skid_right.add_point(skid_world.to_local(gp + side))
		if _skid_left.get_point_count() > 80:
			_skid_left.remove_point(0)
			_skid_right.remove_point(0)
	elif _holding_skid:
		_holding_skid = false
		_freeze_skid_pair()

	var i := 0
	while i < _active_skids.size():
		var entry: Dictionary = _active_skids[i]
		entry["age"] = float(entry["age"]) + delta
		var a := 1.0 - float(entry["age"]) / SKID_FADE
		var left: Line2D = entry["left"]
		var right: Line2D = entry["right"]
		if a <= 0.0 or not is_instance_valid(left) or not is_instance_valid(right):
			if is_instance_valid(left):
				left.queue_free()
			if is_instance_valid(right):
				right.queue_free()
			_active_skids.remove_at(i)
			continue
		var col := Color(0.7, 0.7, 0.85, 0.55 * a)
		left.default_color = col
		right.default_color = col
		_active_skids[i] = entry
		i += 1


func _freeze_skid_pair() -> void:
	if _skid_left.get_point_count() < 2:
		return
	var l := _make_skid_line()
	var r := _make_skid_line()
	l.points = _skid_left.points
	r.points = _skid_right.points
	skid_world.add_child(l)
	skid_world.add_child(r)
	_active_skids.append({"left": l, "right": r, "age": 0.0})
	_skid_left.clear_points()
	_skid_right.clear_points()


func _check_crash() -> void:
	if autopilot or road == null or GameState.phase != GameState.Phase.PLAYING:
		return
	if not road.has_method("get_closest_center_distance"):
		return
	var dist: float = road.get_closest_center_distance(global_position)
	var width: float = road.get_width_at(global_position)
	if dist > width * 0.5:
		_do_crash()


func _do_crash() -> void:
	if not alive:
		return
	alive = false
	GameState.phase = GameState.Phase.CRASHING
	GameState.break_combo()
	crash_particles.restart()
	crash_particles.emitting = true
	spark_particles.emitting = false
	Engine.time_scale = 0.25
	crashed.emit()
	get_tree().create_timer(0.4, true, false, true).timeout.connect(_after_crash)


func _after_crash() -> void:
	Engine.time_scale = 1.0
	GameState.trigger_game_over()


func _check_perfect() -> void:
	if autopilot or not alive or road == null:
		return
	if not _turn_edge:
		return
	if road.has_method("check_perfect_drift") and road.check_perfect_drift(global_position, true):
		GameState.register_perfect_drift()
		perfect_drift.emit()
		_flash_sparks()


func _flash_sparks() -> void:
	spark_particles.emitting = true
	get_tree().create_timer(0.35).timeout.connect(func():
		if is_instance_valid(spark_particles):
			spark_particles.emitting = false
	)


func _score_tick(delta: float) -> void:
	if autopilot or not alive or GameState.phase != GameState.Phase.PLAYING:
		return
	var slip_bonus := 1.0 + absf(slip_angle) * 2.0
	GameState.add_score(int(12.0 * delta * 60.0 * slip_bonus))
