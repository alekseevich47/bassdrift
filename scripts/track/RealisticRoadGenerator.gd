extends RefCounted

## Smooth Catmull-Rom road whose apex spacing tracks the beat map.
## Distance between apexes is car_speed * Δt, then clamped so a hairpin
## cannot fold the ribbon through itself.

const HALF_WIDTH := 104.0
const SHOULDER := 48.0
const SAMPLE_STEP := 18.0


func generate(beat_map: Dictionary, car_speed: float) -> Dictionary:
	var speed: float = maxf(float(car_speed), 40.0)
	var duration: float = maxf(float(beat_map.get("duration_sec", 1.0)), 0.05)
	var turn_scale := float(beat_map.get("turn_scale", 1.0))
	var beats: Array = beat_map.get("beats", [])
	if beats.is_empty():
		beats = [{
			"t": min(duration * 0.5, max(duration - 0.05, 0.02)),
			"lane": TrackLanes.CENTER,
			"kind": TrackLanes.KIND_TAP,
			"dur": 0.0,
			"dir": 0,
			"section": "intro",
		}]
	var points := PackedVector2Array()
	var pos := Vector2.ZERO
	var heading := PI * 0.5
	points.append(pos)
	var poly_s := 0.0
	var t_cursor := 0.0
	var apexes: Array = []
	var min_radius := HALF_WIDTH * 1.32
	for beat in beats:
		if typeof(beat) != TYPE_DICTIONARY:
			continue
		var note: Dictionary = beat
		var t := float(note.get("t", t_cursor))
		var span: float = maxf(t - t_cursor, 0.02)
		var target := speed * span
		var section := str(note.get("section", "build"))
		var lane := int(note.get("lane", TrackLanes.CENTER))
		var dir := int(note.get("dir", TrackLanes.direction_for(lane, 1)))
		var desired := TrackLanes.desired_turn(lane, section, dir, turn_scale)
		var max_angle := clampf(target / min_radius, 0.04, 2.45)
		var turn := clampf(desired, -max_angle, max_angle)
		var steps: int = 12 if absf(turn) >= 1.0 else 7
		var step_len := target / float(steps)
		var step_head := turn / float(steps)
		for _step in steps:
			heading += step_head
			pos += Vector2.from_angle(heading) * step_len
			points.append(pos)
			poly_s += step_len
		apexes.append({
			"s": poly_s,
			"poly_s": poly_s,
			"t": t,
			"lane": lane,
			"kind": str(note.get("kind", TrackLanes.KIND_TAP)),
			"dur": float(note.get("dur", 0.0)),
			"dir": dir,
			"section": section,
			"point": pos,
		})
		t_cursor = t
	var tail := duration - t_cursor
	if tail > 0.05:
		var tail_len := speed * tail
		var tail_steps := maxi(int(tail_len / 28.0), 2)
		var tail_step := tail_len / float(tail_steps)
		for _step in tail_steps:
			pos += Vector2.from_angle(heading) * tail_step
			points.append(pos)
			poly_s += tail_step
	var curve := _catmull(points)
	_fit_length(curve, poly_s)
	var baked := curve.get_baked_length()
	for apex in apexes:
		var point: Vector2 = apex["point"]
		var along: float = float(apex["poly_s"]) * baked / maxf(poly_s, 0.001)
		if curve.has_method("get_closest_offset"):
			apex["s"] = curve.get_closest_offset(point)
		else:
			apex["s"] = along
		apex.erase("point")
		apex.erase("poly_s")
	return {
		"ok": true,
		"curve": curve,
		"length": baked,
		"half_width": HALF_WIDTH,
		"shoulder": SHOULDER,
		"speed": speed,
		"apexes": apexes,
		"road_mesh": _ribbon(curve, baked, HALF_WIDTH, true),
		"shoulder_mesh": _ribbon(curve, baked, HALF_WIDTH + SHOULDER, false),
	}


