extends Node2D
## A troop: a colored circle that walks freely along a navigation path.
## Workers dig marked rock and build blueprints. The job dispatcher hands out the work; a worker
## tells it when it's free.

const SPEED := 200.0  # pixels per second
const RADIUS := 20.0
const DIG_TIME := 1.5  # seconds to dig one tile (build time lives on the grid)

@export var grid: Node2D
@export var start_tile := Vector2i(30, 30)
var dispatcher: Node  # set by the dungeon when summoning

var type_id := ""  # which troop type this is, e.g. "worker"
var color := Color(0.6, 0.6, 0.6)
var can_dig := false  # workers only: digging and building

var path: PackedVector2Array = []  # points still to walk to, in straight lines
var selected := false

var job: Dictionary = {}  # the current job ({"kind", "tile", "furnishing"}), or empty for none
var job_progress := 0.0  # seconds spent digging the current tile (build progress lives on the furnishing)
var unreachable: Dictionary = {}  # job tiles this worker couldn't reach; skipped until the map changes
var unreachable_version := -1  # the grid's nav_version when unreachable was last cleared


## Called by the dungeon before the unit enters the scene.
func setup(new_type_id: String, troop_type: Dictionary) -> void:
	type_id = new_type_id
	color = troop_type["color"]
	can_dig = troop_type["can_dig"]


func _ready() -> void:
	add_to_group("units")  # lets the controller find every unit
	grid.dig(start_tile)  # make sure it starts on floor
	position = grid.tile_to_screen(start_tile)


## The tile the unit is currently over.
func get_tile() -> Vector2i:
	return grid.screen_to_tile(position)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)
	if selected:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, Color.YELLOW, 2.0)
	var fraction := _job_fraction()
	if fraction > 0.0 and path.is_empty():
		# An orange ring fills up while working.
		draw_arc(Vector2.ZERO, RADIUS + 8.0, -PI / 2.0, -PI / 2.0 + TAU * fraction, 32, Color.ORANGE, 3.0)


## How far along the current job is, from 0 to 1.
func _job_fraction() -> float:
	if job.is_empty():
		return 0.0
	if job["kind"] == "build":
		return job["furnishing"]["progress"] / grid.BUILD_TIME
	return job_progress / DIG_TIME


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## True if this is a worker with nothing to do: no job and nowhere to walk.
## The dispatcher only gives work to idle workers, so a troop sent somewhere finishes the trip first.
func is_idle_worker() -> bool:
	return can_dig and job.is_empty() and path.is_empty()


## True if this worker tried and failed to reach that job since the walkable shape last changed.
func has_failed_to_reach(some_job: Dictionary) -> bool:
	_refresh_unreachable()
	return unreachable.has(some_job["tile"])


## The dispatcher's way of giving this worker a job. Returns false, and remembers the job as
## unreachable, if there's no way to it.
func assign(new_job: Dictionary) -> bool:
	if _take_job(new_job):
		return true
	unreachable[new_job["tile"]] = true
	return false


func _refresh_unreachable() -> void:
	if unreachable_version != grid.nav_version:
		unreachable.clear()  # the walkable shape changed, so old failures may be reachable now
		unreachable_version = grid.nav_version


## Walks to the center of a floor tile. Cancels any work.
func move_to(target_tile: Vector2i) -> void:
	_stop_working()
	if grid.is_floor(target_tile):
		_walk_to(grid.tile_to_screen(target_tile))


## The player's direct order: work on the job at the tapped tile if it's free; otherwise go back to
## the dispatcher for whatever's closest.
func start_working(tapped: Vector2i) -> void:
	if not can_dig:
		return  # only workers dig and build
	_stop_working()
	var first := {}
	var blueprint: Dictionary = grid.blueprint_at(tapped)
	if not blueprint.is_empty() and not grid.claimed.has(blueprint["origin"]):
		first = {"kind": "build", "tile": blueprint["origin"], "furnishing": blueprint}
	elif grid.is_marked(tapped) and grid.has_floor_neighbor(tapped) and not grid.claimed.has(tapped):
		first = {"kind": "dig", "tile": tapped, "furnishing": {}}
	if first.is_empty() or not _take_job(first):
		dispatcher.request()


## Claims a job and walks to the nearest side of it. Returns false, claiming nothing, if it can't be reached.
func _take_job(new_job: Dictionary) -> bool:
	job = new_job
	job_progress = 0.0
	grid.claimed[job["tile"]] = self

	# Work from whichever side of the job is the shortest walk away.
	if not _walk_to_nearest(grid.work_spots(job)):
		_release_job()
		return false
	return true


## Lets go of the current job, so another worker can take it.
func _stop_working() -> void:
	_release_job()
	queue_redraw()


func _release_job() -> void:
	if not job.is_empty() and grid.claimed.get(job["tile"]) == self:
		grid.claimed.erase(job["tile"])
	job = {}
	job_progress = 0.0


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


## Walks to whichever spot has the shortest walking path. Returns false if none can be reached.
func _walk_to_nearest(spots: PackedVector2Array) -> bool:
	var map: RID = get_world_2d().navigation_map
	var best_path := PackedVector2Array()
	var best_length := INF
	for spot in spots:
		var target: Vector2 = NavigationServer2D.map_get_closest_point(map, spot)  # snap onto walkable ground
		var candidate: PackedVector2Array = NavigationServer2D.map_get_path(map, position, target, true)
		if candidate.is_empty() or candidate[candidate.size() - 1].distance_to(target) > RADIUS:
			continue  # can't get there
		var length := _path_length(candidate)
		if length < best_length:
			best_length = length
			best_path = candidate
	if best_path.is_empty():
		return false
	path = best_path
	return true


## Total walking distance along a path, from the unit's position.
func _path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	var previous := position
	for point in points:
		total += previous.distance_to(point)
		previous = point
	return total


func _process(delta: float) -> void:
	# The player may have cancelled this job (unmarked the rock or removed the blueprint).
	if not job.is_empty() and not grid.job_still_exists(job):
		_release_job()
		path = PackedVector2Array()  # stop walking to it
		queue_redraw()
		dispatcher.request()  # free again
		return

	if not path.is_empty():
		position = position.move_toward(path[0], SPEED * delta)
		if position == path[0]:  # reached this point; head for the next
			path.remove_at(0)
			if path.is_empty() and job.is_empty() and can_dig:
				dispatcher.request()  # arrived with nothing to do (after digging in, or a move order)
		return

	if job.is_empty():
		return  # idle; the dispatcher will hand out work

	queue_redraw()  # update the progress ring
	var finished := false
	if job["kind"] == "build":
		finished = grid.add_build_progress(job["furnishing"], delta)
	else:
		job_progress += delta
		finished = job_progress >= DIG_TIME
	if not finished:
		return

	# Job finished.
	var done := job
	_release_job()
	if done["kind"] == "dig":
		grid.dig(done["tile"])
		# Tunnel in: step straight into the freshly dug tile, then look for the next job on arrival.
		path = PackedVector2Array([grid.tile_to_screen(done["tile"])])
	else:
		dispatcher.request()  # built it; free for the next job
