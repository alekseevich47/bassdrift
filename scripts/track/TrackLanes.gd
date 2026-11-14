class_name TrackLanes
extends Object

## Drift-cue lanes for a portrait rhythm chart.
## 0 left feint, 1 center beat, 2 right feint, 3 apex hold.

const LEFT := 0
const CENTER := 1
const RIGHT := 2
const APEX := 3
const COUNT := 4

const KIND_TAP := "tap"
const KIND_HOLD := "hold"
const KIND_BOOST := "boost"

const KINDS: Array = [KIND_TAP, KIND_HOLD, KIND_BOOST]


static func is_valid(lane: int) -> bool:
	return lane >= 0 and lane < COUNT


static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


static func name_of(lane: int) -> String:
	match lane:
		LEFT:
			return "left"
		CENTER:
			return "center"
		RIGHT:
			return "right"
		APEX:
			return "apex"
		_:
			return "invalid"


## -1 left, 0 center, +1 right. Apex uses the supplied corner direction.
static func direction_for(lane: int, apex_dir: int = 1) -> int:
	match lane:
		LEFT:
			return -1
		RIGHT:
			return 1
		CENTER:
			return 0
		APEX:
			return 1 if apex_dir >= 0 else -1
		_:
			return 0


static func is_directional(lane: int) -> bool:
	return lane == LEFT or lane == RIGHT or lane == APEX


static func section_name(sections: Array, time_sec: float) -> String:
	var found := "intro"
	for section in sections:
		if typeof(section) != TYPE_DICTIONARY:
			continue
		var start := float((section as Dictionary).get("t", 0.0))
		var dur := float((section as Dictionary).get("dur", 0.0))
		if time_sec >= start and time_sec < start + max(dur, 0.0):
			found = str((section as Dictionary).get("id", found))
	return found


## Radians of heading change before the road generator clamps it to the lane radius.
static func desired_turn(lane: int, section_id: String, dir: int, turn_scale: float = 1.0) -> float:
	var mag := 0.42
	match section_id:
		"intro", "outro":
			mag = 0.30
		"build":
			mag = 0.55
		"drop":
			mag = 0.72
		_:
			mag = 0.42
	match lane:
		CENTER:
			return 0.0
		APEX:
			mag = 2.15 if section_id == "drop" else 1.2
		LEFT, RIGHT:
			if section_id == "drop":
				mag = 0.95
		_:
			return 0.0
	var signed := dir
	if signed == 0:
		signed = -1 if lane == LEFT else 1
	return mag * float(signed) * turn_scale