func sample(curve: Curve2D, distance: float) -> Dictionary:
	var length: float = maxf(curve.get_baked_length(), 0.001)
	var clamped := clampf(distance, 0.0, length)
	var frame := curve.sample_baked_with_rotation(clamped)
	var forward := frame.x
	if forward.length_squared() < 0.000001:
		forward = Vector2.DOWN
	else:
		forward = forward.normalized()
	var right := Vector2(forward.y, -forward.x)
	return {
		"origin": frame.origin,
		"forward": forward,
		"right": right,
		"s": clamped,
	}


func apex_spacing_error(road: Dictionary) -> float:
	var apexes: Array = road.get("apexes", [])
	var speed: float = maxf(float(road.get("speed", 1.0)), 0.001)
	var worst := 0.0
	for i in range(1, apexes.size()):
		var dt := float(apexes[i]["t"]) - float(apexes[i - 1]["t"])
		if dt <= 0.001:
			continue
		var ds := float(apexes[i]["s"]) - float(apexes[i - 1]["s"])
		var err: float = absf(ds / speed - dt) / dt
		worst = max(worst, err)
	return worst


func _catmull(points: PackedVector2Array) -> Curve2D:
	var curve := Curve2D.new()
	var count := points.size()
	if count == 0:
		return curve
	for i in count:
		var point := points[i]
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, count - 1)]
		if i == 0:
			prev = point - (next - point)
		if i == count - 1:
			next = point + (point - prev)
		var tangent := (next - prev) / 6.0
		curve.add_point(point, -tangent, tangent)
	curve.bake_interval = 10.0
	return curve


func _fit_length(curve: Curve2D, target: float) -> void:
	if curve.point_count < 2 or target <= 1.0:
		return
	for _pass in 3:
		var baked := curve.get_baked_length()
		if baked <= 1.0:
			return
		var factor := target / baked
		if abs(factor - 1.0) < 0.012:
			return
		for i in curve.point_count:
			curve.set_point_position(i, curve.get_point_position(i) * factor)
			curve.set_point_in(i, curve.get_point_in(i) * factor)
			curve.set_point_out(i, curve.get_point_out(i) * factor)


func _ribbon(curve: Curve2D, length: float, half: float, asphalt: bool) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := maxi(int(length / SAMPLE_STEP), 2)
	var previous_left := Vector3.ZERO
	var previous_right := Vector3.ZERO
	var previous_v := 0.0
	var started := false
	var tint := Color(1, 1, 1, 1) if asphalt else Color(0.16, 0.17, 0.14, 1)
	for i in count + 1:
		var dist: float = minf(float(i) * SAMPLE_STEP, length)
		var frame := sample(curve, dist)
		var origin: Vector2 = frame["origin"]
		var right: Vector2 = frame["right"]
		var left_pt := origin - right * half
		var right_pt := origin + right * half
		var v := dist / 240.0
		if started:
			_triangle(tool, previous_left, Vector3(left_pt.x, left_pt.y, 0.0), previous_right, Vector2(0.0, previous_v), Vector2(0.0, v), Vector2(1.0, previous_v), tint)
			_triangle(tool, previous_right, Vector3(left_pt.x, left_pt.y, 0.0), Vector3(right_pt.x, right_pt.y, 0.0), Vector2(1.0, previous_v), Vector2(0.0, v), Vector2(1.0, v), tint)
		previous_left = Vector3(left_pt.x, left_pt.y, 0.0)
		previous_right = Vector3(right_pt.x, right_pt.y, 0.0)
		previous_v = v
		started = true
	return tool.commit()


func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, tint: Color) -> void:
	tool.set_color(tint)
	tool.set_uv(uva)
	tool.add_vertex(a)
	tool.set_color(tint)
	tool.set_uv(uvb)
	tool.add_vertex(b)
	tool.set_color(tint)
	tool.set_uv(uvc)
	tool.add_vertex(c)
