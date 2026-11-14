extends Node2D
## Procedural isometric zigzag road: chunks ahead, cull behind camera.

signal perfect_drift_available(vertex: Vector2)
signal turn_vertex_spawned(vertex: Vector2, direction_sign: int)

const DIR_LEFT := Vector2(-0.70710678118, -0.70710678118)
const DIR_RIGHT := Vector2(0.70710678118, -0.70710678118)
const BASE_SPEED := 520.0
const LOOKAHEAD_TURNS := 15
const CULL_MARGIN := 900.0

var center_points: PackedVector2Array = PackedVector2Array()
var left_rail: PackedVector2Array = PackedVector2Array()
var right_rail: PackedVector2Array = PackedVector2Array()
var segment_meta: Array[Dictionary] = []  # {start_beat, beats, width, is_drop, vertex}
var turn_vertices: Array[Vector2] = []
var current_dir_sign: int = 1  # 1 = RIGHT next after LEFT stretch
var generated_beats: float = 0.0
var next_beat_cursor: float = 0.0

@onready var pavement: Polygon2D = $Pavement
@onready var rail_cyan: Line2D = $RailCyan
@onready var rail_magenta: Line2D = $RailMagenta
@onready var crystals: Node2D = $Crystals
@onready var glitch_overlay: ColorRect = $GlitchOverlay

var _crystal_scene_points: Array[Polygon2D] = []
var _autopilot: bool = true
var _drop_active: bool = false


func _ready() -> void:
	rail_cyan.width = 4.0
	rail_cyan.default_color = Color(0.0, 0.94, 1.0, 0.95)
	rail_cyan.antialiased = true
	rail_cyan.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rail_cyan.end_cap_mode = Line2D.LINE_CAP_ROUND
	rail_cyan.joint_mode = Line2D.LINE_JOINT_ROUND

	rail_magenta.width = 4.0
	rail_magenta.default_color = Color(1.0, 0.0, 0.33, 0.95)
	rail_magenta.antialiased = true
	rail_magenta.begin_cap_mode = Line2D.LINE_CAP_ROUND
	rail_magenta.end_cap_mode = Line2D.LINE_CAP_ROUND
	rail_magenta.joint_mode = Line2D.LINE_JOINT_ROUND

	pavement.color = Color(0.07, 0.07, 0.12, 1.0)  # #12121E

	if glitch_overlay:
		glitch_overlay.visible = false
		glitch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	AudioBeatManager.drop_started.connect(_on_drop_started)
	AudioBeatManager.drop_ended.connect(_on_drop_ended)

	reset_road()


func reset_road() -> void:
	center_points.clear()
	left_rail.clear()
	right_rail.clear()
	segment_meta.clear()
	turn_vertices.clear()
	for c in crystals.get_children():
		c.queue_free()
	_crystal_scene_points.clear()
	current_dir_sign = 1
	generated_beats = 0.0
	next_beat_cursor = 0.0
	# Seed start near bottom-center of portrait viewport in world space
	var start := Vector2(360, 1100)
	center_points.append(start)
	_append_rails_for_point(start, DIR_LEFT, 170.0)
	# Prefill
	while segment_meta.size() < LOOKAHEAD_TURNS:
		_generate_next_segment()
	_rebuild_meshes()


func set_autopilot(on: bool) -> void:
	_autopilot = on


func _on_drop_started() -> void:
	_drop_active = true
	if glitch_overlay and glitch_overlay.material:
		glitch_overlay.visible = true


func _on_drop_ended() -> void:
	_drop_active = false
	if glitch_overlay:
		glitch_overlay.visible = false


func _generate_next_segment() -> void:
	var beat_i := int(next_beat_cursor)
	var beats := AudioBeatManager.get_beats_per_segment(beat_i)
	var width := AudioBeatManager.get_road_width(beat_i)
	var bd := AudioBeatManager.beat_duration
	var seg_len := BASE_SPEED * bd * beats
	var dir := DIR_RIGHT if current_dir_sign > 0 else DIR_LEFT
	var last: Vector2 = center_points[center_points.size() - 1]
	var nxt := last + dir * seg_len

	center_points.append(nxt)
	_append_rails_for_point(nxt, dir, width)

	var vertex := nxt
	turn_vertices.append(vertex)
	_spawn_crystal(vertex)

	var meta := {
		"start_beat": next_beat_cursor,
		"beats": beats,
		"width": width,
		"is_drop": AudioBeatManager.get_section_for_beat(beat_i) == "drop",
		"vertex": vertex,
		"dir_sign": current_dir_sign,
		"a": last,
		"b": nxt,
	}
	segment_meta.append(meta)
	turn_vertex_spawned.emit(vertex, current_dir_sign)

	next_beat_cursor += beats
	generated_beats = next_beat_cursor
	current_dir_sign *= -1


