extends Control

## Buy cars, paint them, and spend CR on the four upgrade trees.

signal closed

var _viewed := ""
var _style := ""
var _colors := {
	"primary": Color("#e6e6ea"),
	"secondary": Color("#16161c"),
	"accent": Color("#ff2d8a"),
}
var _syncing := false
var _time := 0.0
var _car_buttons: Dictionary = {}
var _style_buttons: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _upgrade_level: Dictionary = {}
var _upgrade_detail: Dictionary = {}
var _stat_bars: Dictionary = {}
var _pickers: Dictionary = {}


func _ready() -> void:
	UiPalette.paint_header(%BackButton, %Title, %Wallet)
	%Title.text = "GARAGE"
	%BackButton.pressed.connect(func() -> void: closed.emit())
	UiPalette.prepare_scroll(%Scroll)
	UiPalette.style_label(%CarName, UiPalette.INK, 28)
	UiPalette.style_label(%CarMeta, UiPalette.CYAN, 15)
	UiPalette.style_label(%Notice, UiPalette.MUTED, 15)
	%Notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_label(%PaintLabel, UiPalette.MAGENTA, 14)
	UiPalette.style_label(%UpgradeLabel, UiPalette.MAGENTA, 14)
	UiPalette.style_button(%ActionButton, UiPalette.PIT, UiPalette.MAGENTA, 18)
	%ActionButton.custom_minimum_size = Vector2(0, 60)
	%ActionButton.pressed.connect(_on_action)
	_build_rows()
	_show_car(SaveManager.get_selected_car())
	SaveManager.garage_changed.connect(_on_garage_changed)
	SaveManager.currency_changed.connect(_on_currency)
	SaveManager.campaign_changed.connect(_on_garage_changed)


func _exit_tree() -> void:
	if not is_instance_valid(SaveManager):
		return
	if SaveManager.garage_changed.is_connected(_on_garage_changed):
		SaveManager.garage_changed.disconnect(_on_garage_changed)
	if SaveManager.currency_changed.is_connected(_on_currency):
		SaveManager.currency_changed.disconnect(_on_currency)
	if SaveManager.campaign_changed.is_connected(_on_garage_changed):
		SaveManager.campaign_changed.disconnect(_on_garage_changed)


func _process(delta: float) -> void:
	_time += delta
	if %Swatch == null:
		return
	%Swatch.color = UiPalette.paint_tint({
		"style": _style,
		"primary": "#" + _colors["primary"].to_html(false),
		"accent": "#" + _colors["accent"].to_html(false),
	}, _time)


func _on_currency(_cr: int) -> void:
	_sync_wallet()
	_refresh_buttons()


func _on_garage_changed() -> void:
	_sync_wallet()
	_refresh_buttons()


