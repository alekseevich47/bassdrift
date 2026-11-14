extends Node

## Static campaign catalog for APEX BEAT.
## Cars, upgrades, pilot perks, ranks, chapters, paint, and difficulty.
## Safe to query any time after this autoload enters the tree.

const MAX_UPGRADE_LEVEL := 5
const MAX_PERK_LEVEL := 5
const MAX_PILOT_LEVEL := 50
const STAR_CAP := 3

const CAR_STREET_86 := "street_86"
const CAR_SILVIA := "silvia_s_spec"
const CAR_GTR := "gtr_skyline"
const CAR_HYPERION := "apex_hyperion"

const UPGRADE_DRIFT_ANGLE := "drift_angle"
const UPGRADE_TURBO := "turbo_boost"
const UPGRADE_ARMOR := "armor"
const UPGRADE_MAGNET := "magnet"

const PERK_BEAT_WINDOW := "beat_window"
const PERK_COMBO := "combo_keeper"
const PERK_CASH := "cash_flow"
const PERK_FOCUS := "focus_slowmo"

const RANK_NOVICE := "novice"
const RANK_STREET := "street_racer"
const RANK_TOUGE := "touge_king"
const RANK_APEX := "apex_legend"

const STYLE_HARUNA := "haruna_dry_night"
const STYLE_SHUTO := "shuto_rain"
const STYLE_DOCKLANDS := "docklands_fog"
const STYLE_APEX := "apex_storm"

const DIFF_CHILL := "chill"
const DIFF_DRIVE := "drive"
const DIFF_HARDCORE := "hardcore"

const PAINT_GLOSS := "gloss"
const PAINT_METALLIC := "metallic"
const PAINT_CHAMELEON := "chameleon"

const GRAPHICS_QUALITIES: Array = ["low", "medium", "high"]

var _cars: Dictionary = {}
var _car_order: Array = []
var _upgrades: Dictionary = {}
var _upgrade_order: Array = []
var _perks: Dictionary = {}
var _perk_order: Array = []
var _ranks: Array = []
var _chapters: Dictionary = {}
var _chapter_order: Array = []
var _levels: Dictionary = {}
var _level_order: Array = []
var _paint: Dictionary = {}
var _paint_order: Array = []
var _difficulties: Dictionary = {}
var _difficulty_order: Array = []


func _init() -> void:
	_build_cars()
	_build_upgrades()
	_build_perks()
	_build_ranks()
	_build_chapters_and_levels()
	_build_paint()
	_build_difficulties()


func _ready() -> void:
	var problems := validate_catalog()
	for problem in problems:
		push_error("GameData: %s" % problem)
	if SaveManager.has_method("bind_catalog"):
		SaveManager.bind_catalog()


func validate_catalog() -> PackedStringArray:
	var problems: PackedStringArray = []
	if _car_order.size() != 4:
		problems.append("expected 4 cars")
	if _upgrade_order.size() != 4:
		problems.append("expected 4 upgrades")
	if _perk_order.size() != 4:
		problems.append("expected 4 perks")
	if _ranks.size() != 4:
		problems.append("expected 4 ranks")
	if _chapter_order.size() != 4:
		problems.append("expected 4 chapters")
	if _level_order.size() != 16:
		problems.append("expected 16 levels")
	if _paint_order.size() != 3:
		problems.append("expected 3 paint styles")
	if _difficulty_order.size() != 3:
		problems.append("expected 3 difficulties")
	var rank_names: Array = []
	for rank in _ranks:
		rank_names.append(rank["name"])
	if rank_names != ["Novice", "Street Racer", "Touge King", "Apex Legend"]:
		problems.append("rank ladder mismatch")
	for chapter_id in _chapter_order:
		var chapter: Dictionary = _chapters[chapter_id]
		var count := 0
		for level_id in _level_order:
			var level: Dictionary = _levels[level_id]
			if level["chapter_id"] != chapter_id:
				continue
			count += 1
			var bpm := int(level["bpm"])
			if bpm < int(chapter["bpm_min"]) or bpm > int(chapter["bpm_max"]):
				problems.append("%s bpm %d outside chapter range" % [level_id, bpm])
			var targets: Array = level["score_targets"]
			if targets.size() != STAR_CAP:
				problems.append("%s needs 3 score targets" % level_id)
			elif int(targets[0]) >= int(targets[1]) or int(targets[1]) >= int(targets[2]):
				problems.append("%s score targets must increase" % level_id)
		if count != 4:
			problems.append("%s should contain 4 levels" % chapter_id)
	return problems


