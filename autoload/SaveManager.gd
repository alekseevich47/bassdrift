extends Node

## Versioned JSON profile for APEX BEAT.
## Writes user://save.json and keeps the previous good file at user://save.bak.json.
## Schema migrations run in order whenever SAVE_VERSION increases.

const SAVE_VERSION := 2
const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.bak.json"
const CORRUPT_PATH := "user://save.corrupt.json"
const STARTER_CAR := "street_86"
const MAX_UPGRADE_LEVEL := 5
const MAX_PERK_LEVEL := 5
const MAX_PILOT_LEVEL := 50
const MIN_AUDIO_LATENCY_MS := -250
const MAX_AUDIO_LATENCY_MS := 250
const GRAPHICS_QUALITIES: Array = ["low", "medium", "high"]
const DIFFICULTIES: Array = ["chill", "drive", "hardcore"]
const PAINT_STYLES: Array = ["gloss", "metallic", "chameleon"]

signal save_loaded(state: Dictionary)
signal save_reset
signal save_failed(reason: String)
signal currency_changed(cr: int)
signal pilot_changed(level: int, xp: int, skill_points: int)
signal garage_changed
signal campaign_changed
signal settings_changed

var recovered_from_backup := false
var last_error := ""

var _state: Dictionary = {}
var _loaded := false
var _write_blocked := false


func _ready() -> void:
	load_save()


func load_save() -> bool:
	recovered_from_backup = false
	_write_blocked = false
	last_error = ""
	var main_result := _read_json(SAVE_PATH)
	if main_result["ok"]:
		if _too_new(main_result["data"]):
			_write_blocked = true
			last_error = "save_newer_than_build"
			save_failed.emit(last_error)
			var newer_backup := _read_json(BACKUP_PATH)
			if newer_backup["ok"] and not _too_new(newer_backup["data"]):
				_apply_loaded(newer_backup["data"], true)
				return true
			_state = _default_state()
			_loaded = true
			_apply_runtime_settings()
			save_loaded.emit(get_state_copy())
			return false
		_apply_loaded(main_result["data"], false)
		return true
	if main_result["error"] == "corrupt":
		_quarantine_corrupt()
	var backup := _read_json(BACKUP_PATH)
	if backup["ok"] and not _too_new(backup["data"]):
		_apply_loaded(backup["data"], true)
		save_game(false)
		return true
	_state = _default_state()
	_loaded = true
	_apply_runtime_settings()
	save_loaded.emit(get_state_copy())
	if main_result["error"] == "missing" or main_result["error"] == "corrupt":
		save_game(false)
		return true
	last_error = str(main_result["error"])
	save_failed.emit(last_error)
	return false


func save_game(update_backup: bool = true) -> bool:
	if not _loaded:
		load_save()
	if _write_blocked:
		last_error = "write_blocked"
		save_failed.emit(last_error)
		return false
	if update_backup and FileAccess.file_exists(SAVE_PATH):
		var previous := FileAccess.get_file_as_string(SAVE_PATH)
		if _text_is_save(previous):
			if not _write_text(BACKUP_PATH, previous):
				last_error = "backup_failed"
				save_failed.emit(last_error)
				return false
	_state["version"] = SAVE_VERSION
	var payload := JSON.stringify(_state, "\t")
	if not _write_atomic(SAVE_PATH, payload):
		last_error = "write_failed"
		save_failed.emit(last_error)
		return false
	if not FileAccess.file_exists(BACKUP_PATH):
		if not _write_text(BACKUP_PATH, payload):
			last_error = "backup_failed"
			save_failed.emit(last_error)
			return false
	last_error = ""
	return true


func reset_save() -> void:
	var blocked := _write_blocked
	_write_blocked = false
	_state = _default_state()
	_loaded = true
	if not blocked:
		save_game(true)
	else:
		_write_blocked = true
	_apply_runtime_settings()
	if _catalog_ready():
		bind_catalog()
	save_reset.emit()
	save_loaded.emit(get_state_copy())


func migrate(data: Dictionary) -> Dictionary:
	var working := data.duplicate(true)
	var version := int(working.get("version", 0))
	if version < 1:
		working = _migrate_to_v1(working)
		version = 1
	if version < 2:
		working = _migrate_to_v2(working)
		version = 2
	if version < SAVE_VERSION:
		push_error("SaveManager: SAVE_VERSION %d has no migration step past v%d" % [SAVE_VERSION, version])
	working["version"] = SAVE_VERSION
	return _normalize(working)


