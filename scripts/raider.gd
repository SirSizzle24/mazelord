extends "res://scripts/fighter.gd"
## A raider. Attacking, it heads for your dungeon's core, stopping to fight any troop in its way.
## Raiders walk on their own walkable shape where doors are closed: when a door is what blocks the
## way, they bash it down; only when rock blocks it do they dig (slowly). Retreating, it heads back to where it
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
var door: Dictionary = {}  # the door it's breaking down, or empty
var bash_cooldown := 0.0


func _ready() -> void:
	add_to_group("raiders")
	add_to_group("hostiles")  # what your troops attack
	enemy_group = "units"


## Turns back toward the exit (the raid timed out, or the core was taken).
func retreat() -> void:
	retreating = true
	dig_tile = grid.NO_TILE
	door = {}
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
		_plan(goal)

	if not path.is_empty():
		position = position.move_toward(path[0], SPEED * delta)
		if position == path[0]:
			path.remove_at(0)
		return

	# Out of path and short of the goal: break the door in the way, or dig if it's rock.
	if not door.is_empty():
		_bash_door(delta)
	elif not retreating and position.distance_to(goal) > ARRIVE_DISTANCE:
		_start_digging_toward(goal)


## Plans the way to the goal. If doors are what stop the raiders' own path, it heads for the first
## door on the troops' path (which treats doors as open) to break it down.
func _plan(goal: Vector2) -> void:
	var map: RID = get_world_2d().navigation_map
	var own_path: PackedVector2Array = NavigationServer2D.map_get_path(map, position, goal, true, grid.RAIDER_LAYER)
	door = {}
	if _reaches(own_path, goal):
		path = own_path
		return
	var open_path: PackedVector2Array = NavigationServer2D.map_get_path(map, position, goal, true, grid.TROOP_LAYER)
	if _reaches(open_path, goal):
		door = _first_door_on(open_path)
	if door.is_empty():
		path = own_path  # rock in the way: get as close as it can, then dig
	else:
		# Walk up to the door; its tile isn't walkable for raiders, so the path stops beside it.
		var door_spot: Vector2 = grid.tile_to_screen(door["origin"])
		path = NavigationServer2D.map_get_path(map, position, door_spot, true, grid.RAIDER_LAYER)


func _reaches(some_path: PackedVector2Array, goal: Vector2) -> bool:
	return not some_path.is_empty() and some_path[some_path.size() - 1].distance_to(goal) < ARRIVE_DISTANCE


## The first finished door along a path, checked every 30 pixels so no tile is skipped. Empty if none.
func _first_door_on(some_path: PackedVector2Array) -> Dictionary:
	var previous := position
	for point in some_path:
		var steps: int = max(ceili(previous.distance_to(point) / 30.0), 1)
		for i in range(1, steps + 1):
			var tile: Vector2i = grid.screen_to_tile(previous.lerp(point, float(i) / steps))
			if grid.is_door(tile):
				return grid.furnishing_at(tile)
		previous = point
	return {}


## Hits the door in its way, using the raider's own damage and attack speed.
func _bash_door(delta: float) -> void:
	if not grid.furnishings.has(door):
		door = {}  # already broken, by this raider or another
		repath_time_left = 0.0
		return
	bash_cooldown = max(bash_cooldown - delta, 0.0)
	if bash_cooldown == 0.0:
		grid.damage_door(door, damage)
		bash_cooldown = attack_interval
		flash_at = grid.tile_to_screen(door["origin"]) - position
		flash_time_left = FLASH_TIME
		queue_redraw()


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
