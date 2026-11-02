extends Node2D
## A grey circle that walks freely along a navigation path, not tile by tile.

const SPEED := 200.0  # pixels per second
const RADIUS := 20.0

@export var grid: Node2D
@export var start_tile := Vector2i(10, 10)

var path: PackedVector2Array = []  # points still to walk to, in straight lines
var selected := false


func _ready() -> void:
	grid.dig(start_tile)  # make sure it starts on floor
	position = grid.tile_to_screen(start_tile)


## The tile the unit is currently over.
func get_tile() -> Vector2i:
	return grid.screen_to_tile(position)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(0.6, 0.6, 0.6))
	if selected:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, Color.YELLOW, 2.0)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## Plans a path to the center of a floor tile. Does nothing if there's no way there.
func move_to(target_tile: Vector2i) -> void:
	if not grid.is_floor(target_tile):
		return
	var target: Vector2 = grid.tile_to_screen(target_tile)
	var map: RID = get_world_2d().navigation_map
	var new_path: PackedVector2Array = NavigationServer2D.map_get_path(map, position, target, true)

	# The server returns the closest reachable point when the target can't be reached,
	# so check that the path really ends at the target.
	if new_path.is_empty() or new_path[new_path.size() - 1].distance_to(target) > RADIUS:
		return
	path = new_path


func _process(delta: float) -> void:
	if path.is_empty():
		return
	position = position.move_toward(path[0], SPEED * delta)
	if position == path[0]:  # reached this point; head for the next
		path.remove_at(0)