func bind_catalog() -> void:
	if not _catalog_ready():
		return
	_ensure_loaded()
	var changed := false
	for car_id in GameData.car_ids():
		var car_key := str(car_id)
		if not (_state["upgrades"] as Dictionary).has(car_key):
			_state["upgrades"][car_key] = {}
			changed = true
		var paint_cars: Dictionary = _state["paint"]["cars"]
		if not paint_cars.has(car_key):
			paint_cars[car_key] = GameData.default_paint(car_key)
			changed = true
	for perk_id in GameData.perk_ids():
		if not (_state["perks"] as Dictionary).has(str(perk_id)):
			_state["perks"][str(perk_id)] = 0
			changed = true
	_state = _normalize(_state)
	if changed:
		save_game(false)
		garage_changed.emit()


func get_state_copy() -> Dictionary:
	_ensure_loaded()
	return _state.duplicate(true)


func get_save_path() -> String:
	return SAVE_PATH


func get_backup_path() -> String:
	return BACKUP_PATH


func get_cr() -> int:
	_ensure_loaded()
	return int(_state["currency"]["cr"])


func can_afford(amount: int) -> bool:
	return amount >= 0 and get_cr() >= amount


func add_cr(amount: int, reason: String = "") -> int:
	_ensure_loaded()
	var gain := int(max(amount, 0))
	if gain == 0:
		return get_cr()
	_state["currency"]["cr"] = get_cr() + gain
	_state["stats"]["cr_earned"] = int(_state["stats"]["cr_earned"]) + gain
	_state["stats"]["last_cr_reason"] = reason
	currency_changed.emit(get_cr())
	save_game()
	return get_cr()


func spend_cr(amount: int, reason: String = "", autosave: bool = true) -> bool:
	_ensure_loaded()
	var cost := int(amount)
	if cost <= 0 or get_cr() < cost:
		return false
	_state["currency"]["cr"] = get_cr() - cost
	_state["stats"]["cr_spent"] = int(_state["stats"]["cr_spent"]) + cost
	_state["stats"]["last_cr_reason"] = reason
	currency_changed.emit(get_cr())
	if autosave:
		save_game()
	return true


func get_pilot_level() -> int:
	_ensure_loaded()
	return int(_state["pilot"]["level"])


func get_pilot_xp() -> int:
	_ensure_loaded()
	return int(_state["pilot"]["xp"])


func get_skill_points() -> int:
	_ensure_loaded()
	return int(_state["pilot"]["skill_points"])


func get_rank_id() -> String:
	if not _catalog_ready():
		return "novice"
	return str(GameData.get_rank_for_level(get_pilot_level())["id"])


func add_xp(amount: int, reason: String = "") -> Dictionary:
	_ensure_loaded()
	if not _catalog_ready():
		return {"ok": false, "reason": "catalog_unavailable"}
	var gain := int(max(amount, 0))
	if gain == 0:
		return {
			"ok": true,
			"levels_gained": 0,
			"skill_points_gained": 0,
			"level": get_pilot_level(),
			"xp": get_pilot_xp(),
			"reason": reason,
		}
	var level := get_pilot_level()
	var xp := get_pilot_xp() + gain
	var levels_gained := 0
	var points_gained := 0
	while level < GameData.MAX_PILOT_LEVEL and xp >= GameData.xp_to_next(level):
		xp -= GameData.xp_to_next(level)
		level += 1
		levels_gained += 1
		points_gained += GameData.skill_points_for_level_up(level)
	if level >= GameData.MAX_PILOT_LEVEL:
		xp = 0
	_state["pilot"]["level"] = level
	_state["pilot"]["xp"] = xp
	_state["pilot"]["skill_points"] = get_skill_points() + points_gained
	_state["stats"]["xp_earned"] = int(_state["stats"]["xp_earned"]) + gain
	pilot_changed.emit(level, xp, get_skill_points())
	save_game()
	return {
		"ok": true,
		"levels_gained": levels_gained,
		"skill_points_gained": points_gained,
		"level": level,
		"xp": xp,
		"skill_points": get_skill_points(),
		"reason": reason,
	}


func spend_skill_points(amount: int, autosave: bool = true) -> bool:
	_ensure_loaded()
	var cost := int(amount)
	if cost <= 0 or get_skill_points() < cost:
		return false
	_state["pilot"]["skill_points"] = get_skill_points() - cost
	pilot_changed.emit(get_pilot_level(), get_pilot_xp(), get_skill_points())
	if autosave:
		save_game()
	return true


func get_owned_cars() -> Array:
	_ensure_loaded()
	return (_state["owned_cars"] as Array).duplicate()


func owns_car(car_id: String) -> bool:
	return get_owned_cars().has(car_id)


func get_selected_car() -> String:
	_ensure_loaded()
	var selected := str(_state["selected_car"])
	if not owns_car(selected):
		return STARTER_CAR
	return selected


