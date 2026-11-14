extends Node2D
## Bass Drift — wires road, car, camera, audio, UI.

@onready var road: Node2D = $RoadManager
@onready var car: Node2D = $Car
@onready var camera: Camera2D = $CameraJuice
@onready var ui: CanvasLayer = $UI
@onready var grid_bg: ColorRect = $ParallaxBG/NeonGrid
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var glitch_rect: ColorRect = $GlitchLayer/GlitchRect

var _grid_mat: ShaderMaterial
var _glitch_mat: ShaderMaterial
var _restarting: bool = false


func _ready() -> void:
	_setup_environment()
	_setup_shaders()
	car.set_road(road)
	camera.follow_target = car
	car.autopilot = true
	road.set_autopilot(true)

	ui.start_pressed.connect(_on_start)
	ui.restart_pressed.connect(_on_restart)
	car.crashed.connect(_on_car_crashed)
	car.perfect_drift.connect(_on_perfect)
	AudioBeatManager.bass_updated.connect(_on_bass)
	AudioBeatManager.drop_started.connect(_on_drop_started)
	AudioBeatManager.drop_ended.connect(_on_drop_ended)

	# Menu autopilot loop
	AudioBeatManager.set_bpm(GameState.get_bpm())
	AudioBeatManager.start()
	car.reset_car(Vector2(360, 1000))
	if road.center_points.size() > 0:
		car.reset_car(road.center_points[0] + Vector2(0, -40))


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.08)
	env.glow_enabled = true
	env.glow_intensity = 1.4
	env.glow_strength = 1.1
	env.glow_bloom = 0.55
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.7
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	world_env.environment = env


func _setup_shaders() -> void:
	if grid_bg:
		_grid_mat = ShaderMaterial.new()
		_grid_mat.shader = load("res://shaders/neon_grid.gdshader")
		grid_bg.material = _grid_mat
		grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if glitch_rect:
		_glitch_mat = ShaderMaterial.new()
		_glitch_mat.shader = load("res://shaders/drop_glitch.gdshader")
		_glitch_mat.set_shader_parameter("intensity", 0.0)
		glitch_rect.material = _glitch_mat
		glitch_rect.visible = false
		glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_start() -> void:
	AudioBeatManager.set_bpm(GameState.get_bpm())
	_soft_restart(true)
	ui.show_hud()
	GameState.reset_run()
	car.autopilot = false
	road.set_autopilot(false)


func _on_restart() -> void:
	_soft_restart(true)
	ui.show_hud()
	GameState.reset_run()
	car.autopilot = false
	road.set_autopilot(false)


func _soft_restart(play_audio: bool) -> void:
	## Fast restart without full scene reload (~0.1s).
	if _restarting:
		return
	_restarting = true
	Engine.time_scale = 1.0
	road.reset_road()
	var spawn := Vector2(360, 1000)
	if road.center_points.size() > 0:
		spawn = road.center_points[0] + Vector2(0, -40)
	car.reset_car(spawn)
	camera.global_position = spawn
	if play_audio:
		AudioBeatManager.restart()
	_on_drop_ended()
	_restarting = false


func _on_car_crashed() -> void:
	pass  # GameState / UI handle after slow-mo


func _on_perfect() -> void:
	pass


func _on_bass(energy: float) -> void:
	if _grid_mat:
		_grid_mat.set_shader_parameter("bass_energy", energy)
		_grid_mat.set_shader_parameter("scroll_y", AudioBeatManager.song_position * 2.5)


func _on_drop_started() -> void:
	if glitch_rect and _glitch_mat:
		glitch_rect.visible = true
		_glitch_mat.set_shader_parameter("intensity", 0.55)


func _on_drop_ended() -> void:
	if glitch_rect and _glitch_mat:
		_glitch_mat.set_shader_parameter("intensity", 0.0)
		glitch_rect.visible = false


func _process(_delta: float) -> void:
	if road and camera:
		road.maintain_chunks(camera.global_position.y)
	# Soft glitch pulse on bass during drops
	if glitch_rect and glitch_rect.visible and _glitch_mat:
		var i := 0.35 + AudioBeatManager.bass_energy * 0.5
		_glitch_mat.set_shader_parameter("intensity", i)
