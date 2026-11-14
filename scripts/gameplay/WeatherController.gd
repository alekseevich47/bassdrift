extends Node

## Chapter weather: dry night, wet rain, fog dawn, and sunset storm.

signal lightning

var weather_id := "dry_night"
var rain_amount := 0.0
var fog_amount := 0.0
var wet_amount := 0.0
var flash := 0.0

var _lightning := false
var _cooldown := 1.2
var _palette: Dictionary = {}
var _asphalt: ShaderMaterial
var _rain: ShaderMaterial
var _vignette: ShaderMaterial
var _fog: ColorRect
var _flash_rect: ColorRect


func apply_preset(weather_id_in: String) -> void:
	weather_id = _canonical(weather_id_in)
	_palette = _presets()[weather_id]
	rain_amount = float(_palette["rain"])
	fog_amount = float(_palette["fog"])
	wet_amount = float(_palette["wet"])
	_lightning = bool(_palette["lightning"])
	_push_uniforms()


func palette() -> Dictionary:
	if _palette.is_empty():
		apply_preset(weather_id)
	return _palette.duplicate(true)


func bind(asphalt: ShaderMaterial, rain: ShaderMaterial, vignette: ShaderMaterial, fog: ColorRect, flash_rect: ColorRect) -> void:
	_asphalt = asphalt
	_rain = rain
	_vignette = vignette
	_fog = fog
	_flash_rect = flash_rect
	_push_uniforms()


func update(delta: float) -> void:
	if _lightning:
		_cooldown -= delta
		if _cooldown <= 0.0:
			flash = 1.0
			_cooldown = randf_range(1.6, 3.8)
			lightning.emit()
	if flash > 0.0:
		flash = move_toward(flash, 0.0, delta * 2.6)
	_push_uniforms()


func _push_uniforms() -> void:
	if _palette.is_empty():
		return
	if _asphalt != null:
		_asphalt.set_shader_parameter("wet", wet_amount)
		_asphalt.set_shader_parameter("puddle", float(_palette["puddle"]))
		_asphalt.set_shader_parameter("night", float(_palette["night"]))
		_asphalt.set_shader_parameter("asphalt_a", _palette["asphalt_a"])
		_asphalt.set_shader_parameter("asphalt_b", _palette["asphalt_b"])
	if _rain != null:
		_rain.set_shader_parameter("density", rain_amount)
		_rain.set_shader_parameter("drop_color", _palette["rain_color"])
	if _vignette != null:
		_vignette.set_shader_parameter("strength", float(_palette["vignette"]))
		_vignette.set_shader_parameter("edge_color", _palette["vignette_color"])
	if _fog != null:
		var haze: Color = _palette["fog_color"]
		haze.a = fog_amount
		_fog.color = haze
	if _flash_rect != null:
		_flash_rect.color = Color(0.85, 0.88, 1.0, flash * 0.42)


func _canonical(raw: String) -> String:
	match raw:
		"wet_rain", "shuto_rain":
			return "rain"
		"fog_dawn", "dawn", "docklands_fog":
			return "fog"
		"sunset", "sunset_storm", "apex_storm":
			return "storm"
		"dry", "night", "haruna_dry_night":
			return "dry_night"
		_:
			return raw if _presets().has(raw) else "dry_night"


func _presets() -> Dictionary:
	return {
		"dry_night": {
			"ground": Color(0.05, 0.07, 0.05),
			"asphalt_a": Color(0.05, 0.05, 0.06),
			"asphalt_b": Color(0.13, 0.13, 0.14),
			"night": 0.62,
			"wet": 0.04,
			"puddle": 0.02,
			"rain": 0.0,
			"fog": 0.04,
			"lightning": false,
			"fog_color": Color(0.05, 0.06, 0.1, 0.0),
			"rain_color": Color(0.7, 0.78, 0.88, 0.0),
			"light_color": Color(1.0, 0.84, 0.55),
			"tree": Color(0.05, 0.12, 0.07),
			"rock": Color(0.22, 0.22, 0.24),
			"sign": Color(0.93, 0.74, 0.18),
			"rail": Color(0.55, 0.56, 0.6),
			"building": Color(0.04, 0.045, 0.07),
			"skyline": Color(0.03, 0.03, 0.06),
			"window": Color(1.0, 0.78, 0.42),
			"vignette": 0.46,
			"vignette_color": Color(0.01, 0.0, 0.03),
		},
		"rain": {
			"ground": Color(0.04, 0.06, 0.07),
			"asphalt_a": Color(0.04, 0.05, 0.06),
			"asphalt_b": Color(0.1, 0.12, 0.14),
			"night": 0.7,
			"wet": 0.92,
			"puddle": 0.78,
			"rain": 0.72,
			"fog": 0.12,
			"lightning": false,
			"fog_color": Color(0.05, 0.07, 0.09, 1.0),
			"rain_color": Color(0.68, 0.78, 0.86, 0.55),
			"light_color": Color(0.75, 0.88, 1.0),
			"tree": Color(0.04, 0.1, 0.08),
			"rock": Color(0.18, 0.2, 0.22),
			"sign": Color(0.95, 0.78, 0.2),
			"rail": Color(0.45, 0.5, 0.54),
			"building": Color(0.03, 0.05, 0.07),
			"skyline": Color(0.02, 0.04, 0.07),
			"window": Color(0.55, 0.82, 1.0),
			"vignette": 0.52,
			"vignette_color": Color(0.0, 0.02, 0.04),
		},
		"fog": {
			"ground": Color(0.16, 0.16, 0.14),
			"asphalt_a": Color(0.18, 0.18, 0.16),
			"asphalt_b": Color(0.28, 0.28, 0.26),
			"night": 0.18,
			"wet": 0.22,
			"puddle": 0.12,
			"rain": 0.04,
			"fog": 0.42,
			"lightning": false,
			"fog_color": Color(0.62, 0.6, 0.54, 1.0),
			"rain_color": Color(0.8, 0.8, 0.78, 0.25),
			"light_color": Color(1.0, 0.93, 0.75),
			"tree": Color(0.18, 0.22, 0.16),
			"rock": Color(0.4, 0.4, 0.38),
			"sign": Color(0.86, 0.7, 0.22),
			"rail": Color(0.7, 0.68, 0.62),
			"building": Color(0.22, 0.22, 0.2),
			"skyline": Color(0.28, 0.28, 0.26),
			"window": Color(0.95, 0.9, 0.7),
			"vignette": 0.28,
			"vignette_color": Color(0.2, 0.18, 0.14),
		},
		"storm": {
			"ground": Color(0.07, 0.04, 0.03),
			"asphalt_a": Color(0.06, 0.04, 0.04),
			"asphalt_b": Color(0.16, 0.09, 0.07),
			"night": 0.58,
			"wet": 1.0,
			"puddle": 0.88,
			"rain": 0.95,
			"fog": 0.2,
			"lightning": true,
			"fog_color": Color(0.22, 0.08, 0.05, 1.0),
			"rain_color": Color(0.78, 0.7, 0.62, 0.6),
			"light_color": Color(1.0, 0.62, 0.32),
			"tree": Color(0.08, 0.07, 0.04),
			"rock": Color(0.24, 0.16, 0.12),
			"sign": Color(0.95, 0.55, 0.16),
			"rail": Color(0.5, 0.36, 0.28),
			"building": Color(0.08, 0.04, 0.05),
			"skyline": Color(0.1, 0.04, 0.05),
			"window": Color(1.0, 0.55, 0.28),
			"vignette": 0.58,
			"vignette_color": Color(0.08, 0.02, 0.01),
		},
	}