func select_car(car_id: String) -> bool:
	if not owns_car(car_id):
		return false
	_state["selected_car"] = car_id
	garage_changed.emit()
	save_game()
	return true


func unlock_car(car_id: String) -> bool:
	_ensure_loaded()
	if car_id.is_empty():
		return false
	if owns_car(car_id):
		return true
	(_state["owned_cars"] as Array).append(car_id)
	garage_changed.emit()
	save_game()
	return true


func preview_car(car_id: String) -> Dictionary:
	if not _catalog_ready() or not GameData.has_car(car_id):
		return {"ok": false, "reason": "unknown_car"}
	var car := GameData.get_car(car_id)
	var stars := get_total_stars()
	var price := int(car["price_cr"])
	var gate := int(car["unlock_stars"])
	var owned := owns_car(car_id)
	return {
		"ok": true,
		"owned": owned,
		"price_cr": price,
		"unlock_stars": gate,
		"stars": stars,
		"stars_met": stars >= gate,
		"can_buy": (not owned) and stars >= gate and get_cr() >= price,
		"car": car,
	}


func try_purchase_car(car_id: String) -> Dictionary:
	var preview := preview_car(car_id)
	if not preview.get("ok", false):
		return preview
	if preview["owned"]:
		return {"ok": false, "reason": "already_owned"}
	if not preview["stars_met"]:
		return {"ok": false, "reason": "stars_locked", "unlock_stars": preview["unlock_stars"]}
	var price := int(preview["price_cr"])
	if price > 0 and not spend_cr(price, "car:%s" % car_id, false):
		return {"ok": false, "reason": "not_enough_cr", "price_cr": price}
	(_state["owned_cars"] as Array).append(car_id)
	_state["selected_car"] = car_id
	garage_changed.emit()
	save_game()
	return {"ok": true, "car_id": car_id, "price_cr": price}


func get_upgrade_level(car_id: String, upgrade_id: String) -> int:
	_ensure_loaded()
	var per_car: Dictionary = _state["upgrades"]
	if not per_car.has(car_id) or typeof(per_car[car_id]) != TYPE_DICTIONARY:
		return 0
	return int((per_car[car_id] as Dictionary).get(upgrade_id, 0))


func preview_upgrade(car_id: String, upgrade_id: String) -> Dictionary:
	if not _catalog_ready() or not GameData.has_upgrade(upgrade_id):
		return {"ok": false, "reason": "unknown_upgrade"}
	if not owns_car(car_id):
		return {"ok": false, "reason": "car_not_owned"}
	var current := get_upgrade_level(car_id, upgrade_id)
	var maxed := current >= GameData.MAX_UPGRADE_LEVEL
	var next_level := current if maxed else current + 1
	var cost := 0 if maxed else GameData.upgrade_cost(upgrade_id, next_level)
	return {
		"ok": true,
		"level": current,
		"maxed": maxed,
		"next_level": next_level,
		"cost": cost,
		"can_afford": (not maxed) and get_cr() >= cost,
		"effect": GameData.upgrade_effect(upgrade_id, current),
		"next_effect": GameData.upgrade_effect(upgrade_id, next_level),
	}


func try_upgrade(car_id: String, upgrade_id: String) -> Dictionary:
	var preview := preview_upgrade(car_id, upgrade_id)
	if not preview.get("ok", false):
		return preview
	if preview["maxed"]:
		return {"ok": false, "reason": "max_level", "level": preview["level"]}
	var cost := int(preview["cost"])
	if not spend_cr(cost, "upgrade:%s" % upgrade_id, false):
		return {"ok": false, "reason": "not_enough_cr", "cost": cost}
	if not (_state["upgrades"] as Dictionary).has(car_id):
		_state["upgrades"][car_id] = {}
	_state["upgrades"][car_id][upgrade_id] = int(preview["next_level"])
	garage_changed.emit()
	save_game()
	return {"ok": true, "level": int(preview["next_level"]), "cost": cost}


func get_perk_level(perk_id: String) -> int:
	_ensure_loaded()
	return int((_state["perks"] as Dictionary).get(perk_id, 0))


func preview_perk(perk_id: String) -> Dictionary:
	if not _catalog_ready() or not GameData.has_perk(perk_id):
		return {"ok": false, "reason": "unknown_perk"}
	var current := get_perk_level(perk_id)
	var maxed := current >= GameData.MAX_PERK_LEVEL
	var next_level := current if maxed else current + 1
	var cost := 0 if maxed else GameData.perk_cost(perk_id, next_level)
	return {
		"ok": true,
		"level": current,
		"maxed": maxed,
		"next_level": next_level,
		"cost": cost,
		"can_afford": (not maxed) and get_skill_points() >= cost,
		"effect": GameData.perk_effect(perk_id, current),
		"next_effect": GameData.perk_effect(perk_id, next_level),
	}