func car_ids() -> Array:
	return _car_order.duplicate()


func get_car(car_id: String) -> Dictionary:
	if not _cars.has(car_id):
		return {}
	return (_cars[car_id] as Dictionary).duplicate(true)


func has_car(car_id: String) -> bool:
	return _cars.has(car_id)


func starter_car_id() -> String:
	return CAR_STREET_86


func upgrade_ids() -> Array:
	return _upgrade_order.duplicate()


func get_upgrade(upgrade_id: String) -> Dictionary:
	if not _upgrades.has(upgrade_id):
		return {}
	return (_upgrades[upgrade_id] as Dictionary).duplicate(true)


func has_upgrade(upgrade_id: String) -> bool:
	return _upgrades.has(upgrade_id)


func upgrade_cost(upgrade_id: String, next_level: int) -> int:
	var spec := get_upgrade(upgrade_id)
	if spec.is_empty() or next_level < 1 or next_level > MAX_UPGRADE_LEVEL:
		return 0
	return int(spec["base_cost"]) * next_level * next_level


func upgrade_effect(upgrade_id: String, level: int) -> Dictionary:
	var spec := get_upgrade(upgrade_id)
	if spec.is_empty():
		return {}
	var clamped := clampi(level, 0, MAX_UPGRADE_LEVEL)
	var per: Dictionary = spec["per_level"]
	var effect := {"level": clamped}
	for key in per.keys():
		effect[key] = float(per[key]) * float(clamped)
	return effect


func perk_ids() -> Array:
	return _perk_order.duplicate()


func get_perk(perk_id: String) -> Dictionary:
	if not _perks.has(perk_id):
		return {}
	return (_perks[perk_id] as Dictionary).duplicate(true)


func has_perk(perk_id: String) -> bool:
	return _perks.has(perk_id)


func perk_cost(perk_id: String, next_level: int) -> int:
	if not has_perk(perk_id) or next_level < 1 or next_level > MAX_PERK_LEVEL:
		return 0
	return 1


func perk_effect(perk_id: String, level: int) -> Dictionary:
	var spec := get_perk(perk_id)
	if spec.is_empty():
		return {}
	var clamped := clampi(level, 0, MAX_PERK_LEVEL)
	var per: Dictionary = spec["per_level"]
	var effect := {"level": clamped}
	for key in per.keys():
		effect[key] = float(per[key]) * float(clamped)
	if clamped > 0:
		var constants: Dictionary = spec.get("constants", {})
		for key in constants.keys():
			effect[key] = constants[key]
	return effect


func timing_window_ms(perk_level: int, difficulty_id: String) -> float:
	var window := 90.0 + float(perk_effect(PERK_BEAT_WINDOW, perk_level).get("window_ms", 0.0))
	return window * float(get_difficulty(difficulty_id).get("window_scale", 1.0))


func ranks() -> Array:
	var copy: Array = []
	for rank in _ranks:
		copy.append((rank as Dictionary).duplicate(true))
	return copy


func get_rank_for_level(level: int) -> Dictionary:
	var current: Dictionary = _ranks[0]
	for rank in _ranks:
		if level >= int(rank["min_level"]):
			current = rank
	return current.duplicate(true)


func skill_points_for_level_up(new_level: int) -> int:
	var points := 1
	for rank in _ranks:
		if int(rank["min_level"]) == new_level and new_level > 1:
			points += 1
	return points


func xp_to_next(level: int) -> int:
	var clamped: int = int(max(level, 1))
	return 100 + (clamped - 1) * 50


func chapter_ids() -> Array:
	return _chapter_order.duplicate()


func get_chapter(chapter_id: String) -> Dictionary:
	if not _chapters.has(chapter_id):
		return {}
	return (_chapters[chapter_id] as Dictionary).duplicate(true)


func level_ids() -> Array:
	return _level_order.duplicate()


func get_level(level_id: String) -> Dictionary:
	if not _levels.has(level_id):
		return {}
	return (_levels[level_id] as Dictionary).duplicate(true)


func has_level(level_id: String) -> bool:
	return _levels.has(level_id)


func chapter_level_ids(chapter_id: String) -> Array:
	var ids: Array = []
	for level_id in _level_order:
		if (_levels[level_id] as Dictionary)["chapter_id"] == chapter_id:
			ids.append(level_id)
	return ids


func stars_for_score(level_id: String, score: int) -> int:
	var level := get_level(level_id)
	if level.is_empty():
		return 0
	var stars := 0
	for target in level["score_targets"]:
		if score >= int(target):
			stars += 1
	return stars


