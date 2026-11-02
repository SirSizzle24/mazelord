extends Node2D
## A grey circle that walks from tile to tile along a path.

const SPEED := 200.0  # pixels per second
const RADIUS := 20.0

@export var grid: Node2D
@export var start_tile := Vector2i(10, 10)

var tile: Vector2i               # the tile the unit is standing on
var path: Array[Vector2i] = []   # tiles still to walk through
var selected := false


func _ready() -> void:
	tile = start_tile
	grid.dig(tile)  # make sure it starts on floor
	position = grid.tile_to_screen(tile)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(0.6, 0.6, 0.6))
	if selected:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, Color.YELLOW, 2.0)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## Plans a path to the target tile. Does nothing if there's no way there.
func move_to(target: Vector2i) -> void:
	var new_path: Array[Vector2i] = grid.find_path(tile, target)
	if new_path.is_empty():
		return
	new_path.remove_at(0)  # the first tile is where we already stand
	path = new_path


func _process(delta: float) -> void:
	if path.is_empty():
		return
	var next_tile: Vector2i = path[0]
	var target_position: Vector2 = grid.tile_to_screen(next_tile)
	position = position.move_toward(target_position, SPEED * delta)
	if position == target_position:  # arrived at this tile
		tile = next_tile
		path.remove_at(0)