func try_upgrade_perk(perk_id: String) -> Dictionary:
	var preview := preview_perk(perk_id)
	if not preview.get("ok", false):
		return preview
	if preview["maxed"]:
		return {"ok": false, "reason": "max_level", "level": preview["level"]}
	var cost := int(preview["cost"])
	if not spend_skill_points(cost, false):
		return {"ok": false, "reason": "not_enough_skill_points", "cost": cost}
	_state["perks"][perk_id] = int(preview["next_level"])
	pilot_changed.emit(get_pilot_level(), get_pilot_xp(), get_skill_points())
	save_game()
	return {"ok": true, "level": int(preview["next_level"]), "cost": cost}


func get_level_stars(level_id: String) -> int:
	_ensure_loaded()
	return int((_state["campaign"]["stars"] as Dictionary).get(level_id, 0))


func get_level_best_score(level_id: String) -> int:
	_ensure_loaded()
	return int((_state["campaign"]["best_scores"] as Dictionary).get(level_id, 0))


func get_total_stars() -> int:
	_ensure_loaded()
	var total := 0
	for level_id in (_state["campaign"]["stars"] as Dictionary).keys():
		total += int(_state["campaign"]["stars"][level_id])
	return total


func is_level_unlocked(level_id: String) -> bool:
	if not _catalog_ready() or not GameData.has_level(level_id):
		return false
	return get_total_stars() >= int(GameData.get_level(level_id)["unlock_stars"])


func get_continue_level_id() -> String:
	if not _catalog_ready():
		return ""
	var fallback := ""
	for level_id in GameData.level_ids():
		var id := str(level_id)
		if not is_level_unlocked(id):
			continue
		fallback = id
		if get_level_stars(id) < GameData.STAR_CAP:
			return id
	if not fallback.is_empty():
		return fallback
	var ids := GameData.level_ids()
	return str(ids[0]) if not ids.is_empty() else ""


func record_level_result(level_id: String, score: int, stars: int = -1) -> Dictionary:
	if not _catalog_ready() or not GameData.has_level(level_id):
		return {"ok": false, "reason": "unknown_level"}
	if not is_level_unlocked(level_id):
		return {"ok": false, "reason": "locked"}
	var level := GameData.get_level(level_id)
	var safe_score := int(max(score, 0))
	var earned := GameData.stars_for_score(level_id, safe_score)
	var star_count := earned if stars < 0 else int(min(int(stars), earned))
	star_count = clampi(star_count, 0, GameData.STAR_CAP)
	var prev_stars := get_level_stars(level_id)
	var prev_best := get_level_best_score(level_id)
	var new_stars: int = int(max(prev_stars, star_count))
	var new_best: int = int(max(prev_best, safe_score))
	var star_delta: int = new_stars - prev_stars
	var difficulty := get_difficulty()
	var diff := GameData.get_difficulty(difficulty)
	var cr_scale := float(diff.get("cr_scale", 1.0))
	var cash := GameData.perk_effect(GameData.PERK_CASH, get_perk_level(GameData.PERK_CASH))
	var cr_mult := cr_scale * (1.0 + float(cash.get("cr_bonus", 0.0)))
	var base_cr := int(level["reward_cr"])
	var base_xp := int(level["reward_xp"])
	var cr_gain := 0
	var xp_gain := 0
	if safe_score > 0:
		cr_gain = int(round(float(base_cr + star_delta * base_cr) * cr_mult))
		xp_gain = base_xp + star_delta * 25
	_state["campaign"]["stars"][level_id] = new_stars
	_state["campaign"]["best_scores"][level_id] = new_best
	_state["stats"]["races_finished"] = int(_state["stats"]["races_finished"]) + 1
	if cr_gain > 0:
		_state["currency"]["cr"] = get_cr() + cr_gain
		_state["stats"]["cr_earned"] = int(_state["stats"]["cr_earned"]) + cr_gain
		currency_changed.emit(get_cr())
	campaign_changed.emit()
	var xp_result := {}
	if xp_gain > 0:
		xp_result = add_xp(xp_gain, "race:%s" % level_id)
	else:
		save_game()
	return {
		"ok": true,
		"level_id": level_id,
		"score": safe_score,
		"stars": star_count,
		"best_stars": new_stars,
		"best_score": new_best,
		"star_delta": star_delta,
		"cr_gain": cr_gain,
		"xp_gain": xp_gain,
		"xp_result": xp_result,
	}


func get_settings() -> Dictionary:
	_ensure_loaded()
	return (_state["settings"] as Dictionary).duplicate(true)


