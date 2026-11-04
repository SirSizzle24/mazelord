extends "res://scripts/fighter.gd"
## A raider. Attacking, it heads for your dungeon's core, stopping to fight any troop in its way and
## digging through rock (slowly) where there's no open path. Retreating, it heads back to where it
## came in and leaves. Only shows while one of your troops can see it.

const SPEED := 150.0  # pixels per second
const RADIUS := 18.0
const COLOR := Color(0.85, 0.20, 0.20)
const REPATH_TIME := 1.0  # seconds between fresh paths, since your dungeon changes as it walks
const DIG_TIME := 4.0  # seconds to dig a tile; slower than your workers, so you have time to react
const ARRIVE_DISTANCE := 60.0  # how close counts as reaching the core or the exit

var grid: Node2D
var fog: Node2D
var exit_point := Vector2.ZERO  # where it came in, and leaves from
var retreating := false
var carrying_loot := false  # set when it reached your core
var path: PackedVector2Array = []
var repath_time_left := 0.0
var dig_tile := Vector2i(-1, -1)  # the rock it's digging, or (-1, -1)
var dig_time_left := 0.0


func _ready() -> void:
	add_to_group("raiders")
	enemy_group = "units"


## Turns back toward the exit (the raid timed out, or the core was taken).
func retreat() -> void:
	retreating = true
	dig_tile = grid.NO_TILE
	repath_time_left = 0.0


func core_position() -> Vector2:
	return grid.tile_to_screen(grid.START_CENTER)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR.darkened(0.5) if downed else COLOR)
	if carrying_loot and not downed:
		draw_circle(Vector2(0, -RADIUS - 8.0), 7.0, Color(0.45, 0.80, 1.0))  # stolen mana
	_draw_combat(RADIUS)


func _process(delta: float) -> void:
	visible = fog.is_in_sight(grid.screen_to_tile(position))  # hidden in the fog
	if downed:
		return
	if _fight(delta):
		return  # stand and fight while a troop is in range

	var goal: Vector2 = exit_point if retreating else core_position()
	if retreating and position.distance_to(exit_point) < ARRIVE_DISTANCE:
		queue_free()  # gone back into the labyrinth
		return

	if dig_tile != grid.NO_TILE:
		_keep_digging(delta)
		return

	repath_time_left -= delta
	if repath_time_left <= 0.0:
		repath_time_left = REPATH_TIME
		var map: RID = get_world_2d().navigation_map
		path = NavigationServer2D.map_get_path(map, position, goal, true)  # gets as close as it can

	if not path.is_empty():
		position = position.move_toward(path[0], SPEED * delta)
		if position == path[0]:
			path.remove_at(0)
		return

	# Out of path. If it still isn't at the core, the way is blocked by rock: dig toward the core.
	if not retreating and position.distance_to(goal) > ARRIVE_DISTANCE:
		_start_digging_toward(goal)


## Picks the rock tile beside it that's closest to the goal, and starts digging it.
func _start_digging_toward(goal: Vector2) -> void:
	var here: Vector2i = grid.screen_to_tile(position)
	var goal_tile: Vector2i = grid.screen_to_tile(goal)
	var best: Vector2i = grid.NO_TILE
	var best_distance := INF
	for offset in grid.NEIGHBORS:
		var tile: Vector2i = here + offset
		if grid.is_in_bounds(tile) and not grid.is_floor(tile):
			var distance := Vector2(tile).distance_to(Vector2(goal_tile))
			if distance < best_distance:
				best = tile
				best_distance = distance
	dig_tile = best
	dig_time_left = DIG_TIME


func _keep_digging(delta: float) -> void:
	dig_time_left -= delta
	if dig_time_left > 0.0:
		return
	grid.dig(dig_tile)  # unseen digging doesn't show in the fog until a troop looks
	position = grid.tile_to_screen(dig_tile)  # step into the new tunnel
	dig_tile = grid.NO_TILE
	repath_time_left = 0.0
