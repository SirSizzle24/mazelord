extends PanelContainer
## The roster: every troop, with buttons to set its flight and element. Each button cycles through
## its values when tapped (buttons instead of dropdowns, which swallowed taps before).

const MAX_FLIGHTS := 5
const ELEMENTS_PER_FLIGHT := 4

@export var dungeon: Node
@export var roster_button: Button

@onready var rows: VBoxContainer = $Scroll/Rows


func _ready() -> void:
	visible = false
	roster_button.toggled.connect(_on_roster_toggled)
	dungeon.troop_summoned.connect(func(_unit): _rebuild())


func _on_roster_toggled(toggled_on: bool) -> void:
	visible = toggled_on
	if toggled_on:
		_rebuild()


## Throws away the rows and makes one per troop. Simple, and the roster is small.
func _rebuild() -> void:
	for row in rows.get_children():
		row.queue_free()
	for unit in get_tree().get_nodes_in_group("units"):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = unit.roster_label
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)

		var flight_button := Button.new()
		flight_button.custom_minimum_size = Vector2(110, 0)
		var element_button := Button.new()
		element_button.custom_minimum_size = Vector2(110, 0)
		flight_button.pressed.connect(_cycle_flight.bind(unit, flight_button, element_button))
		element_button.pressed.connect(_cycle_element.bind(unit, flight_button, element_button))
		row.add_child(flight_button)
		row.add_child(element_button)
		_show(unit, flight_button, element_button)
		rows.add_child(row)


func _cycle_flight(unit: Node2D, flight_button: Button, element_button: Button) -> void:
	unit.set_flight((unit.flight + 1) % (MAX_FLIGHTS + 1), unit.element)  # none, 1, 2 ... 5, none
	_show(unit, flight_button, element_button)


func _cycle_element(unit: Node2D, flight_button: Button, element_button: Button) -> void:
	unit.set_flight(unit.flight, unit.element % ELEMENTS_PER_FLIGHT + 1)  # 1, 2, 3, 4, 1
	_show(unit, flight_button, element_button)


func _show(unit: Node2D, flight_button: Button, element_button: Button) -> void:
	flight_button.text = "No flight" if unit.flight == 0 else "Flight %d" % unit.flight
	element_button.text = "Element %d" % unit.element
	element_button.disabled = unit.flight == 0  # elements only mean something inside a flight