func get_music_volume() -> float:
	return float(get_settings()["music_volume"])


func set_music_volume(value: float) -> void:
	_ensure_loaded()
	_state["settings"]["music_volume"] = clampf(value, 0.0, 1.0)
	_commit_settings()


func is_music_enabled() -> bool:
	return bool(get_settings()["music_enabled"])


func set_music_enabled(enabled: bool) -> void:
	_ensure_loaded()
	_state["settings"]["music_enabled"] = enabled
	_commit_settings()


func get_sfx_volume() -> float:
	return float(get_settings()["sfx_volume"])


func set_sfx_volume(value: float) -> void:
	_ensure_loaded()
	_state["settings"]["sfx_volume"] = clampf(value, 0.0, 1.0)
	_commit_settings()


func is_sfx_enabled() -> bool:
	return bool(get_settings()["sfx_enabled"])


func set_sfx_enabled(enabled: bool) -> void:
	_ensure_loaded()
	_state["settings"]["sfx_enabled"] = enabled
	_commit_settings()


func get_graphics_quality() -> String:
	return str(get_settings()["graphics_quality"])


func set_graphics_quality(quality: String) -> bool:
	_ensure_loaded()
	if not GRAPHICS_QUALITIES.has(quality):
		return false
	_state["settings"]["graphics_quality"] = quality
	_commit_settings()
	return true


func get_audio_latency_ms() -> int:
	return int(get_settings()["audio_latency_ms"])


func set_audio_latency_ms(latency_ms: int) -> int:
	_ensure_loaded()
	var clamped := clampi(latency_ms, MIN_AUDIO_LATENCY_MS, MAX_AUDIO_LATENCY_MS)
	_state["settings"]["audio_latency_ms"] = clamped
	_commit_settings()
	return clamped


func get_difficulty() -> String:
	_ensure_loaded()
	return str(_state["difficulty"])


func set_difficulty(difficulty_id: String) -> bool:
	_ensure_loaded()
	if not DIFFICULTIES.has(difficulty_id):
		return false
	if _catalog_ready() and not GameData.has_difficulty(difficulty_id):
		return false
	_state["difficulty"] = difficulty_id
	settings_changed.emit()
	save_game()
	return true


func has_seen_tutorial() -> bool:
	_ensure_loaded()
	return bool(_state["tutorial_seen"])


func set_tutorial_seen(seen: bool = true) -> void:
	_ensure_loaded()
	_state["tutorial_seen"] = seen
	save_game()


func has_cleared_driving_tutorial() -> bool:
	_ensure_loaded()
	return bool(_state.get("driving_tutorial_done", false))


func set_driving_tutorial_cleared(done: bool = true) -> void:
	_ensure_loaded()
	_state["driving_tutorial_done"] = done
	if done:
		_state["tutorial_seen"] = true
	save_game()


func get_paint(car_id: String) -> Dictionary:
	_ensure_loaded()
	var cars: Dictionary = _state["paint"]["cars"]
	if cars.has(car_id) and typeof(cars[car_id]) == TYPE_DICTIONARY:
		return (cars[car_id] as Dictionary).duplicate(true)
	if _catalog_ready():
		return GameData.default_paint(car_id)
	return {"style": "gloss", "primary": "#e6e6ea", "secondary": "#16161c", "accent": "#ff2d8a"}


func owns_paint_style(style_id: String) -> bool:
	_ensure_loaded()
	return (_state["paint"]["owned_styles"] as Array).has(style_id)


func preview_paint(style_id: String) -> Dictionary:
	if not _catalog_ready() or not GameData.has_paint_style(style_id):
		return {"ok": false, "reason": "unknown_paint"}
	var style := GameData.get_paint_style(style_id)
	var price := int(style["price_cr"])
	var owned := owns_paint_style(style_id)
	return {
		"ok": true,
		"owned": owned,
		"price_cr": price,
		"can_buy": (not owned) and get_cr() >= price,
		"style": style,
	}


func try_purchase_paint(style_id: String) -> Dictionary:
	var preview := preview_paint(style_id)
	if not preview.get("ok", false):
		return preview
	if preview["owned"]:
		return {"ok": true, "style_id": style_id, "price_cr": 0, "already_owned": true}
	var price := int(preview["price_cr"])
	if price > 0 and not spend_cr(price, "paint:%s" % style_id, false):
		return {"ok": false, "reason": "not_enough_cr", "price_cr": price}
	(_state["paint"]["owned_styles"] as Array).append(style_id)
	garage_changed.emit()
	save_game()
	return {"ok": true, "style_id": style_id, "price_cr": price, "already_owned": false}


