extends Node

## In-editor rewarded-ad stand-in.
## show_rewarded_ad(callback) always invokes callback(success: bool).
## Revive and x2 reward are the same pipeline with placement-specific payouts.
## Editor and exported builds both resolve after a short delay so gameplay can be tested
## before a real network SDK replaces the body of _resolve_success().

signal ad_started(placement: String)
signal ad_completed(placement: String, rewarded: bool)
signal ad_unavailable(placement: String, reason: String)

const PLACEMENT_GENERIC := "generic"
const PLACEMENT_REVIVE := "revive"
const PLACEMENT_DOUBLE := "x2_reward"

var ads_enabled := true
var simulate_success := true
var editor_delay_sec := 0.65
var export_delay_sec := 0.35

var _busy := false
var _token := 0
var _pending_callback := Callable()
var _pending_placement := ""


func is_busy() -> bool:
	return _busy


func can_show(placement: String = PLACEMENT_GENERIC) -> bool:
	return ads_enabled and not _busy and not placement.is_empty()


func show_rewarded_ad(callback: Callable, placement: String = PLACEMENT_GENERIC) -> bool:
	if not callback.is_valid():
		push_error("AdMonetizationStub.show_rewarded_ad requires a valid callback")
		return false
	var slot := placement if not placement.is_empty() else PLACEMENT_GENERIC
	if not ads_enabled:
		ad_unavailable.emit(slot, "ads_disabled")
		callback.call(false)
		return false
	if _busy:
		ad_unavailable.emit(slot, "ad_busy")
		callback.call(false)
		return false
	_busy = true
	_token += 1
	var token := _token
	_pending_callback = callback
	_pending_placement = slot
	ad_started.emit(slot)
	var tree := get_tree()
	if tree == null:
		_finish(token, false, "no_tree")
		return false
	tree.create_timer(_delay_seconds(), true, true, false).timeout.connect(_finish.bind(token, true, ""), CONNECT_ONE_SHOT)
	return true


func show_revive_ad(callback: Callable) -> bool:
	return show_rewarded_ad(callback, PLACEMENT_REVIVE)


func show_double_reward_ad(base_cr: int, callback: Callable) -> bool:
	if not callback.is_valid():
		push_error("AdMonetizationStub.show_double_reward_ad requires a valid callback")
		return false
	var payout := int(max(base_cr, 0))
	return show_rewarded_ad(func(success: bool) -> void:
		var granted := 0
		if success and payout > 0 and _save_ready():
			SaveManager.add_cr(payout, PLACEMENT_DOUBLE)
			granted = payout
		if callback.is_valid():
			callback.call(success, granted)
	, PLACEMENT_DOUBLE)


func _delay_seconds() -> float:
	if OS.has_feature("editor"):
		return max(editor_delay_sec, 0.0)
	return max(export_delay_sec, 0.0)


func _finish(token: int, reached_end: bool, early_reason: String) -> void:
	if token != _token:
		return
	var callback := _pending_callback
	var placement := _pending_placement
	_pending_callback = Callable()
	_pending_placement = ""
	_busy = false
	var success := reached_end and simulate_success and early_reason.is_empty()
	if not success and not early_reason.is_empty():
		ad_unavailable.emit(placement, early_reason)
	ad_completed.emit(placement, success)
	if callback.is_valid():
		callback.call(success)


func _save_ready() -> bool:
	return get_node_or_null("/root/SaveManager") != null
