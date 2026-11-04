extends "res://scripts/fighter.gd"
## A raider: heads for your dungeon's core and stops to fight any troop in its way.
## Only shows while one of your troops can see it.

const SPEED := 150.0  # pixels per second
const RADIUS := 18.0
const COLOR := Color(0.85, 0.20, 0.20)
const REPATH_TIME := 1.0  # seconds between fresh paths, since your dungeon changes as it walks

var grid: Node2D
var fog: Node2D
var path: PackedVector2Array = []
var repath_time_left := 0.0


func _ready() -> void:
	add_to_group("raiders")
	enemy_group = "units"


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR.darkened(0.5) if downed else COLOR)
	_draw_combat(RADIUS)


func _process(delta: float) -> void:
	visible = fog.is_in_sight(grid.screen_to_tile(position))  # hidden in the fog
	if downed:
		return
	if _fight(delta):
		return  # stand and fight while a troop is in range

	repath_time_left -= delta
	if repath_time_left <= 0.0:
		repath_time_left = REPATH_TIME
		var core: Vector2 = grid.tile_to_screen(grid.START_CENTER)
		var map: RID = get_world_2d().navigation_map
		path = NavigationServer2D.map_get_path(map, position, core, true)  # gets as close as it can
	if path.is_empty():
		return
	position = position.move_toward(path[0], SPEED * delta)
	if position == path[0]:
		path.remove_at(0)