func set_car_paint(car_id: String, style_id: String, primary: Color, secondary: Color, accent: Color) -> Dictionary:
	if not owns_car(car_id):
		return {"ok": false, "reason": "car_not_owned"}
	if not owns_paint_style(style_id):
		return {"ok": false, "reason": "paint_not_owned"}
	if _catalog_ready() and not GameData.has_paint_style(style_id):
		return {"ok": false, "reason": "unknown_paint"}
	_state["paint"]["cars"][car_id] = {
		"style": style_id,
		"primary": _html_color(primary),
		"secondary": _html_color(secondary),
		"accent": _html_color(accent),
	}
	garage_changed.emit()
	save_game()
	return {"ok": true, "paint": get_paint(car_id)}


func _apply_loaded(data: Dictionary, from_backup: bool) -> void:
	_state = migrate(data)
	_loaded = true
	recovered_from_backup = from_backup
	_apply_runtime_settings()
	save_loaded.emit(get_state_copy())


func _ensure_loaded() -> void:
	if not _loaded:
		load_save()


func _commit_settings() -> void:
	_apply_runtime_settings()
	settings_changed.emit()
	save_game()


func _apply_runtime_settings() -> void:
	var settings: Dictionary = _state.get("settings", {})
	_apply_bus("Music", float(settings.get("music_volume", 0.85)), bool(settings.get("music_enabled", true)))
	_apply_bus("SFX", float(settings.get("sfx_volume", 1.0)), bool(settings.get("sfx_enabled", true)))


func _apply_bus(bus_name: String, linear: float, enabled: bool) -> void:
	var idx := _ensure_bus(bus_name)
	if idx < 0:
		return
	var audible := enabled and linear > 0.001
	AudioServer.set_bus_mute(idx, not audible)
	if audible:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.001, 1.0)))


func _ensure_bus(bus_name: String) -> int:
	var existing := AudioServer.get_bus_index(bus_name)
	if existing >= 0:
		return existing
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


func _catalog_ready() -> bool:
	return get_node_or_null("/root/GameData") != null


func _pilot_cap() -> int:
	if _catalog_ready():
		return maxi(int(GameData.MAX_PILOT_LEVEL), 1)
	return MAX_PILOT_LEVEL


func _default_state() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"currency": {"cr": 0},
		"pilot": {"xp": 0, "level": 1, "skill_points": 0},
		"owned_cars": [STARTER_CAR],
		"selected_car": STARTER_CAR,
		"upgrades": {},
		"perks": {},
		"campaign": {"stars": {}, "best_scores": {}},
		"paint": {"owned_styles": ["gloss"], "cars": {}},
		"settings": _default_settings(),
		"difficulty": "drive",
		"tutorial_seen": false,
		"driving_tutorial_done": false,
		"stats": {"races_finished": 0, "cr_earned": 0, "cr_spent": 0, "xp_earned": 0, "last_cr_reason": ""},
	}


func _default_settings() -> Dictionary:
	return {
		"music_enabled": true,
		"sfx_enabled": true,
		"music_volume": 0.85,
		"sfx_volume": 1.0,
		"graphics_quality": "medium",
		"audio_latency_ms": 0,
	}


func _migrate_to_v1(data: Dictionary) -> Dictionary:
	if not data.has("version"):
		data["version"] = 1
	if not data.has("pilot") or typeof(data["pilot"]) != TYPE_DICTIONARY:
		data["pilot"] = {"xp": 0, "level": 1, "skill_points": 0}
	if not data.has("owned_cars"):
		data["owned_cars"] = [STARTER_CAR]
	if not data.has("selected_car"):
		data["selected_car"] = STARTER_CAR
	if not data.has("upgrades"):
		data["upgrades"] = {}
	if not data.has("perks"):
		data["perks"] = {}
	if not data.has("settings") or typeof(data["settings"]) != TYPE_DICTIONARY:
		data["settings"] = {"music": 0.85, "sfx": 1.0}
	if not data.has("tutorial_seen"):
		data["tutorial_seen"] = false
	data["version"] = 1
	return data


