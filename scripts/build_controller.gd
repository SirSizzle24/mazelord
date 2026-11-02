extends Node2D
## In build mode, tapping a floor tile places the chosen furnishing as a blueprint.
## Mana is spent when it's placed; workers will build it in the next step.

const TAP_DISTANCE := 10.0  # a touch that moves less than this many pixels is a tap, not a pan

@export var grid: Node2D
@export var dungeon: Node
@export var build_button: Button
@export var dig_button: Button
@export var item_picker: OptionButton

var build_mode := false
var item_ids: Array[String] = []  # the furnishing id for each entry in the picker, in order
var press_position := Vector2.ZERO
var fingers_down := 0
var tap_possible := false


func _ready() -> void:
	for id in dungeon.FURNISHINGS:
		var item: Dictionary = dungeon.FURNISHINGS[id]
		item_picker.add_item("%s (%d)" % [item["name"], item["cost"]])
		item_ids.append(id)
	item_picker.visible = false

	build_button.toggled.connect(_on_build_toggled)
	dig_button.toggled.connect(_on_dig_toggled)


func _on_build_toggled(toggled_on: bool) -> void:
	build_mode = toggled_on
	item_picker.visible = toggled_on
	if toggled_on:
		dig_button.button_pressed = false  # only one mode at a time


func _on_dig_toggled(toggled_on: bool) -> void:
	if toggled_on:
		build_button.button_pressed = false


func _unhandled_input(event: InputEvent) -> void:
	if not build_mode:
		return
	if not (event is InputEventScreenTouch):
		return

	# Same tap-or-pan test as the unit controller.
	if event.pressed:
		fingers_down += 1
		tap_possible = fingers_down == 1
		press_position = event.position
		return
	fingers_down = max(fingers_down - 1, 0)
	if not tap_possible:
		return
	tap_possible = false
	if event.position.distance_to(press_position) > TAP_DISTANCE:
		return

	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var tile: Vector2i = grid.screen_to_tile(grid.to_local(world_position))
	var id := item_ids[item_picker.selected]
	var item: Dictionary = dungeon.FURNISHINGS[id]

	if not grid.can_place(tile, item["size"]):
		return  # not all floor, or something's already there
	if not dungeon.try_spend(item["cost"]):
		return  # can't afford it
	grid.place_blueprint(id, tile, item["size"], item["color"])
