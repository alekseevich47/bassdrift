extends RefCounted

## Roadside touge dressing: rails, sodium lights, turn signs, trees, rocks, and city blocks.

const _Road := preload("res://scripts/track/RealisticRoadGenerator.gd")


static func light_texture() -> Texture2D:
	if _light_tex != null:
		return _light_tex
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	_light_tex = texture
	return texture


static var _light_tex: Texture2D


func populate(parent: Node2D, road: Dictionary, visual: Dictionary, quality: String) -> void:
	var curve: Curve2D = road.get("curve")
	if curve == null:
		return
	var length := float(road.get("length", 0.0))
	var half := float(road.get("half_width", 104.0))
	var speed := float(road.get("speed", 400.0))
	if length < 8.0:
		return
	var root := Node2D.new()
	root.name = "Scenery"
	parent.add_child(root)
	_rails(root, curve, length, half, visual)
	_lights_and_props(root, curve, length, half, visual, quality)
	_signs(root, curve, road.get("apexes", []), half, speed, visual)
	_city(root, curve, length, half, visual, quality)


func _rails(parent: Node2D, curve: Curve2D, length: float, half: float, visual: Dictionary) -> void:
	var left := Line2D.new()
	var right := Line2D.new()
	var rail := Color(visual.get("rail", Color(0.62, 0.63, 0.66)))
	for line in [left, right]:
		line.width = 5.0
		line.default_color = rail
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.z_index = 2
		parent.add_child(line)
	var step := 22.0
	var count := int(length / step)
	var road = _Road.new()
	for i in count + 1:
		var frame: Dictionary = road.sample(curve, min(float(i) * step, length))
		var origin: Vector2 = frame["origin"]
		var side: Vector2 = frame["right"]
		left.add_point(origin - side * (half + 8.0))
		right.add_point(origin + side * (half + 8.0))
		if i % 16 == 0:
			_post(parent, origin - side * (half + 8.0), rail)
			_post(parent, origin + side * (half + 8.0), rail)


func _post(parent: Node2D, at: Vector2, color: Color) -> void:
	var post := Polygon2D.new()
	post.polygon = PackedVector2Array([
		Vector2(-3, -8), Vector2(3, -8), Vector2(3, 8), Vector2(-3, 8),
	])
	post.color = color.darkened(0.25)
	post.position = at
	post.z_index = 2
	parent.add_child(post)


func _lights_and_props(parent: Node2D, curve: Curve2D, length: float, half: float, visual: Dictionary, quality: String) -> void:
	var spacing := 620.0
	var light_budget := 28
	if quality == "high":
		spacing = 460.0
		light_budget = 48
	elif quality == "low":
		spacing = 860.0
		light_budget = 14
	var road = _Road.new()
	var lights := 0
	var dist := 180.0
	var previous := Vector2.DOWN
	while dist < length - 80.0:
		var frame: Dictionary = road.sample(curve, dist)
		var forward: Vector2 = frame["forward"]
		var right: Vector2 = frame["right"]
		var origin: Vector2 = frame["origin"]
		var turn := previous.cross(forward)
		var outside := 1.0 if turn >= 0.0 else -1.0
		if abs(turn) < 0.002:
			outside = 1.0 if int(dist / spacing) % 2 == 0 else -1.0
		var shoulder: Vector2 = origin + right * outside * (half + 34.0)
		if lights < light_budget:
			_streetlight(parent, shoulder, forward, visual)
			lights += 1
		if int(dist / spacing) % 2 == 0:
			_tree(parent, origin + right * outside * (half + 110.0), visual, int(dist))
		elif int(dist / spacing) % 3 == 1:
			_rock(parent, origin + right * outside * (half + 150.0), visual, int(dist))
		previous = forward
		dist += spacing


func _streetlight(parent: Node2D, at: Vector2, forward: Vector2, visual: Dictionary) -> void:
	var rig := Node2D.new()
	rig.position = at
	rig.rotation = forward.angle()
	rig.z_index = 6
	parent.add_child(rig)
	var pole := Polygon2D.new()
	pole.polygon = PackedVector2Array([
		Vector2(-3, -6), Vector2(3, -6), Vector2(4, 54), Vector2(-4, 54),
	])
	pole.color = Color(0.25, 0.26, 0.28)
	rig.add_child(pole)
	var lamp := Polygon2D.new()
	lamp.polygon = PackedVector2Array([
		Vector2(-16, -8), Vector2(10, -4), Vector2(10, 4), Vector2(-16, 8),
	])
	lamp.color = Color(visual.get("light_color", Color(1.0, 0.86, 0.55)))
	rig.add_child(lamp)
	var light := PointLight2D.new()
	light.texture = light_texture()
	light.texture_scale = 3.4
	light.color = Color(visual.get("light_color", Color(1.0, 0.84, 0.52)))
	light.energy = 0.85
	light.position = Vector2(-8, 0)
	rig.add_child(light)


func _tree(parent: Node2D, at: Vector2, visual: Dictionary, salt: int) -> void:
	var tree := Node2D.new()
	tree.position = at
	tree.z_index = 5
	parent.add_child(tree)
	var trunk := Polygon2D.new()
	trunk.polygon = PackedVector2Array([
		Vector2(-4, 8), Vector2(4, 8), Vector2(3, 28), Vector2(-3, 28),
	])
	trunk.color = Color(0.28, 0.18, 0.1)
	tree.add_child(trunk)
	var crown := Polygon2D.new()
	var radius := 18.0 + float(salt % 11)
	crown.polygon = PackedVector2Array([
		Vector2(0, -radius * 1.3),
		Vector2(radius, 8),
		Vector2(-radius, 10),
	])
	crown.color = Color(visual.get("tree", Color(0.08, 0.16, 0.09)))
	tree.add_child(crown)