func _build_rows() -> void:
	var cars: Array = GameData.car_ids()
	if cars.is_empty():
		%Notice.text = "No cars in the catalog."
		return
	for car_id in cars:
		var id := str(car_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 58)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.set_meta("car_id", id)
		button.pressed.connect(_show_car.bind(id))
		%CarRow.add_child(button)
		_car_buttons[id] = button
	for stat_name in ["speed", "accel", "drift", "grip"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var caption := Label.new()
		caption.custom_minimum_size = Vector2(64, 0)
		caption.text = stat_name.to_upper()
		UiPalette.style_label(caption, UiPalette.MUTED, 13)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiPalette.style_bar(bar, UiPalette.CYAN if stat_name != "drift" else UiPalette.MAGENTA)
		var value := Label.new()
		value.custom_minimum_size = Vector2(36, 0)
		UiPalette.style_label(value, UiPalette.INK, 14, HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(caption)
		row.add_child(bar)
		row.add_child(value)
		%Stats.add_child(row)
		_stat_bars[stat_name] = {"bar": bar, "value": value}
	for style_id in GameData.paint_ids():
		var id := str(style_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("paint_id", id)
		button.pressed.connect(_on_style.bind(id))
		%PaintRow.add_child(button)
		_style_buttons[id] = button
	for slot in ["primary", "secondary", "accent"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		var caption := Label.new()
		caption.text = slot.to_upper()
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiPalette.style_label(caption, UiPalette.MUTED, 12, HORIZONTAL_ALIGNMENT_CENTER)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(0, 48)
		picker.edit_alpha = false
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.color_changed.connect(_on_color.bind(slot))
		column.add_child(caption)
		column.add_child(picker)
		%ColorRow.add_child(column)
		_pickers[slot] = picker
	for upgrade_id in GameData.upgrade_ids():
		var id := str(upgrade_id)
		var spec := GameData.get_upgrade(id)
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
		button.set_meta("upgrade_id", id)
		button.pressed.connect(_on_upgrade.bind(id))
		UiPalette.style_button(button, UiPalette.PIT, UiPalette.AMBER, 16)
		block.add_child(heading)
		block.add_child(blurb)
		block.add_child(detail)
		block.add_child(button)
		%Upgrades.add_child(block)
		_upgrade_level[id] = heading
		_upgrade_detail[id] = detail
		_upgrade_buttons[id] = button


func _show_car(car_id: String) -> void:
	if car_id.is_empty() or not GameData.has_car(car_id):
		car_id = SaveManager.get_selected_car()
	_viewed = car_id
	var paint := SaveManager.get_paint(car_id)
	_style = str(paint.get("style", GameData.PAINT_GLOSS))
	_syncing = true
	for slot in _colors.keys():
		_colors[slot] = Color(str(paint.get(slot, "#ffffff")))
		if _pickers.has(slot):
			(_pickers[slot] as ColorPickerButton).color = _colors[slot]
	_syncing = false
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _viewed.is_empty() or not GameData.has_car(_viewed):
		return
	_sync_wallet()
	var car := GameData.get_car(_viewed)
	var owned := SaveManager.owns_car(_viewed)
	var preview := SaveManager.preview_car(_viewed)
	%CarName.text = str(car.get("name", _viewed))
	%CarMeta.text = "%s  ·  gate %d★" % [
		UiPalette.money(int(car.get("price_cr", 0))) if int(car.get("price_cr", 0)) > 0 else "STARTER",
		int(car.get("unlock_stars", 0)),
	]
	var stats: Dictionary = car.get("stats", {})
	for stat_name in _stat_bars.keys():
		var pack: Dictionary = _stat_bars[stat_name]
		var amount := int(stats.get(stat_name, 0))
		(pack["bar"] as ProgressBar).value = amount
		(pack["value"] as Label).text = str(amount)
	for car_id in _car_buttons.keys():
		var button: Button = _car_buttons[car_id]
		var tag := ""
		if SaveManager.get_selected_car() == str(car_id):
			tag = " · ON"
		button.text = "%s%s" % [_short_car(str(car_id)), tag]
		UiPalette.style_choice(button, str(car_id) == _viewed, 13)
	if owned and SaveManager.get_selected_car() == _viewed:
		%ActionButton.text = "SELECTED"
		%ActionButton.disabled = true
		_notice("This is the car on the line.")
	elif owned:
		%ActionButton.text = "SELECT"
		%ActionButton.disabled = false
		_notice("In the garage. Select it to race.")
	elif not bool(preview.get("stars_met", false)):
		%ActionButton.text = "NEED %d STARS" % int(preview.get("unlock_stars", 0))
		%ActionButton.disabled = true
		_notice("Needs %d stars. You have %d." % [int(preview.get("unlock_stars", 0)), int(preview.get("stars", 0))])
	elif not bool(preview.get("can_buy", false)):
		%ActionButton.text = "NEED %s" % UiPalette.money(int(preview.get("price_cr", 0)))
		%ActionButton.disabled = true
		_notice("Costs %s." % UiPalette.money(int(preview.get("price_cr", 0))))
	else:
		%ActionButton.text = "BUY  %s" % UiPalette.money(int(preview.get("price_cr", 0)))
		%ActionButton.disabled = false
		_notice("Ready to buy.")
	UiPalette.style_button(%ActionButton, UiPalette.PIT, UiPalette.MAGENTA, 18)
	for style_id in _style_buttons.keys():
		var button: Button = _style_buttons[style_id]
		var style := GameData.get_paint_style(str(style_id))
		var paint_preview := SaveManager.preview_paint(str(style_id))
		var paint_owned := bool(paint_preview.get("owned", false))
		var price := int(style.get("price_cr", 0))
		var equipped := paint_owned and _style == str(style_id)
		var label := str(style.get("name", style_id)).to_upper()
		if equipped:
			button.text = "%s\nON" % label
		elif paint_owned:
			button.text = "%s\nUSE" % label
		else:
			button.text = "%s\n%s" % [label, UiPalette.money(price)]
		button.disabled = (not owned) or ((not paint_owned) and not bool(paint_preview.get("can_buy", false)))
		UiPalette.style_choice(button, equipped, 13)
	for slot in _pickers.keys():
		(_pickers[slot] as ColorPickerButton).disabled = not owned
	for upgrade_id in _upgrade_buttons.keys():
		var spec := GameData.get_upgrade(str(upgrade_id))
		var info := SaveManager.preview_upgrade(_viewed, str(upgrade_id))
		var level := int(info.get("level", 0)) if bool(info.get("ok", false)) else SaveManager.get_upgrade_level(_viewed, str(upgrade_id))
		var maxed := bool(info.get("maxed", level >= GameData.MAX_UPGRADE_LEVEL))
		var heading: Label = _upgrade_level[upgrade_id]
		heading.text = "%s   %d/%d" % [str(spec.get("name", upgrade_id)), level, GameData.MAX_UPGRADE_LEVEL]
		var now_effect: Dictionary = info.get("effect", {})
		var next_effect: Dictionary = info.get("next_effect", {})
		var detail: Label = _upgrade_detail[upgrade_id]
		if maxed:
			detail.text = "Now: %s" % UiPalette.format_effect(now_effect)
		else:
			detail.text = "Now: %s\nNext: %s" % [UiPalette.format_effect(now_effect), UiPalette.format_effect(next_effect)]
		var button: Button = _upgrade_buttons[upgrade_id]
		if not owned:
			button.text = "BUY THE CAR"
			button.disabled = true
		elif maxed:
			button.text = "MAX"
			button.disabled = true
		elif not bool(info.get("can_afford", false)):
			button.text = "NEED %s" % UiPalette.money(int(info.get("cost", 0)))
			button.disabled = true
		else:
			button.text = "UPGRADE  %s" % UiPalette.money(int(info.get("cost", 0)))
			button.disabled = false
		UiPalette.style_button(button, UiPalette.PIT, UiPalette.AMBER, 16)


func _on_action() -> void:
	if _viewed.is_empty():
		return
	if SaveManager.owns_car(_viewed):
		if not SaveManager.select_car(_viewed):
			_notice("Couldn't select that car.", true)
		return
	var result := SaveManager.try_purchase_car(_viewed)
	if not bool(result.get("ok", false)):
		_notice(UiPalette.reason_text(result), true)
		_refresh_buttons()


func _on_style(style_id: String) -> void:
	if not SaveManager.owns_car(_viewed):
		_notice("Buy the car before paint.", true)
		return
	var preview := SaveManager.preview_paint(style_id)
	if not bool(preview.get("ok", false)):
		_notice(UiPalette.reason_text(preview), true)
		return
	if not bool(preview.get("owned", false)):
		var bought := SaveManager.try_purchase_paint(style_id)
		if not bool(bought.get("ok", false)):
			_notice(UiPalette.reason_text(bought), true)
			_refresh_buttons()
			return
	_style = style_id
	_apply_paint()
	_refresh_buttons()


func _on_upgrade(upgrade_id: String) -> void:
	var result := SaveManager.try_upgrade(_viewed, upgrade_id)
	if not bool(result.get("ok", false)):
		_notice(UiPalette.reason_text(result), true)
	_refresh_buttons()


func _on_color(color: Color, slot: String) -> void:
	if _syncing:
		return
	_colors[slot] = color
	_apply_paint()


func _apply_paint() -> void:
	if not SaveManager.owns_car(_viewed) or not SaveManager.owns_paint_style(_style):
		return
	var primary: Color = _colors["primary"]
	var secondary: Color = _colors["secondary"]
	var accent: Color = _colors["accent"]
	var result := SaveManager.set_car_paint(_viewed, _style, primary, secondary, accent)
	if not bool(result.get("ok", false)):
		_notice(UiPalette.reason_text(result), true)


func _sync_wallet() -> void:
	%Wallet.text = UiPalette.money(SaveManager.get_cr())


func _notice(text: String, bad: bool = false) -> void:
	%Notice.text = text
	%Notice.add_theme_color_override("font_color", UiPalette.DANGER if bad else UiPalette.MUTED)


func _short_car(car_id: String) -> String:
	match car_id:
		GameData.CAR_STREET_86:
			return "86"
		GameData.CAR_SILVIA:
			return "SILVIA"
		GameData.CAR_GTR:
			return "GT-R"
		GameData.CAR_HYPERION:
			return "APEX"
		_:
			return str(GameData.get_car(car_id).get("name", car_id))
