extends Node2D
## A grey circle that walks freely along a navigation path, and can be set to dig marked rock.

const SPEED := 200.0  # pixels per second
const RADIUS := 20.0
const DIG_TIME := 1.5  # seconds to dig one tile

@export var grid: Node2D
@export var start_tile := Vector2i(10, 10)

var path: PackedVector2Array = []  # points still to walk to, in straight lines
var selected := false

var is_digger := false  # true while assigned to dig: keeps taking the nearest marked tile
var dig_target: Vector2i = Vector2i(-1, -1)  # the tile being dug, or NO_TILE
var dig_progress := 0.0  # seconds spent on the current tile


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
	if dig_progress > 0.0:
		# An orange ring fills up while digging.
		var fraction := dig_progress / DIG_TIME
		draw_arc(Vector2.ZERO, RADIUS + 8.0, -PI / 2.0, -PI / 2.0 + TAU * fraction, 32, Color.ORANGE, 3.0)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## Walks to the center of a floor tile. Cancels any digging.
func move_to(target_tile: Vector2i) -> void:
	_stop_digging()
	if grid.is_floor(target_tile):
		_walk_to(grid.tile_to_screen(target_tile))


## Assigns this unit to dig, starting with the given marked tile if it can be reached.
func start_digging(first_tile: Vector2i) -> void:
	is_digger = true
	if not grid.has_floor_neighbor(first_tile):
		first_tile = grid.nearest_diggable(position)  # can't reach that one yet; take the nearest
	_go_dig(first_tile)


## Heads for a marked tile: walks to the nearest point beside it, then digs.
func _go_dig(tile: Vector2i) -> void:
	if tile == grid.NO_TILE:
		_stop_digging()  # nothing left to dig
		return
	dig_target = tile
	dig_progress = 0.0
	var map: RID = get_world_2d().navigation_map
	# The rock itself isn't walkable, so aim for the closest walkable point to it.
	var beside: Vector2 = NavigationServer2D.map_get_closest_point(map, grid.tile_to_screen(tile))
	if not _walk_to(beside):
		print("Can't reach marked tile ", tile, "; stopping")
		_stop_digging()


func _stop_digging() -> void:
	is_digger = false
	dig_target = grid.NO_TILE
	dig_progress = 0.0
	queue_redraw()


## Plans a path to a point. Returns false, and stays put, if there's no way there.
func _walk_to(point: Vector2) -> bool:
	var map: RID = get_world_2d().navigation_map
	var new_path: PackedVector2Array = NavigationServer2D.map_get_path(map, position, point, true)
	# The server returns the closest reachable point when the target can't be reached,
	# so check that the path really ends at the target.
	if new_path.is_empty() or new_path[new_path.size() - 1].distance_to(point) > RADIUS:
		return false
	path = new_path
	return true


func _process(delta: float) -> void:
	if not path.is_empty():
		position = position.move_toward(path[0], SPEED * delta)
		if position == path[0]:  # reached this point; head for the next
			path.remove_at(0)
			if path.is_empty() and is_digger and dig_target == grid.NO_TILE:
				_go_dig(grid.nearest_diggable(position))  # stepped into a dug tile; find the next
		return

	if dig_target != grid.NO_TILE:
		dig_progress += delta
		queue_redraw()  # update the progress ring
		if dig_progress >= DIG_TIME:
			var dug := dig_target
			grid.dig(dug)
			dig_target = grid.NO_TILE
			dig_progress = 0.0
			# Tunnel in: step straight into the freshly dug tile.
			path = PackedVector2Array([grid.tile_to_screen(dug)])
