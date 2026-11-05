extends Node2D
## Outside dig, build and remove modes:
## - Troops in no flight: tap one to select it, then tap a tile to send it there, or tap a marked
##   tile or a blueprint to set a worker working.
## - Flights: tap any member (or a flight button) to select the whole flight, toggle element buttons
##   to pick which elements move (none or all pressed = the whole flight), then tap a destination.

const TapDetector = preload("res://scripts/tap_detector.gd")
const TAP_SLACK := 10.0  # extra pixels around a unit that still count as tapping it
const MAX_FLIGHTS := 5
const ELEMENTS_PER_FLIGHT := 4
const SPREAD := 34.0  # pixels between flight members around a destination, so they don't pile up

@export var grid: Node2D
@export var dig_controller: Node2D
@export var build_controller: Node2D
@export var fog: Node2D
@export var flight_bar: Container    # buttons F1 to F5, the backup way to select a flight
@export var element_bar: Container   # toggle buttons 1 to 4, shown while a flight is selected
@export var roster: Node  # the troop cards; a long press on a troop opens its card

var selected: Node2D = null  # the selected troop in no flight, or null
var selected_flight := 0  # the selected flight, or 0 for none
var element_buttons: Array[Button] = []
var taps := TapDetector.new()


func _ready() -> void:
	for n in range(1, MAX_FLIGHTS + 1):
		var button := Button.new()
		button.text = "F%d" % n
		button.pressed.connect(_on_flight_button.bind(n))
		flight_bar.add_child(button)
	for n in range(1, ELEMENTS_PER_FLIGHT + 1):
		var button := Button.new()
		button.text = str(n)
		button.toggle_mode = true
		element_bar.add_child(button)
		element_buttons.append(button)
	element_bar.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if dig_controller.dig_mode or build_controller.build_mode or build_controller.remove_mode:
		return
	if not taps.is_tap(event):
		return

	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var tapped_unit := _unit_at(world_position)

	if tapped_unit != null and taps.was_long_press:
		roster.open_for(tapped_unit)
		return
	if tapped_unit != null:
		if tapped_unit.flight > 0:
			# Tapping a flight member selects (or deselects) its whole flight.
			_select_flight(0 if tapped_unit.flight == selected_flight else tapped_unit.flight)
		elif tapped_unit == selected:
			_select(null)  # tap the selected troop again to deselect
		else:
			_select(tapped_unit)
		return

	var tapped: Vector2i = grid.screen_to_tile(grid.to_local(world_position))
	if not fog.is_known(tapped):
		return  # moving into the unknown would give away whether it's open

	if selected_flight > 0:
		_move_flight(grid.tile_to_screen(tapped))
		return
	if selected == null:
		return
	if grid.is_marked(tapped) or not grid.blueprint_at(tapped).is_empty():
		selected.start_working(tapped)  # ignored by units that can't work
	else:
		selected.move_to(tapped)  # does nothing if there's no path


func _on_flight_button(flight: int) -> void:
	_select_flight(0 if flight == selected_flight else flight)


## Sends the chosen elements of the selected flight to a point, spread in a small circle around it.
func _move_flight(destination: Vector2) -> void:
	var chosen: Array[int] = []
	for n in element_buttons.size():
		if element_buttons[n].button_pressed:
			chosen.append(n + 1)
	var whole_flight := chosen.is_empty() or chosen.size() == ELEMENTS_PER_FLIGHT

	var movers: Array = []
	for unit in _flight_members(selected_flight):
		if whole_flight or chosen.has(unit.element):
			movers.append(unit)
	for i in movers.size():
		var offset := Vector2.ZERO
		if movers.size() > 1:
			offset = Vector2.from_angle(TAU * i / movers.size()) * SPREAD
		movers[i].move_to_point(destination + offset)


func _flight_members(flight: int) -> Array:
	var members: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.flight == flight:
			members.append(unit)
	return members


## The unit under a world position, or null if there isn't one.
func _unit_at(world_position: Vector2) -> Node2D:
	for unit in get_tree().get_nodes_in_group("units"):
		if world_position.distance_to(unit.global_position) <= unit.radius + TAP_SLACK:
			return unit
	return null


func _select(unit: Node2D) -> void:
	_select_flight(0)
	if selected != null:
		selected.set_selected(false)
	selected = unit
	if selected != null:
		selected.set_selected(true)


## Selects a whole flight (0 for none) and shows the element buttons, all unpressed.
func _select_flight(flight: int) -> void:
	if selected != null and flight > 0:
		selected.set_selected(false)
		selected = null
	for unit in _flight_members(selected_flight):
		unit.set_selected(false)
	selected_flight = flight
	for unit in _flight_members(selected_flight):
		unit.set_selected(true)
	for button in element_buttons:
		button.button_pressed = false
	element_bar.visible = flight > 0
