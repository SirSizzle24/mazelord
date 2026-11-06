extends PanelContainer
## Troop cards, like a trading card game: name banner, picture, type and size, stats, status, assignment
## and fame. Tap a card to see it large, with the troop's history. The main view shows flightless
## fighters, with five flight slots to drag cards onto, and the workers below (workers can't join
## flights). Tap a flight slot to open that flight's deck, with four element slots and a "Remove from
## flight" slot. Long-press a troop on the map to open its card.

const MAX_FLIGHTS := 5
const ELEMENTS_PER_FLIGHT := 4
const REFRESH_TIME := 0.5  # seconds between updates of the cards' text while open
const CARD_COLUMNS := 5

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
var detail_layer: PanelContainer  # covers the roster while one card is shown large
var detail_holder: VBoxContainer
var detail_card: Card = null


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
	card_grid.columns = CARD_COLUMNS
	list.add_child(card_grid)
	workers_title = Label.new()
	workers_title.text = "Workers (can't join flights)"
	list.add_child(workers_title)
	worker_grid = GridContainer.new()
	worker_grid.columns = CARD_COLUMNS
	list.add_child(worker_grid)

	# The large card, over everything else. A PanelContainer's children all fill it, so this one
	# covers the list; its dim background also stops taps reaching the cards underneath.
	detail_layer = PanelContainer.new()
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	detail_layer.add_theme_stylebox_override("panel", dim)
	detail_layer.visible = false
	add_child(detail_layer)
	var center := CenterContainer.new()
	detail_layer.add_child(center)
	detail_holder = VBoxContainer.new()
	center.add_child(detail_holder)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(close_detail)
	detail_holder.add_child(close)


## Shows one troop's card large, with its history.
func show_detail(unit: Node2D) -> void:
	close_detail()
	detail_card = Card.new(self, unit, false, false, true)
	detail_holder.add_child(detail_card)
	detail_holder.move_child(detail_card, 0)  # above the Close button
	detail_layer.visible = true


func close_detail() -> void:
	if detail_card != null:
		detail_card.queue_free()
		detail_card = null
	detail_layer.visible = false


func _on_roster_toggled(toggled_on: bool) -> void:
	visible = toggled_on
	if toggled_on:
		_rebuild()
	else:
		highlighted = null
		close_detail()


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
		if detail_card != null:
			detail_card.refresh()


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
				worker_grid.add_child(Card.new(self, unit, false, unit == highlighted))
			elif unit.flight == 0:
				card_grid.add_child(Card.new(self, unit, true, unit == highlighted))
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
			card_grid.add_child(Card.new(self, unit, true, unit == highlighted))
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
## Small in the lists; large (with history) when tapped.
class Card extends PanelContainer:
	const SMALL_SIZE := Vector2(200, 290)  # about a playing card's 5:7
	const LARGE_SIZE := Vector2(340, 560)
	const TAP_DISTANCE := 12.0  # a press that moves less than this before release is a tap, not a drag

	var roster: Node
	var unit: Node2D
	var draggable: bool
	var large: bool
	var press_at := Vector2.INF  # where a press started, to tell taps from drags
	var frame: StyleBoxFlat
	var name_label: Label
	var type_label: Label
	var stats_label: Label
	var status_label: Label
	var fame_bar: ProgressBar
	var fame_label: Label
	var history_label: Label

	func _init(owner_roster: Node, for_unit: Node2D, can_drag: bool, highlight: bool, is_large := false) -> void:
		roster = owner_roster
		unit = for_unit
		draggable = can_drag
		large = is_large
		custom_minimum_size = LARGE_SIZE if large else SMALL_SIZE
		if highlight:
			modulate = Color(1.0, 1.0, 0.6)  # tinted yellow
		frame = StyleBoxFlat.new()
		frame.bg_color = Color(0.16, 0.13, 0.11)
		frame.set_border_width_all(3)
		frame.set_corner_radius_all(10)
		frame.set_content_margin_all(8)
		add_theme_stylebox_override("panel", frame)

		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE  # taps and drags go to the card itself
		add_child(column)
		name_label = _label(column, 22 if large else 16)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var picture := ColorRect.new()  # a placeholder until there's art
		picture.color = unit.color
		picture.custom_minimum_size = Vector2(0, 200 if large else 110)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(picture)
		type_label = _label(column, 15 if large else 12)
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_label = _label(column, 15 if large else 12)
		status_label = _label(column, 15 if large else 12)
		fame_bar = ProgressBar.new()
		fame_bar.show_percentage = false
		fame_bar.custom_minimum_size = Vector2(0, 8)
		fame_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(fame_bar)
		fame_label = _label(column, 12)
		if large:
			history_label = _label(column, 15)
		refresh()

	func _label(column: VBoxContainer, font_size: int) -> Label:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", font_size)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
		return label

	func refresh() -> void:
		if not is_instance_valid(unit):
			name_label.text = "(gone)"
			return
		# Named troops get a gold frame; the rest take their troop color.
		frame.border_color = Color(0.92, 0.76, 0.30) if unit.is_named else unit.color.darkened(0.3)
		name_label.text = unit.roster_label
		type_label.text = "%s  ·  %s" % [unit.type_id.capitalize(), unit.size.capitalize()]
		stats_label.text = "HP %d/%d   DMG %d\nRange %d   %.1fs per hit" % [int(unit.health),
			int(unit.max_health), int(unit.damage), int(unit.attack_range), unit.attack_interval]
		var assignment := "Flight %d · Element %d" % [unit.flight, unit.element] if unit.flight > 0 \
			else ("Worker" if unit.can_dig else "No flight")
		status_label.text = "%s\n%s" % [unit.status_text(), assignment]
		if unit.is_named:
			fame_bar.max_value = 1.0
			fame_bar.value = 1.0
			fame_label.text = "Fame %d · Named" % int(unit.fame)
		else:
			fame_bar.max_value = unit.dungeon.name_threshold()
			fame_bar.value = unit.fame
			fame_label.text = "Fame %d / %d" % [int(unit.fame), int(unit.dungeon.name_threshold())]
		if large:
			var h: Dictionary = unit.history
			history_label.text = ("History\nRaids survived: %d\nRaiders downed: %d\n" \
				+ "Injured: %d times, recovered %d\nRescues: %d\nCells dug: %d   Built: %d   Hauled: %d\n" \
				+ "Traits: -") % [h["raids_survived"], h["raiders_downed"], h["times_injured"],
				h["injuries_survived"], h["rescues"], h["cells_dug"], h["builds"], h["hauls"]]

	# A tap (press and release without moving far) opens the large card. A drag is handled below.
	func _gui_input(event: InputEvent) -> void:
		if large or not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			press_at = event.position
		elif press_at != Vector2.INF and event.position.distance_to(press_at) < TAP_DISTANCE:
			press_at = Vector2.INF
			if is_instance_valid(unit):
				roster.show_detail(unit)

	# Godot's drag and drop: returning data here starts a drag; a Slot underneath can accept it.
	func _get_drag_data(_at_position: Vector2) -> Variant:
		press_at = Vector2.INF  # it's a drag, so the release isn't a tap
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
