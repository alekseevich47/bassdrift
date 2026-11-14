extends Control

## Four chapters, four levels each. A chapter opens when its first level's
## star gate is met. Each level still respects its own unlock_stars.

signal closed
signal race_requested(level_id: String)


func _ready() -> void:
	UiPalette.paint_header(%BackButton, %Title, %Wallet)
	%Title.text = "LEVELS"
	%BackButton.pressed.connect(func() -> void: closed.emit())
	UiPalette.prepare_scroll(%Scroll)
	SaveManager.campaign_changed.connect(_refresh)
	SaveManager.currency_changed.connect(_on_currency)
	_refresh()


func _exit_tree() -> void:
	if not is_instance_valid(SaveManager):
		return
	if SaveManager.campaign_changed.is_connected(_refresh):
		SaveManager.campaign_changed.disconnect(_refresh)
	if SaveManager.currency_changed.is_connected(_on_currency):
		SaveManager.currency_changed.disconnect(_on_currency)


func _on_currency(_cr: int) -> void:
	_sync_wallet()


func _refresh() -> void:
	_sync_wallet()
	for child in %Body.get_children():
		%Body.remove_child(child)
		child.free()
	var chapters: Array = GameData.chapter_ids()
	if chapters.is_empty():
		%Body.add_child(_note("No chapters in the catalog yet."))
		return
	var cap := GameData.level_ids().size() * GameData.STAR_CAP
	var total := SaveManager.get_total_stars()
	var summary := _note("%d / %d stars on the mountain." % [total, cap])
	UiPalette.style_label(summary, UiPalette.AMBER, 16, HORIZONTAL_ALIGNMENT_LEFT)
	%Body.add_child(summary)
	for chapter_id in chapters:
		%Body.add_child(_chapter_block(str(chapter_id)))
	var footer := _note("Stars open the next gate." if total < cap else "Every gate is open.")
	%Body.add_child(footer)


func _chapter_block(chapter_id: String) -> Control:
	var chapter := GameData.get_chapter(chapter_id)
	var level_ids: Array = GameData.chapter_level_ids(chapter_id)
	var unlocked := false
	var gate := 0
	if not level_ids.is_empty():
		var first := GameData.get_level(str(level_ids[0]))
		gate = int(first.get("unlock_stars", 0))
		unlocked = SaveManager.is_level_unlocked(str(level_ids[0]))
	var earned := 0
	for level_id in level_ids:
		earned += SaveManager.get_level_stars(str(level_id))
	var palette: Dictionary = chapter.get("palette", {})
	var neon := Color(str(palette.get("neon", "#ff2d8a")))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_meta("chapter_id", chapter_id)
	panel.set_meta("unlocked", unlocked)
	UiPalette.style_panel(panel, neon if unlocked else UiPalette.LOCK)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "%s   %s" % [str(chapter.get("name", chapter_id)).to_upper(), str(chapter.get("subtitle", ""))]
	UiPalette.style_label(title, UiPalette.INK if unlocked else UiPalette.LOCK, 20)
	box.add_child(title)
	var weather := str(chapter.get("weather", "")).replace("_", " ")
	var meta := Label.new()
	meta.text = "%d–%d BPM  ·  %s  ·  %d/%d" % [
		int(chapter.get("bpm_min", 0)),
		int(chapter.get("bpm_max", 0)),
		weather,
		earned,
		level_ids.size() * GameData.STAR_CAP,
	]
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(meta, UiPalette.CYAN if unlocked else UiPalette.MUTED, 14)
	box.add_child(meta)
	if not unlocked:
		var lock := Label.new()
		lock.text = "LOCKED  ·  need %d stars  ·  you have %d" % [gate, SaveManager.get_total_stars()]
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiPalette.style_label(lock, UiPalette.AMBER, 14)
		box.add_child(lock)
	if level_ids.is_empty():
		box.add_child(_note("No levels in this chapter."))
		return panel
	for level_id in level_ids:
		box.add_child(_level_button(str(level_id), unlocked))
	return panel


func _level_button(level_id: String, chapter_open: bool) -> Button:
	var level := GameData.get_level(level_id)
	var open := chapter_open and SaveManager.is_level_unlocked(level_id)
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 76)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.set_meta("level_id", level_id)
	button.set_meta("unlocked", open)
	var best := SaveManager.get_level_best_score(level_id)
	var best_text := "NO TIME" if best <= 0 else "BEST %s" % UiPalette.grouped_int(best)
	var second := "%d BPM  ·  %s" % [int(level.get("bpm", 0)), best_text]
	if not open:
		second = "LOCKED  ·  %d STARS" % int(level.get("unlock_stars", 0))
	button.text = "%s   %s\n%s" % [
		UiPalette.stars(SaveManager.get_level_stars(level_id)),
		str(level.get("name", level_id)),
		second,
	]
	button.disabled = not open
	UiPalette.style_button(button, UiPalette.BG, UiPalette.CYAN if open else UiPalette.LOCK, 16)
	if open:
		button.pressed.connect(_emit_race.bind(level_id))
	return button


func _emit_race(level_id: String) -> void:
	race_requested.emit(level_id)


func _sync_wallet() -> void:
	%Wallet.text = "%d★  %s" % [SaveManager.get_total_stars(), UiPalette.money(SaveManager.get_cr())]


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(label, UiPalette.MUTED, 15)
	return label