func _append_rails_for_point(pt: Vector2, dir: Vector2, width: float) -> void:
	# Perpendicular in XZ-isometric plane; flip so cyan stays visually left.
	var normal := Vector2(-dir.y, dir.x).normalized()
	if normal.x > 0.0:
		normal = -normal
	left_rail.append(pt + normal * width * 0.5)
	right_rail.append(pt - normal * width * 0.5)


func _spawn_crystal(pos: Vector2) -> void:
	var poly := Polygon2D.new()
	var s := 10.0
	poly.polygon = PackedVector2Array([
		Vector2(0, -s * 1.4),
		Vector2(s * 0.7, 0),
		Vector2(0, s * 1.4),
		Vector2(-s * 0.7, 0),
	])
	poly.color = Color(0.0, 0.94, 1.0, 0.85)
	poly.position = pos
	# Soft additive glow via modulate pulse in _process
	crystals.add_child(poly)
	_crystal_scene_points.append(poly)


func maintain_chunks(camera_y: float) -> void:
	while segment_meta.size() < LOOKAHEAD_TURNS:
		_generate_next_segment()
		_rebuild_meshes()

	# Cull segments well behind camera (camera looks up / negative Y travel)
	var culled := false
	while segment_meta.size() > 3:
		var first: Dictionary = segment_meta[0]
		var b: Vector2 = first["b"]
		if b.y > camera_y + CULL_MARGIN:
			segment_meta.pop_front()
			if center_points.size() > 1:
				center_points.remove_at(0)
			if left_rail.size() > 1:
				left_rail.remove_at(0)
			if right_rail.size() > 1:
				right_rail.remove_at(0)
			if turn_vertices.size() > 0:
				turn_vertices.remove_at(0)
			if crystals.get_child_count() > 0:
				crystals.get_child(0).queue_free()
			culled = true
		else:
			break
	if culled:
		_rebuild_meshes()


func _rebuild_meshes() -> void:
	if left_rail.size() < 2 or right_rail.size() < 2:
		return
	rail_cyan.points = left_rail
	rail_magenta.points = right_rail

	# Pavement strip as triangle strip between left and right rails
	var poly := PackedVector2Array()
	for i in left_rail.size():
		poly.append(left_rail[i])
	for i in range(right_rail.size() - 1, -1, -1):
		poly.append(right_rail[i])
	pavement.polygon = poly


func get_closest_center_distance(world_pos: Vector2) -> float:
	var best := INF
	for seg in segment_meta:
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var closest := Geometry2D.get_closest_point_to_segment(world_pos, a, b)
		var d := world_pos.distance_to(closest)
		if d < best:
			best = d
	return best


func get_width_at(world_pos: Vector2) -> float:
	var best_d := INF
	var width := 170.0
	for seg in segment_meta:
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var closest := Geometry2D.get_closest_point_to_segment(world_pos, a, b)
		var d := world_pos.distance_to(closest)
		if d < best_d:
			best_d = d
			width = float(seg["width"])
	return width


func get_nearest_vertex(world_pos: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for v in turn_vertices:
		var d := world_pos.distance_to(v)
		if d < best_d:
			best_d = d
			best = v
	return best


func check_perfect_drift(car_pos: Vector2, turn_just_started: bool) -> bool:
	if not turn_just_started:
		return false
	var v := get_nearest_vertex(car_pos)
	return car_pos.distance_to(v) <= 30.0


func get_autopilot_dir(world_pos: Vector2) -> Vector2:
	## Steer toward upcoming center line for menu autopilot.
	if segment_meta.is_empty():
		return DIR_LEFT
	var best_seg: Dictionary = segment_meta[0]
	var best_d := INF
	for seg in segment_meta:
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var closest := Geometry2D.get_closest_point_to_segment(world_pos, a, b)
		var d := world_pos.distance_to(closest)
		if d < best_d:
			best_d = d
			best_seg = seg
	# Prefer next segment direction
	var idx := segment_meta.find(best_seg)
	if idx >= 0 and idx + 1 < segment_meta.size():
		best_seg = segment_meta[idx + 1]
	var sign: int = best_seg.get("dir_sign", 1)
	return DIR_RIGHT if sign > 0 else DIR_LEFT


func _process(_delta: float) -> void:
	# Pulse crystals with bass
	var pulse := 1.0 + AudioBeatManager.bass_energy * 0.45
	for c in crystals.get_children():
		if c is Polygon2D:
			(c as Polygon2D).scale = Vector2(pulse, pulse)
			var base_col := Color(0.0, 0.94, 1.0, 0.85)
			if _drop_active:
				base_col = Color(1.0, 0.0, 0.33, 0.9)
			(c as Polygon2D).color = base_col