func _migrate_to_v2(data: Dictionary) -> Dictionary:
	var currency: Dictionary = data.get("currency", {}) if typeof(data.get("currency")) == TYPE_DICTIONARY else {}
	if not currency.has("cr"):
		currency["cr"] = int(data.get("cr", 0))
	data["currency"] = currency
	data.erase("cr")
	var settings: Dictionary = data.get("settings", {}) if typeof(data.get("settings")) == TYPE_DICTIONARY else {}
	if settings.has("music") and not settings.has("music_volume"):
		settings["music_volume"] = float(settings["music"])
	if settings.has("sfx") and not settings.has("sfx_volume"):
		settings["sfx_volume"] = float(settings["sfx"])
	settings.erase("music")
	settings.erase("sfx")
	for key in _default_settings().keys():
		if not settings.has(key):
			settings[key] = _default_settings()[key]
	data["settings"] = settings
	var campaign: Dictionary = data.get("campaign", {}) if typeof(data.get("campaign")) == TYPE_DICTIONARY else {}
	if not campaign.has("stars"):
		var legacy_stars = data.get("stars", {})
		campaign["stars"] = legacy_stars if typeof(legacy_stars) == TYPE_DICTIONARY else {}
	if not campaign.has("best_scores") or typeof(campaign["best_scores"]) != TYPE_DICTIONARY:
		campaign["best_scores"] = {}
	data["campaign"] = campaign
	data.erase("stars")
	if not data.has("paint") or typeof(data["paint"]) != TYPE_DICTIONARY:
		data["paint"] = {"owned_styles": ["gloss"], "cars": {}}
	if not data.has("difficulty"):
		data["difficulty"] = "drive"
	if not data.has("stats") or typeof(data["stats"]) != TYPE_DICTIONARY:
		data["stats"] = {"races_finished": 0, "cr_earned": 0, "cr_spent": 0, "xp_earned": 0, "last_cr_reason": ""}
	data["version"] = 2
	return data


func _normalize(data: Dictionary) -> Dictionary:
	var defaults := _default_state()
	data["version"] = SAVE_VERSION
	var currency: Dictionary = data.get("currency", {}) if typeof(data.get("currency")) == TYPE_DICTIONARY else {}
	currency["cr"] = int(max(int(currency.get("cr", 0)), 0))
	data["currency"] = currency
	var pilot: Dictionary = data.get("pilot", {}) if typeof(data.get("pilot")) == TYPE_DICTIONARY else {}
	var pilot_cap := _pilot_cap()
	var pilot_level := clampi(int(pilot.get("level", 1)), 1, pilot_cap)
	var pilot_xp := int(max(int(pilot.get("xp", 0)), 0))
	if pilot_level >= pilot_cap:
		pilot_xp = 0
	pilot["level"] = pilot_level
	pilot["xp"] = pilot_xp
	pilot["skill_points"] = int(max(int(pilot.get("skill_points", 0)), 0))
	data["pilot"] = pilot
	data["owned_cars"] = _string_list(data.get("owned_cars"), [STARTER_CAR])
	if not (data["owned_cars"] as Array).has(STARTER_CAR):
		(data["owned_cars"] as Array).push_front(STARTER_CAR)
	var selected := str(data.get("selected_car", STARTER_CAR))
	if not (data["owned_cars"] as Array).has(selected):
		selected = STARTER_CAR
	data["selected_car"] = selected
	var upgrades_in: Dictionary = data.get("upgrades", {}) if typeof(data.get("upgrades")) == TYPE_DICTIONARY else {}
	var upgrades_out := {}
	for car_id in upgrades_in.keys():
		upgrades_out[str(car_id)] = _clamp_level_map(upgrades_in[car_id], MAX_UPGRADE_LEVEL)
	data["upgrades"] = upgrades_out
	data["perks"] = _clamp_level_map(data.get("perks", {}), MAX_PERK_LEVEL)
	var campaign_in: Dictionary = data.get("campaign", {}) if typeof(data.get("campaign")) == TYPE_DICTIONARY else {}
	data["campaign"] = {
		"stars": _clamp_level_map(campaign_in.get("stars", {}), 3),
		"best_scores": _non_negative_int_map(campaign_in.get("best_scores", {})),
	}
	var paint_in: Dictionary = data.get("paint", {}) if typeof(data.get("paint")) == TYPE_DICTIONARY else {}
	var owned_styles := _string_list(paint_in.get("owned_styles"), ["gloss"])
	if not owned_styles.has("gloss"):
		owned_styles.push_front("gloss")
	var paint_cars_in: Dictionary = paint_in.get("cars", {}) if typeof(paint_in.get("cars")) == TYPE_DICTIONARY else {}
	var paint_cars_out := {}
	for car_id in paint_cars_in.keys():
		paint_cars_out[str(car_id)] = _normalize_paint(paint_cars_in[car_id])
	data["paint"] = {"owned_styles": owned_styles, "cars": paint_cars_out}
	var settings_in: Dictionary = data.get("settings", {}) if typeof(data.get("settings")) == TYPE_DICTIONARY else {}
	var settings := _default_settings()
	settings["music_enabled"] = bool(settings_in.get("music_enabled", true))
	settings["sfx_enabled"] = bool(settings_in.get("sfx_enabled", true))
	settings["music_volume"] = clampf(float(settings_in.get("music_volume", settings["music_volume"])), 0.0, 1.0)
	settings["sfx_volume"] = clampf(float(settings_in.get("sfx_volume", settings["sfx_volume"])), 0.0, 1.0)
	var quality := str(settings_in.get("graphics_quality", "medium"))
	settings["graphics_quality"] = quality if GRAPHICS_QUALITIES.has(quality) else "medium"
	settings["audio_latency_ms"] = clampi(int(settings_in.get("audio_latency_ms", 0)), MIN_AUDIO_LATENCY_MS, MAX_AUDIO_LATENCY_MS)
	data["settings"] = settings
	var difficulty := str(data.get("difficulty", "drive"))
	data["difficulty"] = difficulty if DIFFICULTIES.has(difficulty) else "drive"
	data["tutorial_seen"] = bool(data.get("tutorial_seen", false))
	data["driving_tutorial_done"] = bool(data.get("driving_tutorial_done", false))
	var stats_in: Dictionary = data.get("stats", {}) if typeof(data.get("stats")) == TYPE_DICTIONARY else {}
	var stats: Dictionary = defaults["stats"]
	stats["races_finished"] = int(max(int(stats_in.get("races_finished", 0)), 0))
	stats["cr_earned"] = int(max(int(stats_in.get("cr_earned", 0)), 0))
	stats["cr_spent"] = int(max(int(stats_in.get("cr_spent", 0)), 0))
	stats["xp_earned"] = int(max(int(stats_in.get("xp_earned", 0)), 0))
	stats["last_cr_reason"] = str(stats_in.get("last_cr_reason", ""))
	data["stats"] = stats
	return data


