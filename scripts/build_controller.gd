extends Node2D
## In build mode, tapping a floor tile places the chosen furnishing as a blueprint.
## Pick the furnishing from the button bar shown in build mode.
## Mana is spent when it's placed; workers will build it in the next step.

const TapDetector = preload("res://scripts/tap_detector.gd")

@export var grid: Node2D
@export var dungeon: Node
@export var build_button: Button
@export var dig_button: Button
@export var item_bar: Container  # holds one button per furnishing

var build_mode := false
var selected_id := ""  # the furnishing that taps will place
var taps := TapDetector.new()


func _ready() -> void:
	# One button per furnishing. The group allows only one to be pressed at a time, like radio buttons.
	var group := ButtonGroup.new()
	for id in dungeon.FURNISHINGS:
		var item: Dictionary = dungeon.FURNISHINGS[id]
		var button := Button.new()
		button.text = "%s (%d)" % [item["name"], item["cost"]]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func(): selected_id = id)  # each button remembers its own id
		item_bar.add_child(button)
		if selected_id == "":  # the first item starts selected
			selected_id = id
			button.button_pressed = true
	item_bar.visible = false

	build_button.toggled.connect(_on_build_toggled)
	dig_button.toggled.connect(_on_dig_toggled)


func _on_build_toggled(toggled_on: bool) -> void:
	build_mode = toggled_on
	item_bar.visible = toggled_on
	if toggled_on:
		dig_button.button_pressed = false  # only one mode at a time


func _on_dig_toggled(toggled_on: bool) -> void:
	if toggled_on:
		build_button.button_pressed = false


func _unhandled_input(event: InputEvent) -> void:
	if not build_mode:
		return
	if not taps.is_tap(event):
		return

	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var tile: Vector2i = grid.screen_to_tile(grid.to_local(world_position))
	var id := selected_id
	var item: Dictionary = dungeon.FURNISHINGS[id]

	if not grid.can_place(tile, item["size"]):
		return  # not all floor, or something's already there
	if not dungeon.try_spend(item["cost"]):
		return  # can't afford it
	grid.place_blueprint(id, tile, item["size"], item["color"])
