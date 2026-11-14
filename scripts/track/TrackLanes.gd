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