func _normalize_paint(raw) -> Dictionary:
	var source: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var style := str(source.get("style", "gloss"))
	if not PAINT_STYLES.has(style):
		style = "gloss"
	return {
		"style": style,
		"primary": _normalize_html_color(source.get("primary", "#e6e6ea"), "#e6e6ea"),
		"secondary": _normalize_html_color(source.get("secondary", "#16161c"), "#16161c"),
		"accent": _normalize_html_color(source.get("accent", "#ff2d8a"), "#ff2d8a"),
	}


func _clamp_level_map(raw, max_level: int) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key in raw.keys():
		out[str(key)] = clampi(int(raw[key]), 0, max_level)
	return out


func _non_negative_int_map(raw) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key in raw.keys():
		out[str(key)] = int(max(int(raw[key]), 0))
	return out


func _string_list(raw, fallback: Array) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return fallback.duplicate()
	for entry in raw:
		var text := str(entry).strip_edges()
		if text.is_empty() or out.has(text):
			continue
		out.append(text)
	if out.is_empty():
		return fallback.duplicate()
	return out


func _normalize_html_color(value, fallback: String) -> String:
	var text := str(value).strip_edges()
	if text.begins_with("#"):
		text = text.substr(1)
	if text.length() != 6:
		return fallback
	for i in text.length():
		var code := text.unicode_at(i)
		var hex := (code >= 48 and code <= 57) or (code >= 65 and code <= 70) or (code >= 97 and code <= 102)
		if not hex:
			return fallback
	return "#" + text.to_lower()


func _html_color(color: Color) -> String:
	return "#" + color.to_html(false)


func _too_new(data: Dictionary) -> bool:
	return int(data.get("version", 0)) > SAVE_VERSION


func _text_is_save(text: String) -> bool:
	if text.strip_edges().is_empty():
		return false
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return false
	return int((parser.data as Dictionary).get("version", 0)) > 0


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "missing", "data": {}}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return {"ok": false, "error": "corrupt", "data": {}}
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "corrupt", "data": {}}
	return {"ok": true, "error": "", "data": parser.data}


func _quarantine_corrupt() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists("save.corrupt.json"):
		dir.remove("save.corrupt.json")
	if dir.file_exists("save.json"):
		dir.rename("save.json", "save.corrupt.json")


func _write_text(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "open_failed:%s" % FileAccess.get_open_error()
		return false
	file.store_string(contents)
	var err := file.get_error()
	file.close()
	return err == OK


func _write_atomic(path: String, contents: String) -> bool:
	var tmp_name := "save.json.tmp"
	var final_name := path.trim_prefix("user://")
	if not _write_text("user://" + tmp_name, contents):
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		last_error = "user_dir_missing"
		return false
	if dir.file_exists(final_name):
		var removed := dir.remove(final_name)
		if removed != OK:
			last_error = "replace_failed:%s" % removed
			return false
	var renamed := dir.rename(tmp_name, final_name)
	if renamed != OK:
		last_error = "rename_failed:%s" % renamed
		return false
	return true
