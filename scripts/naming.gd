extends PanelContainer
## Asks the player to name a troop that has earned one: a suggested name in an editable box.
## Several troops can earn names at once; they wait in a queue and are named one at a time.
## After naming, the announcement shows and the troop's card opens.

const ANNOUNCE_TIME := 5.0

@export var dungeon: Node
@export var roster: Node
@export var announcement: Label

var queue: Array = []
var current: Node2D = null
var announce_left := 0.0
var prompt: Label
var name_box: LineEdit


func _ready() -> void:
	visible = false
	announcement.visible = false
	var column := VBoxContainer.new()
	add_child(column)
	prompt = Label.new()
	column.add_child(prompt)
	name_box = LineEdit.new()
	name_box.custom_minimum_size = Vector2(260, 0)
	name_box.text_submitted.connect(func(_text): _confirm())  # pressing Enter works too
	column.add_child(name_box)
	var ok := Button.new()
	ok.text = "OK"
	ok.pressed.connect(_confirm)
	column.add_child(ok)
	dungeon.name_earned.connect(_on_name_earned)


func _on_name_earned(unit: Node2D) -> void:
	queue.append(unit)
	if current == null:
		_ask_next()


func _ask_next() -> void:
	current = null
	while not queue.is_empty():
		var unit: Node2D = queue.pop_front()
		if is_instance_valid(unit) and not unit.is_named:  # it may have died while waiting
			current = unit
			break
	visible = current != null
	if visible:
		move_to_front()  # over the roster, if it's open
		announcement.move_to_front()
	if current != null:
		prompt.text = "A %s has earned a name!" % current.roster_label
		name_box.text = dungeon.suggest_name()
		name_box.grab_focus()


func _confirm() -> void:
	if current == null:
		return
	var chosen := name_box.text.strip_edges()
	if chosen == "":
		chosen = dungeon.suggest_name()
	var old_label: String = current.roster_label
	current.give_name(chosen)
	announcement.text = "A %s is now known as %s." % [old_label, chosen]
	announcement.visible = true
	announce_left = ANNOUNCE_TIME
	roster.open_for(current)
	_ask_next()


func _process(delta: float) -> void:
	if announce_left > 0.0:
		announce_left -= delta
		if announce_left <= 0.0:
			announcement.visible = false
