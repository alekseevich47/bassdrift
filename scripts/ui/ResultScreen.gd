extends CanvasLayer

## Animated finish card.
## present(result) reads score, stars, best_score, best_stars, star_delta,
## cr_gain, xp_gain, xp_result, level_id, display_name, crashed/failed.
## Revive uses AdMonetizationStub.show_revive_ad.
## Double reward uses show_double_reward_ad, which calls show_rewarded_ad
## and grants the bonus CR itself.

signal restart_requested
signal garage_requested
signal revive_accepted

var _result: Dictionary = {}
var _tween: Tween
var _ad_lock := false
var _revive_used := false
var _doubled := false
var _shown_score := 0


func _ready() -> void:
	add_to_group("apex_result_screen")
	process_mode = Node.PROCESS_MODE_ALWAYS
	%Dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	UiPalette.style_panel(%Panel, UiPalette.MAGENTA)
	UiPalette.style_label(%Kicker, UiPalette.MAGENTA, 16, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.style_label(%Heading, UiPalette.INK, 32, HORIZONTAL_ALIGNMENT_CENTER)
	%Heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(%Score, UiPalette.INK, 64, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.style_label(%Rewards, UiPalette.AMBER, 18, HORIZONTAL_ALIGNMENT_CENTER)
	%Rewards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(%LevelUp, UiPalette.CYAN, 18, HORIZONTAL_ALIGNMENT_CENTER)
	UiPalette.style_label(%Status, UiPalette.MUTED, 15, HORIZONTAL_ALIGNMENT_CENTER)
	%Status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for star in [%Star1, %Star2, %Star3]:
		UiPalette.style_label(star, UiPalette.AMBER, 40, HORIZONTAL_ALIGNMENT_CENTER)
		star.custom_minimum_size = Vector2(48, 48)
		star.pivot_offset = Vector2(24, 24)
	for button in [%ReviveButton, %DoubleButton, %RestartButton, %GarageButton]:
		button.custom_minimum_size = Vector2(0, 60)
	UiPalette.style_button(%ReviveButton, UiPalette.PIT, UiPalette.MAGENTA, 18)
	UiPalette.style_button(%DoubleButton, UiPalette.PIT, UiPalette.AMBER, 18)
	UiPalette.style_button(%RestartButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%GarageButton, UiPalette.PIT, UiPalette.CYAN, 18)
	%ReviveButton.pressed.connect(_on_revive_pressed)
	%DoubleButton.pressed.connect(_on_double_pressed)
	%RestartButton.pressed.connect(func() -> void: restart_requested.emit())
	%GarageButton.pressed.connect(func() -> void: garage_requested.emit())
	if not AdMonetizationStub.ad_completed.is_connected(_on_ad_completed):
		AdMonetizationStub.ad_completed.connect(_on_ad_completed)


func _exit_tree() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if is_instance_valid(AdMonetizationStub) and AdMonetizationStub.ad_completed.is_connected(_on_ad_completed):
		AdMonetizationStub.ad_completed.disconnect(_on_ad_completed)


func present(result: Dictionary) -> void:
	if not is_node_ready():
		call_deferred("present", result)
		return
	_result = result.duplicate(true)
	_revive_used = false
	_doubled = false
	_ad_lock = false
	var crashed := _is_crashed(result)
	%Kicker.text = "WRECKED" if crashed else "FINISH"
	%Heading.text = _level_name(result)
	%Score.text = "0"
	_shown_score = 0
	_lay_stars(0)
	%Rewards.modulate = Color(1, 1, 1, 0)
	%Rewards.text = _reward_text(result)
	var xp_result: Dictionary = result.get("xp_result", {}) if typeof(result.get("xp_result")) == TYPE_DICTIONARY else {}
	var levels_gained := int(xp_result.get("levels_gained", 0))
	if levels_gained > 0:
		%LevelUp.visible = true
		%LevelUp.text = "LEVEL UP  %d" % int(xp_result.get("level", 0))
		var points := int(xp_result.get("skill_points_gained", 0))
		if points > 0:
			%LevelUp.text += "  ·  +%d SP" % points
		%LevelUp.modulate = Color(1, 1, 1, 0)
	else:
		%LevelUp.visible = false
	if crashed and bool(result.get("can_revive", true)):
		%Status.text = "Watch a short ad to get back on the line."
	elif crashed:
		%Status.text = str(result.get("status", "The run ended in the wall."))
	else:
		%Status.text = "The line holds."
	_refresh_buttons()
	_play(int(result.get("score", 0)), _star_count(result))


func _play(score: int, stars: int) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	for star in [%Star1, %Star2, %Star3]:
		star.scale = Vector2(0.2, 0.2)
		star.modulate = Color(1, 1, 1, 0)
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_shown_score, 0.0, float(maxi(score, 0)), 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for index in 3:
		var star: Label = [%Star1, %Star2, %Star3][index]
		_tween.tween_interval(0.05)
		_tween.tween_callback(_reveal_star.bind(star, index < stars))
		_tween.tween_property(star, "scale", Vector2.ONE, 0.16)
		_tween.parallel().tween_property(star, "modulate:a", 1.0, 0.16)
	_tween.tween_property(%Rewards, "modulate:a", 1.0, 0.2)
	if %LevelUp.visible:
		_tween.parallel().tween_property(%LevelUp, "modulate:a", 1.0, 0.2)


func _set_shown_score(value: float) -> void:
	_shown_score = int(round(value))
	if is_node_ready():
		%Score.text = UiPalette.grouped_int(_shown_score)


func _reveal_star(star: Label, filled: bool) -> void:
	star.text = "★" if filled else "☆"
	star.add_theme_color_override("font_color", UiPalette.AMBER if filled else UiPalette.LOCK)


func _lay_stars(count: int) -> void:
	var stars: Array = [%Star1, %Star2, %Star3]
	for index in stars.size():
		var star: Label = stars[index]
		var filled := index < count
		star.text = "★" if filled else "☆"
		star.add_theme_color_override("font_color", UiPalette.AMBER if filled else UiPalette.LOCK)


func _refresh_buttons() -> void:
	var crashed := _is_crashed(_result)
	var explicit = _result.get("can_revive", null)
	var show_revive := crashed
	if explicit != null:
		show_revive = bool(explicit)
	%ReviveButton.visible = show_revive
	%ReviveButton.disabled = _ad_lock or _revive_used or not show_revive
	%ReviveButton.text = "REVIVE"
	var payout := int(_result.get("cr_gain", 0))
	%DoubleButton.disabled = _ad_lock or _doubled or payout <= 0
	if _doubled:
		%DoubleButton.text = "DOUBLED"
	elif payout <= 0:
		%DoubleButton.text = "NO CR TO DOUBLE"
	else:
		%DoubleButton.text = "DOUBLE REWARD"
	%RestartButton.disabled = _ad_lock
	%GarageButton.disabled = _ad_lock
	UiPalette.style_button(%ReviveButton, UiPalette.PIT, UiPalette.MAGENTA, 18)
	UiPalette.style_button(%DoubleButton, UiPalette.PIT, UiPalette.AMBER, 18)
	UiPalette.style_button(%RestartButton, UiPalette.PIT, UiPalette.CYAN, 18)
	UiPalette.style_button(%GarageButton, UiPalette.PIT, UiPalette.CYAN, 18)


func _on_revive_pressed() -> void:
	if _ad_lock or _revive_used:
		return
	_ad_lock = true
	_refresh_buttons()
	%Status.text = "Ad playing..."
	AdMonetizationStub.show_revive_ad(_on_revive_finished)


func _on_revive_finished(success: bool) -> void:
	_ad_lock = false
	if not is_inside_tree():
		return
	if success:
		_revive_used = true
		revive_accepted.emit()
		return
	_refresh_buttons()
	%Status.text = "Ad didn't finish. You can try again."


func _on_double_pressed() -> void:
	if _ad_lock or _doubled:
		return
	var payout := int(_result.get("cr_gain", 0))
	if payout <= 0:
		return
	_ad_lock = true
	_refresh_buttons()
	%Status.text = "Ad playing..."
	AdMonetizationStub.show_double_reward_ad(payout, _on_double_finished)


func _on_double_finished(success: bool, granted: int) -> void:
	_ad_lock = false
	if not is_inside_tree():
		return
	if not success:
		_refresh_buttons()
		%Status.text = "Ad didn't finish. CR stays as it is."
		return
	_doubled = true
	_refresh_buttons()
	%DoubleButton.text = "DOUBLED  +%s" % UiPalette.money(granted)
	%Status.text = "Extra %s is in the wallet." % UiPalette.money(granted)


func _on_ad_completed(_placement: String, _rewarded: bool) -> void:
	if not is_inside_tree():
		return
	_ad_lock = false
	if not _revive_used:
		_refresh_buttons()


func _reward_text(result: Dictionary) -> String:
	var lines: PackedStringArray = []
	var best := int(result.get("best_score", result.get("score", 0)))
	lines.append("BEST  %s" % UiPalette.grouped_int(best))
	var star_delta := int(result.get("star_delta", 0))
	if star_delta > 0:
		lines.append("NEW STAR")
	var cr_gain := int(result.get("cr_gain", 0))
	if cr_gain > 0:
		lines.append("+%s" % UiPalette.money(cr_gain))
	var xp_gain := int(result.get("xp_gain", 0))
	if xp_gain > 0:
		lines.append("+%d XP" % xp_gain)
	var coin_cr := int(result.get("coin_cr", 0))
	if coin_cr > 0:
		lines.append("COINS +%s" % UiPalette.money(coin_cr))
	if result.has("perfects") or result.has("misses"):
		lines.append("Perfect %d  ·  Miss %d" % [int(result.get("perfects", 0)), int(result.get("misses", 0))])
	if lines.size() == 1 and int(result.get("score", 0)) <= 0:
		lines.append("No payout on an empty run.")
	return "\n".join(lines)


func _star_count(result: Dictionary) -> int:
	if result.has("stars"):
		return clampi(int(result["stars"]), 0, GameData.STAR_CAP)
	if result.has("best_stars") and not result.has("score"):
		return clampi(int(result["best_stars"]), 0, GameData.STAR_CAP)
	var level_id := str(result.get("level_id", ""))
	if GameData.has_level(level_id) and result.has("score"):
		return GameData.stars_for_score(level_id, int(result["score"]))
	return 0


func _level_name(result: Dictionary) -> String:
	if str(result.get("level_name", "")) != "":
		return str(result["level_name"])
	var level_id := str(result.get("level_id", ""))
	if GameData.has_level(level_id):
		return str(GameData.get_level(level_id).get("name", level_id))
	if str(result.get("display_name", "")) != "":
		return str(result["display_name"])
	if str(result.get("mode", "")) == "custom":
		return "CUSTOM LINE"
	return "OPEN ROAD"


func _is_crashed(result: Dictionary) -> bool:
	if bool(result.get("crashed", false)) or bool(result.get("failed", false)) or bool(result.get("wrecked", false)):
		return true
	return str(result.get("reason", "")) == "wrecked"
