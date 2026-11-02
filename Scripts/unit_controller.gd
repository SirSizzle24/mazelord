extends Node2D
## Outside dig mode: tap the unit to select it, then tap a tile to send it there.

const TAP_DISTANCE := 10.0  # a touch that moves less than this many pixels is a tap, not a pan

@export var grid: Node2D
@export var unit: Node2D
@export var dig_controller: Node2D

var press_position := Vector2.ZERO
var fingers_down := 0
var tap_possible := false  # false once a touch turns into a pan or a pinch


func _unhandled_input(event: InputEvent) -> void:
	if dig_controller.dig_mode:
		return
	if not (event is InputEventScreenTouch):
		return

	if event.pressed:
		fingers_down += 1
		tap_possible = fingers_down == 1  # a second finger means a pinch, so no tap
		press_position = event.position
		return

	# A finger lifted.
	fingers_down = max(fingers_down - 1, 0)
	if not tap_possible:
		return
	tap_possible = false
	if event.position.distance_to(press_position) > TAP_DISTANCE:
		return  # the finger moved: that was a pan

	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var tapped: Vector2i = grid.screen_to_tile(grid.to_local(world_position))

	if tapped == unit.tile:
		unit.set_selected(not unit.selected)  # tap the unit again to deselect
	elif unit.selected:
		unit.move_to(tapped)  # does nothing if there's no path
