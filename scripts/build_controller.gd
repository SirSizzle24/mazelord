extends Node2D
## Build mode: tap a tile to preview the chosen furnishing there, Rotate to turn it 90 degrees,
## and Place to confirm it as a blueprint (mana is spent on placing). Pick items from the button bar.
## Remove mode: tapping clears a dig mark, cancels a blueprint (full refund),
## or tears down a finished item (half refund).
## Also keeps the Dig, Build and Remove modes exclusive: turning one on turns the others off.

const TapDetector = preload("res://scripts/tap_detector.gd")
const DECONSTRUCT_REFUND := 0.5  # share of the cost returned when tearing down a finished item

@export var grid: Node2D
@export var dungeon: Node
@export var build_button: Button
@export var dig_button: Button
@export var remove_button: Button
@export var rotate_button: Button
@export var place_button: Button
@export var item_bar: Container  # holds one button per furnishing

var build_mode := false
var remove_mode := false
var selected_id := ""  # the furnishing being placed
var preview_tile := Vector2i(-1, -1)  # where the preview sits, or (-1, -1) for no preview
var rotation_steps := 0  # quarter turns, 0 to 3
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
		button.pressed.connect(_select_item.bind(id))  # bind attaches this button's id to the call
		item_bar.add_child(button)
		if selected_id == "":  # the first item starts selected
			selected_id = id
			button.button_pressed = true
	item_bar.visible = false
	rotate_button.visible = false
	place_button.visible = false
	rotate_button.pressed.connect(_on_rotate_pressed)
	place_button.pressed.connect(_on_place_pressed)

	build_button.toggled.connect(_on_build_toggled)
	dig_button.toggled.connect(_on_dig_toggled)
	remove_button.toggled.connect(_on_remove_toggled)


func _on_build_toggled(toggled_on: bool) -> void:
	build_mode = toggled_on
	item_bar.visible = toggled_on
	rotate_button.visible = toggled_on
	place_button.visible = toggled_on
	if not toggled_on:
		preview_tile = grid.NO_TILE  # leaving build mode drops the preview
		grid.clear_preview()
	if toggled_on:
		dig_button.button_pressed = false  # only one mode at a time
		remove_button.button_pressed = false


func _on_dig_toggled(toggled_on: bool) -> void:
	if toggled_on:
		build_button.button_pressed = false
		remove_button.button_pressed = false


func _on_remove_toggled(toggled_on: bool) -> void:
	remove_mode = toggled_on
	if toggled_on:
		dig_button.button_pressed = false
		build_button.button_pressed = false


func _process(_delta: float) -> void:
	# Mana, digging and building all change whether the preview fits, so refresh it each frame in build mode.
	if build_mode:
		_update_preview()


func _select_item(id: String) -> void:
	selected_id = id


func _on_rotate_pressed() -> void:
	rotation_steps = (rotation_steps + 1) % 4


## The chosen item's size after rotating: every quarter turn swaps width and length.
func _current_size() -> Vector2i:
	var size: Vector2i = dungeon.FURNISHINGS[selected_id]["size"]
	if rotation_steps % 2 == 1:
		size = Vector2i(size.y, size.x)
	return size


func _update_preview() -> void:
	if preview_tile == grid.NO_TILE:
		grid.clear_preview()
		place_button.disabled = true
		return
	var item: Dictionary = dungeon.FURNISHINGS[selected_id]
	var fits: bool = grid.can_place(preview_tile, _current_size(), item.get("needs_deposit", false))
	grid.set_preview(preview_tile, _current_size(), item["color"], fits)
	place_button.disabled = not (fits and dungeon.mana >= item["cost"])


func _on_place_pressed() -> void:
	var item: Dictionary = dungeon.FURNISHINGS[selected_id]
	if not grid.can_place(preview_tile, _current_size(), item.get("needs_deposit", false)):
		return  # not all floor, something's already there, or it needs a deposit
	if not dungeon.try_spend(item["cost"]):
		return  # can't afford it
	grid.place_blueprint(selected_id, preview_tile, _current_size(), item["color"], item.get("blocks", true), rotation_steps)
	preview_tile = grid.NO_TILE  # placed; the next tap starts a new preview


func _unhandled_input(event: InputEvent) -> void:
	if not build_mode and not remove_mode:
		return
	if not taps.is_tap(event):
		return

	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var tile: Vector2i = grid.screen_to_tile(grid.to_local(world_position))
	if remove_mode:
		_remove_at(tile)
		return

	preview_tile = tile  # tapping moves the preview; Place confirms it


## Removes whatever is on a tile: a dig mark, a blueprint, or a finished furnishing.
func _remove_at(tile: Vector2i) -> void:
	if grid.is_marked(tile):
		grid.unmark(tile)
		return
	var furnishing: Dictionary = grid.furnishing_at(tile)
	if furnishing.is_empty():
		return
	var cost: int = dungeon.FURNISHINGS[furnishing["id"]]["cost"]
	var refund: int = cost if not furnishing["built"] else int(cost * DECONSTRUCT_REFUND)
	grid.remove_furnishing(furnishing)
	dungeon.add_mana(refund)
