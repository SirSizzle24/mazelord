extends PanelContainer
## Troop cards, like baseball cards: picture, name, type, stats, status, fame and traits.
## The main view shows flightless fighters, with five flight slots to drag cards onto, and the workers
## below (workers can't join flights). Tap a flight slot to open that flight's deck, with four element
## slots and a "Remove from flight" slot. Long-press a troop on the map to open its card.

const MAX_FLIGHTS := 5
const ELEMENTS_PER_FLIGHT := 4
const REFRESH_TIME := 0.5  # seconds between updates of the cards' text while open

@export var dungeon: Node
@export var roster_button: Button

var view_flight := 0  # 0 for the main view, 1 to 5 for that flight's deck
var highlighted: Node2D = null  # the troop whose card was opened by long press
var refresh_left := 0.0

var header: Label
var back_button: Button
var slot_row: HBoxContainer
var card_grid: GridContainer
var workers_title: Label
var worker_grid: GridContainer


func _ready() -> void:
	visible = false
	_build_layout()
	roster_button.toggled.connect(_on_roster_toggled)
	dungeon.troop_summoned.connect(func(_unit): _rebuild())


## Everything inside the panel is made in code, so the layout lives in one readable place.
func _build_layout() -> void:
	var column := VBoxContainer.new()
	add_child(column)

	var top := HBoxContainer.new()
	back_button = Button.new()
	back_button.text = "< Back"
	back_button.pressed.connect(func(): open_flight(0))
	top.add_child(back_button)
	header = Label.new()
	top.add_child(header)
	column.add_child(top)

	slot_row = HBoxContainer.new()
	column.add_child(slot_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	card_grid = GridContainer.new()
	card_grid.columns = 3
	list.add_child(card_grid)
	workers_title = Label.new()
	workers_title.text = "Workers (can't join flights)"
	list.add_child(workers_title)
	worker_grid = GridContainer.new()
	worker_grid.columns = 3
	list.add_child(worker_grid)


func _on_roster_toggled(toggled_on: bool) -> void:
	visible = toggled_on
	if toggled_on:
		_rebuild()
	else:
		highlighted = null


## Opens the deck holding this troop, with its card highlighted.
func open_for(unit: Node2D) -> void:
	highlighted = unit
	view_flight = unit.flight
	if roster_button.button_pressed:
		_rebuild()
	else:
		roster_button.button_pressed = true  # opening runs _rebuild


func open_flight(flight: int) -> void:
	view_flight = flight
	_rebuild()


func _process(delta: float) -> void:
	if not visible:
		return
	# Refresh the cards' text (health, status...) without rebuilding, so a drag in progress isn't disturbed.
	refresh_left -= delta
	if refresh_left <= 0.0:
		refresh_left = REFRESH_TIME
		for grid in [card_grid, worker_grid]:
			for card in grid.get_children():
				card.refresh()


## Clears and remakes the slots and cards for the current view.
func _rebuild() -> void:
	for container in [slot_row, card_grid, worker_grid]:
		for child in container.get_children():
			child.queue_free()
	var troops: Array = get_tree().get_nodes_in_group("units")

	if view_flight == 0:
		header.text = "  Troops: drag a fighter onto a flight, or tap a flight to open it"
		back_button.visible = false
		for n in range(1, MAX_FLIGHTS + 1):
			var members := troops.filter(func(unit): return unit.flight == n).size()
			slot_row.add_child(Slot.new(self, "flight", n, "Flight %d\n%d troops" % [n, members]))
		for unit in troops:
			if unit.can_dig:
				worker_grid.add_child(Card.new(unit, false, unit == highlighted))
			elif unit.flight == 0:
				card_grid.add_child(Card.new(unit, true, unit == highlighted))
		workers_title.visible = true
	else:
		header.text = "  Flight %d: drag a card onto an element" % view_flight
		back_button.visible = true
		var members := troops.filter(func(unit): return unit.flight == view_flight)
		members.sort_custom(func(a, b): return a.element < b.element)
		for n in range(1, ELEMENTS_PER_FLIGHT + 1):
			var count := members.filter(func(unit): return unit.element == n).size()
			slot_row.add_child(Slot.new(self, "element", n, "Element %d\n%d troops" % [n, count]))
		slot_row.add_child(Slot.new(self, "remove", 0, "Remove from\nflight"))
		for unit in members:
			card_grid.add_child(Card.new(unit, true, unit == highlighted))
		workers_title.visible = false


## A card was dropped on a slot.
func card_dropped(kind: String, number: int, unit: Node2D) -> void:
	match kind:
		"flight":
			unit.set_flight(number, 1)
		"element":
			unit.set_flight(view_flight, number)
		"remove":
			unit.set_flight(0, 1)
	_rebuild()


## One troop's card. Inner classes like this live inside another script; this one is only used here.
class Card extends PanelContainer:
	var unit: Node2D
	var draggable: bool
	var text: Label

	func _init(for_unit: Node2D, can_drag: bool, highlight: bool) -> void:
		unit = for_unit
		draggable = can_drag
		custom_minimum_size = Vector2(300, 120)
		if highlight:
			modulate = Color(1.0, 1.0, 0.6)  # tinted yellow
		var row := HBoxContainer.new()
		add_child(row)
		var picture := ColorRect.new()  # a placeholder until there's art
		picture.color = unit.color
		picture.custom_minimum_size = Vector2(70, 100)
		row.add_child(picture)
		text = Label.new()
		row.add_child(text)
		refresh()

	func refresh() -> void:
		if not is_instance_valid(unit):
			text.text = "(gone)"
			return
		text.text = "%s\n%s\nHP %d/%d  DMG %d  RNG %d  %.1fs\n%s\nFame: -    Traits: -" % [
			unit.roster_label, dungeon_type_name(), int(unit.health), int(unit.max_health), int(unit.damage),
			int(unit.attack_range), unit.attack_interval, unit.status_text()]

	func dungeon_type_name() -> String:
		return unit.type_id.capitalize()

	# Godot's drag and drop: returning data here starts a drag; a Slot underneath can accept it.
	func _get_drag_data(_at_position: Vector2) -> Variant:
		if not draggable or not is_instance_valid(unit):
			return null
		var preview := Label.new()
		preview.text = unit.roster_label
		set_drag_preview(preview)
		return {"unit": unit}


## A drop target: a flight (main view), an element (flight view), or "remove from flight".
class Slot extends PanelContainer:
	var roster: Node
	var kind: String
	var number: int

	func _init(owner_roster: Node, slot_kind: String, slot_number: int, caption: String) -> void:
		roster = owner_roster
		kind = slot_kind
		number = slot_number
		custom_minimum_size = Vector2(150, 64)
		var label := Label.new()
		label.text = caption
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("unit") and is_instance_valid(data["unit"]) \
			and not data["unit"].can_dig  # workers can't join flights

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		roster.card_dropped(kind, number, data["unit"])

	func _gui_input(event: InputEvent) -> void:
		# Tapping a flight slot opens that flight's deck.
		if kind == "flight" and event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			roster.open_flight(number)