func next_level_id(level_id: String) -> String:
	var index := _level_order.find(level_id)
	if index < 0 or index + 1 >= _level_order.size():
		return ""
	return str(_level_order[index + 1])


func paint_ids() -> Array:
	return _paint_order.duplicate()


func get_paint_style(style_id: String) -> Dictionary:
	if not _paint.has(style_id):
		return {}
	return (_paint[style_id] as Dictionary).duplicate(true)


func has_paint_style(style_id: String) -> bool:
	return _paint.has(style_id)


func default_paint(car_id: String) -> Dictionary:
	var car := get_car(car_id)
	var colors: Dictionary = car.get("default_colors", {})
	return {
		"style": PAINT_GLOSS,
		"primary": str(colors.get("primary", "#e8e8ea")),
		"secondary": str(colors.get("secondary", "#14141a")),
		"accent": str(colors.get("accent", "#ff2d8a")),
	}


func difficulty_ids() -> Array:
	return _difficulty_order.duplicate()


func get_difficulty(difficulty_id: String) -> Dictionary:
	if not _difficulties.has(difficulty_id):
		return {}
	return (_difficulties[difficulty_id] as Dictionary).duplicate(true)


func has_difficulty(difficulty_id: String) -> bool:
	return _difficulties.has(difficulty_id)


func has_graphics_quality(quality: String) -> bool:
	return GRAPHICS_QUALITIES.has(quality)


func resolve_track_profile(style_or_level: String) -> Dictionary:
	if has_level(style_or_level):
		var level := get_level(style_or_level)
		var chapter := get_chapter(str(level["chapter_id"]))
		return {
			"style": str(level["style"]),
			"level_id": style_or_level,
			"chapter_id": str(level["chapter_id"]),
			"weather": str(level["weather"]),
			"bpm": float(level["bpm"]),
			"duration_sec": float(level["length_sec"]),
			"display_name": str(level["name"]),
			"source": "campaign",
		}
	for chapter_id in _chapter_order:
		var chapter: Dictionary = _chapters[chapter_id]
		if chapter_id == style_or_level or str(chapter["style"]) == style_or_level:
			return {
				"style": str(chapter["style"]),
				"level_id": "",
				"chapter_id": chapter_id,
				"weather": str(chapter["weather"]),
				"bpm": float(chapter["bpm_min"] + chapter["bpm_max"]) * 0.5,
				"duration_sec": float(chapter["duration_sec"]),
				"display_name": str(chapter["name"]),
				"source": "campaign",
			}
	return {}


func _build_cars() -> void:
	_add_car(CAR_STREET_86, "Street 86", 0, 0, true, {
		"speed": 68, "accel": 70, "drift": 62, "grip": 58, "weight": 100,
	}, {"primary": "#e6e6ea", "secondary": "#16161c", "accent": "#ff2d8a"})
	_add_car(CAR_SILVIA, "Silvia S-Spec", 6, 8000, false, {
		"speed": 72, "accel": 74, "drift": 84, "grip": 48, "weight": 96,
	}, {"primary": "#f2f4f7", "secondary": "#1b2430", "accent": "#3de1ff"})
	_add_car(CAR_GTR, "GT-R Skyline", 16, 24000, false, {
		"speed": 84, "accel": 80, "drift": 66, "grip": 74, "weight": 124,
	}, {"primary": "#d6d8df", "secondary": "#101820", "accent": "#ffc857"})
	_add_car(CAR_HYPERION, "Apex Hyperion", 32, 60000, false, {
		"speed": 94, "accel": 90, "drift": 88, "grip": 60, "weight": 90,
	}, {"primary": "#f7f2ff", "secondary": "#140818", "accent": "#ff2d8a"})


func _add_car(car_id: String, display_name: String, unlock_stars: int, price_cr: int, owned_by_default: bool, stats: Dictionary, colors: Dictionary) -> void:
	_car_order.append(car_id)
	_cars[car_id] = {
		"id": car_id,
		"name": display_name,
		"unlock_stars": unlock_stars,
		"price_cr": price_cr,
		"owned_by_default": owned_by_default,
		"stats": stats,
		"default_colors": colors,
	}


