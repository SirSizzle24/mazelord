extends Node2D
## In dig mode, touching or dragging over rock marks it for a worker to dig.

@export var grid: Node2D
@export var camera: Camera2D
@export var dig_button: Button
@export var fog: Node2D

var dig_mode := false


func _ready() -> void:
	# When the button is toggled, Godot calls our function with its new state.
	dig_button.toggled.connect(_on_dig_button_toggled)


func _on_dig_button_toggled(toggled_on: bool) -> void:
	dig_mode = toggled_on
	camera.pan_enabled = not toggled_on  # one finger digs instead of panning


func _unhandled_input(event: InputEvent) -> void:
	if not dig_mode:
		return
	if camera.touches.size() > 1:
		return  # two fingers means pinch-zoom, not digging

	var is_press: bool = event is InputEventScreenTouch and event.pressed
	if is_press or event is InputEventScreenDrag:
		# Touch positions are in screen pixels; convert to world, then to the grid's own space.
		var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
		var tile: Vector2i = grid.screen_to_tile(grid.to_local(world_position))
		grid.mark(tile, not fog.is_known(tile))  # hidden tiles can be marked whatever they hide
