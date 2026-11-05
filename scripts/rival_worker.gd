extends "res://scripts/fighter.gd"
## A rival worker. Waits by the rival core; when a guard goes down off the mycelium, it walks over,
## carries the guard to the rival mycelium, and sets it down to revive. Weak, and can be attacked.

const SPEED := 130.0
const RADIUS := 14.0
const COLOR := Color(0.75, 0.55, 0.85)
const REPATH_TIME := 0.5
const PICKUP_DISTANCE := 30.0

var grid: Node2D
var fog: Node2D
var home := Vector2.ZERO
var patient: Node2D = null
var carrying := false
var path: PackedVector2Array = []
var repath_time_left := 0.0


func _ready() -> void:
	add_to_group("hostiles")
	add_to_group("rival_workers")
	enemy_group = "units"


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR.darkened(0.5) if downed else COLOR)
	_draw_combat(RADIUS)


func _on_downed() -> void:
	_drop_patient()


func _process(delta: float) -> void:
	visible = fog.is_in_sight(grid.screen_to_tile(position))
	if downed:
		return
	_fight(delta)  # fights back weakly, but keeps working

	if patient != null and (not is_instance_valid(patient) or not patient.downed):
		patient = null  # revived or gone
		carrying = false
	if patient == null:
		_find_patient()

	var goal := home
	if patient != null:
		if carrying:
			goal = grid.tile_to_screen(_nearest_rival_mycelium())
			if position.distance_to(goal) < PICKUP_DISTANCE:
				_drop_patient()  # set it down on the mycelium to revive
				return
		else:
			goal = patient.position
			if position.distance_to(goal) < PICKUP_DISTANCE:
				carrying = true
				patient.carried_by = self

	repath_time_left -= delta
	if repath_time_left <= 0.0:
		repath_time_left = REPATH_TIME
		var map: RID = get_world_2d().navigation_map
		path = NavigationServer2D.map_get_path(map, position, goal, true, grid.RAIDER_LAYER)
	if not path.is_empty():
		position = position.move_toward(path[0], SPEED * delta)
		if position == path[0]:
			path.remove_at(0)


## Claims the nearest downed guard that's off the mycelium and nobody else is coming for.
func _find_patient() -> void:
	var best := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var taken: bool = guard.rescuer != null and is_instance_valid(guard.rescuer)
		if not guard.downed or taken or grid.has_mycelium(grid.screen_to_tile(guard.position), "rival"):
			continue
		var distance := position.distance_to(guard.position)
		if distance < best:
			best = distance
			patient = guard
	if patient != null:
		patient.rescuer = self
		carrying = false


func _drop_patient() -> void:
	if patient != null and is_instance_valid(patient):
		patient.carried_by = null
		patient.rescuer = null
		patient.position = position
	patient = null
	carrying = false


func _nearest_rival_mycelium() -> Vector2i:
	var best: Vector2i = grid.rival_core
	var best_distance := INF
	for tile in grid.rival_mycelium:
		var distance := position.distance_to(grid.tile_to_screen(tile))
		if distance < best_distance:
			best = tile
			best_distance = distance
	return best
