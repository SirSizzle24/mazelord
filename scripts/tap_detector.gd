extends RefCounted
## Tells taps apart from pans and pinches. Feed it every touch event; it says when one completes a tap.
## Shared by every controller that responds to taps, so the rules live in one place.

const TAP_DISTANCE := 10.0  # a touch that moves less than this many pixels is a tap, not a pan

var fingers: Dictionary = {}  # finger index -> true while that finger is down
var press_position := Vector2.ZERO
var tap_possible := false  # false once a touch turns into a pinch


## True if this event is a finger lifting at the end of a tap.
func is_tap(event: InputEvent) -> bool:
	if not (event is InputEventScreenTouch):
		return false

	if event.pressed:
		# Stored by finger number: if a release was ever missed (a dropdown can swallow one),
		# the same finger pressing again overwrites its old entry instead of piling up.
		fingers[event.index] = true
		tap_possible = fingers.size() == 1  # a second finger means a pinch, so no tap
		press_position = event.position
		return false

	fingers.erase(event.index)
	if not tap_possible:
		return false
	tap_possible = false
	return event.position.distance_to(press_position) <= TAP_DISTANCE  # moved too far: it was a pan
