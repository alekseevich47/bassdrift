extends Control

## Pilot level, rank ladder, and the four perk trees.
## The level cap is GameData.MAX_PILOT_LEVEL. Skill points come from level-ups.

signal closed

var _perk_buttons: Dictionary = {}
var _perk_headings: Dictionary = {}
var _perk_details: Dictionary = {}


func _ready() -> void:
	UiPalette.paint_header(%BackButton, %Title, %Wallet)
	%Title.text = "PILOT"
	%BackButton.pressed.connect(func() -> void: closed.emit())
	UiPalette.prepare_scroll(%Scroll)
	UiPalette.style_label(%LevelLabel, UiPalette.INK, 36, HORIZONTAL_ALIGNMENT_LEFT)
	UiPalette.style_label(%RankLabel, UiPalette.CYAN, 18)
	UiPalette.style_label(%NextRank, UiPalette.MUTED, 14)
	UiPalette.style_label(%XpLabel, UiPalette.AMBER, 14)
	UiPalette.style_label(%Points, UiPalette.INK, 20)
	UiPalette.style_label(%Hint, UiPalette.MUTED, 14)
	%Hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_bar(%XpBar, UiPalette.MAGENTA)
	%XpBar.min_value = 0
	%XpBar.max_value = 100
	UiPalette.style_label(%RankHeading, UiPalette.MAGENTA, 14)
	UiPalette.style_label(%PerkHeading, UiPalette.MAGENTA, 14)
	_build_perks()
	SaveManager.pilot_changed.connect(_on_pilot)
	SaveManager.currency_changed.connect(_on_currency)
	_refresh()


func _exit_tree() -> void:
	if not is_instance_valid(SaveManager):
		return
	if SaveManager.pilot_changed.is_connected(_on_pilot):
		SaveManager.pilot_changed.disconnect(_on_pilot)
	if SaveManager.currency_changed.is_connected(_on_currency):
		SaveManager.currency_changed.disconnect(_on_currency)


func _on_pilot(_level: int, _xp: int, _points: int) -> void:
	_refresh()


func _on_currency(_cr: int) -> void:
	%Wallet.text = UiPalette.money(SaveManager.get_cr())


func _build_perks() -> void:
	for child in %RankList.get_children():
		child.queue_free()
	for perk_id in GameData.perk_ids():
		var id := str(perk_id)
		var spec := GameData.get_perk(id)
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 4)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var heading := Label.new()
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiPalette.style_label(heading, UiPalette.INK, 16)
		var blurb := Label.new()
		blurb.text = str(spec.get("blurb", ""))
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiPalette.style_label(blurb, UiPalette.MUTED, 13)
		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiPalette.style_label(detail, UiPalette.CYAN, 13)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 52)
		button.set_meta("perk_id", id)
		button.pressed.connect(_on_perk.bind(id))
		block.add_child(heading)
		block.add_child(blurb)
		block.add_child(detail)
		block.add_child(button)
		%PerkList.add_child(block)
		_perk_headings[id] = heading
		_perk_details[id] = detail
		_perk_buttons[id] = button
	if _perk_buttons.is_empty():
		var empty := Label.new()
		empty.text = "No perks in the catalog."
		UiPalette.style_label(empty, UiPalette.MUTED, 15)
		%PerkList.add_child(empty)


func _refresh() -> void:
	%Wallet.text = UiPalette.money(SaveManager.get_cr())
	var level := SaveManager.get_pilot_level()
	var xp := SaveManager.get_pilot_xp()
	var points := SaveManager.get_skill_points()
	var cap := GameData.MAX_PILOT_LEVEL
	var rank := GameData.get_rank_for_level(level)
	%LevelLabel.text = "LV %d" % level
	%RankLabel.text = str(rank.get("name", "Novice"))
	%NextRank.text = _next_rank_text(level)
	if level >= cap:
		%XpBar.value = 100
		%XpLabel.text = "Level %d / %d  ·  MAX" % [level, cap]
	else:
		var need := GameData.xp_to_next(level)
		%XpBar.value = 0.0 if need <= 0 else float(xp) / float(need) * 100.0
		%XpLabel.text = "Level %d / %d  ·  %d / %d XP" % [level, cap, xp, need]
	%Points.text = "%d SKILL %s" % [points, "POINT" if points == 1 else "POINTS"]
	var any_perk := false
	var all_maxed := not _perk_buttons.is_empty()
	for perk_id in _perk_buttons.keys():
		var spec := GameData.get_perk(str(perk_id))
		var info := SaveManager.preview_perk(str(perk_id))
		var perk_level := int(info.get("level", SaveManager.get_perk_level(str(perk_id))))
		if perk_level > 0:
			any_perk = true
		var maxed := bool(info.get("maxed", perk_level >= GameData.MAX_PERK_LEVEL))
		if not maxed:
			all_maxed = false
		var heading: Label = _perk_headings[perk_id]
		heading.text = "%s   %d/%d" % [str(spec.get("name", perk_id)), perk_level, GameData.MAX_PERK_LEVEL]
		var detail: Label = _perk_details[perk_id]
		if maxed:
			detail.text = UiPalette.format_effect(info.get("effect", {}))
		else:
			detail.text = "Now: %s\nNext: %s" % [
				UiPalette.format_effect(info.get("effect", {})),
				UiPalette.format_effect(info.get("next_effect", {})),
			]
		var button: Button = _perk_buttons[perk_id]
		if maxed:
			button.text = "MAX"
			button.disabled = true
		elif not bool(info.get("can_afford", false)):
			button.text = "NEED 1 SP"
			button.disabled = true
		else:
			button.text = "SPEND 1"
			button.disabled = false
		UiPalette.style_button(button, UiPalette.PIT, UiPalette.CYAN, 16)
	_rebuild_ranks(str(rank.get("id", "")))
	if points == 0 and not any_perk:
		%Hint.text = "Finish races to earn XP. Each level grants a skill point."
	elif all_maxed:
		%Hint.text = "Every perk is maxed."
	elif points == 0:
		%Hint.text = "No skill points left. Race to level up."
	else:
		%Hint.text = "Spend a point to push a perk. Rank thresholds grant an extra point."


func _rebuild_ranks(current_id: String) -> void:
	for child in %RankList.get_children():
		%RankList.remove_child(child)
		child.free()
	var level := SaveManager.get_pilot_level()
	for rank in GameData.ranks():
		var row := Label.new()
		var min_level := int(rank.get("min_level", 1))
		var marker := "▸ " if str(rank.get("id", "")) == current_id else "  "
		row.text = "%sLv %d   %s" % [marker, min_level, str(rank.get("name", ""))]
		var color := UiPalette.MUTED
		if str(rank.get("id", "")) == current_id:
			color = UiPalette.CYAN
		elif level >= min_level:
			color = UiPalette.INK
		UiPalette.style_label(row, color, 16)
		%RankList.add_child(row)


func _next_rank_text(level: int) -> String:
	for rank in GameData.ranks():
		if int(rank.get("min_level", 1)) > level:
			return "Next rank %s at level %d." % [str(rank.get("name", "")), int(rank["min_level"])]
	return "Top rank. The cap is level %d." % GameData.MAX_PILOT_LEVEL


func _on_perk(perk_id: String) -> void:
	var result := SaveManager.try_upgrade_perk(perk_id)
	if not bool(result.get("ok", false)):
		%Hint.text = UiPalette.reason_text(result)
		%Hint.add_theme_color_override("font_color", UiPalette.DANGER)
		return
	%Hint.add_theme_color_override("font_color", UiPalette.MUTED)
	_refresh()