func _build_upgrades() -> void:
	_add_upgrade(UPGRADE_DRIFT_ANGLE, "Drift Angle", 350, "Wider slip angle and a bigger score multiplier.", {
		"angle_deg": 4.0,
		"score_mult": 0.05,
	})
	_add_upgrade(UPGRADE_TURBO, "Turbo Boost", 450, "More speed and a longer beat-boost.", {
		"speed_mult": 0.04,
		"boost_sec": 0.2,
	})
	_add_upgrade(UPGRADE_ARMOR, "Armor", 400, "Extra wall hits before the run ends.", {
		"extra_hits": 1.0,
		"wall_durability": 0.1,
	})
	_add_upgrade(UPGRADE_MAGNET, "Magnet", 500, "Snaps the car toward the beat line and pulls CR.", {
		"snap": 0.06,
		"pickup_mult": 0.12,
	})


func _add_upgrade(upgrade_id: String, display_name: String, base_cost: int, blurb: String, per_level: Dictionary) -> void:
	_upgrade_order.append(upgrade_id)
	_upgrades[upgrade_id] = {
		"id": upgrade_id,
		"name": display_name,
		"base_cost": base_cost,
		"max_level": MAX_UPGRADE_LEVEL,
		"blurb": blurb,
		"per_level": per_level,
	}


func _build_perks() -> void:
	_add_perk(PERK_BEAT_WINDOW, "Beat Window", "Widens the perfect-hit timing window.", {"window_ms": 18.0})
	_add_perk(PERK_COMBO, "Combo Keeper", "Forgives misses before a combo breaks.", {"misses_kept": 1.0})
	_add_perk(PERK_CASH, "Cash Flow", "Pays more CR at the finish line.", {"cr_bonus": 0.08})
	_add_perk(PERK_FOCUS, "Focus Slow-Mo", "Stretches time after a perfect chain.", {"slowmo_sec": 0.35}, {"time_scale": 0.65})


func _add_perk(perk_id: String, display_name: String, blurb: String, per_level: Dictionary, constants: Dictionary = {}) -> void:
	_perk_order.append(perk_id)
	_perks[perk_id] = {
		"id": perk_id,
		"name": display_name,
		"max_level": MAX_PERK_LEVEL,
		"point_cost": 1,
		"blurb": blurb,
		"per_level": per_level,
		"constants": constants,
	}


func _build_ranks() -> void:
	# Thresholds stay early so a save earned under the old cap keeps its rank.
	# Apex Legend then runs from 20 through MAX_PILOT_LEVEL.
	_ranks = [
		{"id": RANK_NOVICE, "name": "Novice", "min_level": 1},
		{"id": RANK_STREET, "name": "Street Racer", "min_level": 5},
		{"id": RANK_TOUGE, "name": "Touge King", "min_level": 12},
		{"id": RANK_APEX, "name": "Apex Legend", "min_level": 20},
	]


func _build_chapters_and_levels() -> void:
	_add_chapter("haruna", "Haruna", "Dry Night", 115, 125, "dry_night", STYLE_HARUNA, 92, {
		"sky": "#140818", "road": "#1a1024", "neon": "#ff2d8a",
	})
	_add_chapter("shuto", "Shuto", "Rain", 130, 140, "rain", STYLE_SHUTO, 98, {
		"sky": "#071018", "road": "#101820", "neon": "#3de1ff",
	})
	_add_chapter("docklands", "Docklands", "Fog", 145, 155, "fog", STYLE_DOCKLANDS, 104, {
		"sky": "#121410", "road": "#1a1c18", "neon": "#d6ff6b",
	})
	_add_chapter("apex", "Apex", "Storm", 160, 175, "storm", STYLE_APEX, 112, {
		"sky": "#12060e", "road": "#1c0c14", "neon": "#ffc857",
	})
	_add_level("haruna_01", "haruna", "Touge Gate", 115, 0, [5000, 12000, 20000], 84, 250, 80)
	_add_level("haruna_02", "haruna", "Cedar Switchbacks", 118, 1, [7000, 15000, 25000], 86, 300, 90)
	_add_level("haruna_03", "haruna", "Hairpin Shrine", 122, 2, [9000, 18000, 30000], 88, 360, 100)
	_add_level("haruna_04", "haruna", "Summit Night", 125, 4, [11000, 22000, 36000], 92, 430, 120)
	_add_level("shuto_01", "shuto", "Elevated Entry", 130, 6, [14000, 26000, 42000], 90, 520, 140)
	_add_level("shuto_02", "shuto", "Neon Runoff", 133, 8, [16000, 30000, 48000], 92, 600, 160)
	_add_level("shuto_03", "shuto", "Rain Wangan", 137, 11, [19000, 35000, 55000], 96, 700, 180)
	_add_level("shuto_04", "shuto", "Tollgate Drift", 140, 14, [22000, 40000, 64000], 100, 820, 200)
	_add_level("docklands_01", "docklands", "Pier Lights", 145, 16, [26000, 46000, 72000], 96, 960, 230)
	_add_level("docklands_02", "docklands", "Container Alleys", 148, 19, [30000, 52000, 82000], 100, 1100, 260)
	_add_level("docklands_03", "docklands", "Fog Cut", 152, 22, [34000, 60000, 94000], 104, 1260, 290)
	_add_level("docklands_04", "docklands", "Harbor Crown", 155, 25, [39000, 68000, 108000], 108, 1440, 320)
	_add_level("apex_01", "apex", "Storm Rise", 160, 28, [45000, 78000, 120000], 104, 1700, 360)
	_add_level("apex_02", "apex", "Thunder Esses", 165, 32, [52000, 90000, 140000], 108, 2000, 420)
	_add_level("apex_03", "apex", "Lightning Gate", 170, 35, [60000, 104000, 162000], 112, 2400, 480)
	_add_level("apex_04", "apex", "Apex Line", 175, 39, [70000, 120000, 190000], 120, 3000, 560)


