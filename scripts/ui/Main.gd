extends Control

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const RACE_SCENE := "res://scenes/RaceWorld.tscn"

signal scene_changed(scene_name: String)

var _active := ""


func _ready() -> void:
	show_menu()
	if OS.get_cmdline_user_args().has("--smoke"):
		var runner: Node = load("res://tools/smoke_check.gd").new()
		add_child(runner)


func show_menu() -> void:
	var node := _swap(MENU_SCENE)
	if node == null:
		return
	if node.has_signal("play_requested"):
		node.play_requested.connect(show_race)
	_active = "menu"
	scene_changed.emit("menu")


func show_race(level_id: String = "") -> void:
	var node := _swap(RACE_SCENE)
	if node == null:
		return
	if node.has_method("configure"):
		node.configure(level_id)
	if node.has_signal("exit_requested"):
		node.exit_requested.connect(show_menu)
	_active = "race"
	scene_changed.emit("race")


func current_scene_name() -> String:
	return _active


func _swap(scene_path: String) -> Node:
	var host := $Host
	for child in host.get_children():
		host.remove_child(child)
		child.free()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Missing scene: %s" % scene_path)
		return null
	var node := packed.instantiate()
	host.add_child(node)
	return node
