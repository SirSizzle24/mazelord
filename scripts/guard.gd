extends "res://scripts/fighter.gd"
## A rival guard. Holds its post, chases your troops that come near, then returns.
## Downed guards don't die: rival workers carry them to the rival mycelium, where they revive.

const SPEED := 210.0
const RADIUS := 27.0
const COLOR := Color(0.55, 0.25, 0.70)
const CHASE_RANGE := 330.0  # how far from its post a guard will go after your troops
const REPATH_TIME := 0.5
const HEAL_TIME := 15.0  # seconds on mycelium to revive at full health

var grid: Node2D
var fog: Node2D
var post := Vector2.ZERO
var path: PackedVector2Array = []
var repath_time_left := 0.0
var heal_time := 0.0
var carried_by: Node2D = null  # the rival worker carrying it, or null
var rescuer: Node2D = null  # the rival worker coming for it, or null


func _ready() -> void:
	add_to_group("hostiles")
	add_to_group("guards")
	enemy_group = "units"


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR.darkened(0.5) if downed else COLOR)
	_draw_combat(RADIUS)
	if downed and grid.has_mycelium(grid.screen_to_tile(position), "rival"):
		draw_arc(Vector2.ZERO, RADIUS + 6.0, -PI / 2.0, -PI / 2.0 + TAU * heal_time / HEAL_TIME, 32, Color(0.4, 0.95, 0.4), 3.0)


func _process(delta: float) -> void:
	visible = fog.is_in_sight(grid.screen_to_tile(position))
	if downed:
		_process_downed(delta)
		return
	if _fight(delta):
		return

	# Chase the nearest troop near the post; otherwise go back to the post.
	var goal := post
	var best := CHASE_RANGE
	for unit in get_tree().get_nodes_in_group("units"):
		if not unit.downed and post.distance_to(unit.position) <= best:
			goal = unit.position
			best = post.distance_to(unit.position)

	repath_time_left -= delta
	if repath_time_left <= 0.0:
		repath_time_left = REPATH_TIME
		var map: RID = get_world_2d().navigation_map
		path = NavigationServer2D.map_get_path(map, position, goal, true, grid.RAIDER_LAYER)
	if not path.is_empty():
		position = position.move_toward(path[0], SPEED * delta)
		if position == path[0]:
			path.remove_at(0)


func _process_downed(delta: float) -> void:
	if carried_by != null and is_instance_valid(carried_by):
		position = carried_by.position + Vector2(0, -RADIUS)
		return
	carried_by = null
	if grid.has_mycelium(grid.screen_to_tile(position), "rival"):
		heal_time += delta
		queue_redraw()
		if heal_time >= HEAL_TIME:
			downed = false
			health = max_health
			heal_time = 0.0
			rescuer = null