func _add_chapter(chapter_id: String, display_name: String, subtitle: String, bpm_min: int, bpm_max: int, weather: String, style: String, duration_sec: int, palette: Dictionary) -> void:
	_chapter_order.append(chapter_id)
	_chapters[chapter_id] = {
		"id": chapter_id,
		"name": display_name,
		"subtitle": subtitle,
		"order": _chapter_order.size(),
		"bpm_min": bpm_min,
		"bpm_max": bpm_max,
		"weather": weather,
		"style": style,
		"duration_sec": duration_sec,
		"palette": palette,
	}


func _add_level(level_id: String, chapter_id: String, display_name: String, bpm: int, unlock_stars: int, score_targets: Array, length_sec: int, reward_cr: int, reward_xp: int) -> void:
	var chapter: Dictionary = _chapters[chapter_id]
	var index := 1
	for existing_id in _level_order:
		if (_levels[existing_id] as Dictionary)["chapter_id"] == chapter_id:
			index += 1
	_level_order.append(level_id)
	_levels[level_id] = {
		"id": level_id,
		"chapter_id": chapter_id,
		"chapter_name": str(chapter["name"]),
		"index": index,
		"name": display_name,
		"bpm": bpm,
		"weather": str(chapter["weather"]),
		"style": str(chapter["style"]),
		"unlock_stars": unlock_stars,
		"score_targets": score_targets,
		"length_sec": length_sec,
		"reward_cr": reward_cr,
		"reward_xp": reward_xp,
	}


func _build_paint() -> void:
	_add_paint(PAINT_GLOSS, "Gloss", 0, 0.05, 0.28, 0.35, false)
	_add_paint(PAINT_METALLIC, "Metallic", 2000, 0.95, 0.22, 0.7, false)
	_add_paint(PAINT_CHAMELEON, "Chameleon", 5000, 0.65, 0.15, 1.0, true)


func _add_paint(style_id: String, display_name: String, price_cr: int, metalness: float, roughness: float, clearcoat: float, color_shift: bool) -> void:
	_paint_order.append(style_id)
	_paint[style_id] = {
		"id": style_id,
		"name": display_name,
		"price_cr": price_cr,
		"metalness": metalness,
		"roughness": roughness,
		"clearcoat": clearcoat,
		"color_shift": color_shift,
	}


func _build_difficulties() -> void:
	_add_difficulty(DIFF_CHILL, "Chill", 1.4, 0.88, 0.85, 0.9, 1, false)
	_add_difficulty(DIFF_DRIVE, "Drive", 1.0, 1.0, 1.0, 1.0, 0, false)
	_add_difficulty(DIFF_HARDCORE, "Hardcore", 0.7, 1.1, 1.3, 1.2, 0, true)


func _add_difficulty(difficulty_id: String, display_name: String, window_scale: float, speed_scale: float, score_scale: float, cr_scale: float, extra_armor: int, combo_keeper_disabled: bool) -> void:
	_difficulty_order.append(difficulty_id)
	_difficulties[difficulty_id] = {
		"id": difficulty_id,
		"name": display_name,
		"window_scale": window_scale,
		"speed_scale": speed_scale,
		"score_scale": score_scale,
		"cr_scale": cr_scale,
		"extra_armor": extra_armor,
		"combo_keeper_disabled": combo_keeper_disabled,
	}
