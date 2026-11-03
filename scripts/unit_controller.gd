extends Node2D
## Outside dig mode: tap a unit to select it, then tap a tile to send it there,
## or tap a marked tile to set a worker digging.

const TapDetector = preload("res://scripts/tap_detector.gd")
const TAP_SLACK := 10.0  # extra pixels around a unit that still count as tapping it

@export var grid: Node2D
@export var dig_controller: Node2D
@export var build_controller: Node2D

var selected: Node2D = null  # the selected unit, or null for none
var taps := TapDetector.new()


func _unhandled_input(event: InputEvent) -> void:
	if dig_controller.dig_mode or build_controller.build_mode:
		return
	if not taps.is_tap(event):
		return

	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var tapped_unit := _unit_at(world_position)

	if tapped_unit != null:
		if tapped_unit == selected:
			_select(null)  # tap the selected unit again to deselect
		else:
			_select(tapped_unit)
		return
	if selected == null:
		return

	var tapped: Vector2i = grid.screen_to_tile(grid.to_local(world_position))
	if grid.is_marked(tapped):
		selected.start_digging(tapped)  # ignored by units that can't dig
	else:
		selected.move_to(tapped)  # does nothing if there's no path


## The unit under a world position, or null if there isn't one.
func _unit_at(world_position: Vector2) -> Node2D:
	for unit in get_tree().get_nodes_in_group("units"):
		if world_position.distance_to(unit.global_position) <= unit.RADIUS + TAP_SLACK:
			return unit
	return null


func _select(unit: Node2D) -> void:
	if selected != null:
		selected.set_selected(false)
	selected = unit
	if selected != null:
		selected.set_selected(true)