func _rock(parent: Node2D, at: Vector2, visual: Dictionary, salt: int) -> void:
	var rock := Polygon2D.new()
	var wobble := float((salt % 7) - 3)
	rock.polygon = PackedVector2Array([
		Vector2(-16, 6), Vector2(-8, -10 + wobble), Vector2(10, -8), Vector2(18, 5), Vector2(4, 12), Vector2(-10, 11),
	])
	rock.color = Color(visual.get("rock", Color(0.32, 0.32, 0.34)))
	rock.position = at
	rock.z_index = 4
	parent.add_child(rock)


func _signs(parent: Node2D, curve: Curve2D, apexes: Array, half: float, speed: float, visual: Dictionary) -> void:
	var road = _Road.new()
	var length := curve.get_baked_length()
	var sign_color := Color(visual.get("sign", Color(0.92, 0.72, 0.16)))
	var placed := 0
	for apex in apexes:
		if typeof(apex) != TYPE_DICTIONARY:
			continue
		if int(apex.get("lane", 1)) != TrackLanes.APEX and str(apex.get("section", "")) != "drop":
			continue
		if placed >= 24:
			break
		var at: float = float(apex.get("s", 0.0)) - maxf(speed * 0.55, 80.0)
		if at < 40.0 or at > length - 20.0:
			continue
		var frame: Dictionary = road.sample(curve, at)
		var dir := int(apex.get("dir", 1))
		var right: Vector2 = frame["right"]
		var origin: Vector2 = frame["origin"]
		var outside := -float(dir if dir != 0 else 1)
		var sign := Node2D.new()
		sign.position = origin + right * outside * (half + 26.0)
		sign.rotation = (frame["forward"] as Vector2).angle()
		sign.z_index = 7
		parent.add_child(sign)
		var board := Polygon2D.new()
		board.polygon = PackedVector2Array([
			Vector2(-12, -14), Vector2(12, -14), Vector2(12, 14), Vector2(-12, 14),
		])
		board.color = sign_color
		sign.add_child(board)
		var arrow := Polygon2D.new()
		var flip := -1.0 if dir < 0 else 1.0
		arrow.polygon = PackedVector2Array([
			Vector2(-6.0 * flip, -6), Vector2(7.0 * flip, 0), Vector2(-6.0 * flip, 6),
		])
		arrow.color = Color(0.12, 0.1, 0.08)
		sign.add_child(arrow)
		var stick := Polygon2D.new()
		stick.polygon = PackedVector2Array([
			Vector2(-2, 14), Vector2(2, 14), Vector2(2, 36), Vector2(-2, 36),
		])
		stick.color = Color(0.35, 0.28, 0.16)
		sign.add_child(stick)
		placed += 1


func _city(parent: Node2D, curve: Curve2D, length: float, half: float, visual: Dictionary, quality: String) -> void:
	var layer := Node2D.new()
	layer.name = "CityParallax"
	layer.z_index = -8
	parent.add_child(layer)
	var road = _Road.new()
	var step := 980.0 if quality != "low" else 1400.0
	var dist := 260.0
	var index := 0
	var window := Color(visual.get("window", Color(0.95, 0.78, 0.42)))
	while dist < length:
		var frame: Dictionary = road.sample(curve, dist)
		var right: Vector2 = frame["right"]
		var origin: Vector2 = frame["origin"]
		var side := 1.0 if index % 2 == 0 else -1.0
		var block := Node2D.new()
		block.position = origin + right * side * (half + 280.0)
		block.rotation = (frame["forward"] as Vector2).angle()
		layer.add_child(block)
		var floors := 3 + (index % 4)
		var body := Polygon2D.new()
		var height := 36.0 + float(floors) * 18.0
		body.polygon = PackedVector2Array([
			Vector2(-28, -height * 0.5),
			Vector2(28, -height * 0.5),
			Vector2(34, height * 0.5),
			Vector2(-34, height * 0.5),
		])
		body.color = Color(visual.get("building", Color(0.07, 0.08, 0.1)))
		block.add_child(body)
		for row in mini(floors, 5):
			var glow := Polygon2D.new()
			glow.polygon = PackedVector2Array([
				Vector2(-16, -height * 0.35 + float(row) * 14.0),
				Vector2(16, -height * 0.35 + float(row) * 14.0),
				Vector2(16, -height * 0.35 + float(row) * 14.0 + 6.0),
				Vector2(-16, -height * 0.35 + float(row) * 14.0 + 6.0),
			])
			glow.color = window
			glow.color.a = 0.45 if row % 2 == 0 else 0.8
			block.add_child(glow)
		dist += step
		index += 1
	_skyline(parent, visual)


func _skyline(parent: Node2D, visual: Dictionary) -> void:
	var backdrop := ParallaxBackground.new()
	backdrop.layer = -20
	parent.add_child(backdrop)
	var band := ParallaxLayer.new()
	band.motion_scale = Vector2(0.22, 0.22)
	band.motion_mirroring = Vector2(1280, 0)
	backdrop.add_child(band)
	var base := Color(visual.get("skyline", Color(0.05, 0.05, 0.08)))
	var cursor := 0.0
	var index := 0
	while cursor < 1280.0:
		var width := 48.0 + float((index * 37) % 70)
		var height := 80.0 + float((index * 53) % 160)
		var tower := Polygon2D.new()
		tower.polygon = PackedVector2Array([
			Vector2(cursor, 1280.0),
			Vector2(cursor, 1280.0 - height),
			Vector2(cursor + width, 1280.0 - height),
			Vector2(cursor + width, 1280.0),
		])
		tower.color = base.lightened(0.02 * float(index % 3))
		band.add_child(tower)
		cursor += width + 18.0
		index += 1
