extends Node
## Hands out work. Workers don't look for jobs themselves; when they're free, they say so, and the
## dispatcher matches idle workers with open jobs, closest pair first, so each job goes to the
## nearest free worker rather than whichever worker happened to look first.

const INTERVAL := 0.5  # seconds between regular checks; a free worker can also ask for one right away
## A free worker takes over a job another worker is still walking to only if it's clearly closer:
## at most this share of the other worker's distance. The margin stops two nearly equal workers
## from swapping a job back and forth ("hysteresis": demand a clear advantage before switching).
const TAKEOVER_MARGIN := 0.75
## Rescues come before all other work: a life is on the clock. Taken off a rescue's distance, so
## any rescue is "closer" than any other job.
const RESCUE_PRIORITY := 100000.0

@export var grid: Node2D
@export var fog: Node2D
@export var rooms: Node

var timer := 0.0
var requested := false  # a worker became free; dispatch on the next frame


## Workers call this when they become free, and the controller when the player asks for work.
func request() -> void:
	requested = true


func _process(delta: float) -> void:
	timer += delta
	if not requested and timer < INTERVAL:
		return
	timer = 0.0
	requested = false
	_dispatch()


## A haul job for every item the player has seen, as long as there's a storage room to bring it to.
func _haul_jobs() -> Array:
	var jobs: Array = []
	var drop: Vector2i = rooms.storage_drop_tile()
	if drop == grid.NO_TILE:
		return jobs  # nowhere to bring things
	for tile in grid.items:
		if fog.is_known(tile) and not grid.claimed.has(tile):
			jobs.append({"kind": "haul", "tile": tile, "furnishing": {}, "position": grid.tile_to_screen(tile),
				"drop": drop, "carrying": false, "item": {}})
	return jobs


## A rescue job for every injured troop that isn't on mycelium and has nobody coming for it,
## as long as there's mycelium somewhere to carry it to.
func _rescue_jobs() -> Array:
	var jobs: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		var has_rescuer: bool = unit.rescuer != null and is_instance_valid(unit.rescuer)
		if not unit.downed or has_rescuer or grid.has_mycelium(unit.get_tile()):
			continue
		var drop: Vector2i = grid.nearest_free_mycelium(unit.position)
		if drop == grid.NO_TILE:
			continue  # no mycelium anywhere
		jobs.append({"kind": "rescue", "tile": unit.get_tile(), "furnishing": {}, "position": unit.position,
			"patient": unit, "drop": drop, "carrying": false})
	return jobs


## Jobs other workers are still walking to, which a closer free worker could take over.
## Each carries a "holder": the worker who has it now.
func _takeover_jobs() -> Array:
	var jobs: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.can_be_taken_over():
			var job: Dictionary = unit.job.duplicate()
			job["position"] = _job_position(job)
			job["holder"] = unit
			jobs.append(job)
	return jobs


func _job_position(job: Dictionary) -> Vector2:
	if job["kind"] == "build":
		return grid.footprint_center(job["furnishing"])
	return grid.tile_to_screen(job["tile"])


func _dispatch() -> void:
	var idle: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.is_idle_worker():
			idle.append(unit)
	if idle.is_empty():
		return
	var jobs: Array = grid.open_jobs() + _haul_jobs() + _takeover_jobs() + _rescue_jobs()

	# Greedy matching: find the closest idle worker and open job anywhere, pair them, and repeat.
	while not idle.is_empty() and not jobs.is_empty():
		var best_worker: Node2D = null
		var best_job: Dictionary = {}
		var best_distance := INF
		for worker in idle:
			for job in jobs:
				if worker.has_failed_to_reach(job):
					continue
				var distance: float = worker.position.distance_to(job["position"])
				if job["kind"] == "rescue":
					distance -= RESCUE_PRIORITY
				if job.has("holder"):
					var holder_distance: float = job["holder"].position.distance_to(job["position"])
					if distance > holder_distance * TAKEOVER_MARGIN:
						continue  # not clearly closer than the worker already heading there
				if distance < best_distance:
					best_worker = worker
					best_job = job
					best_distance = distance
		if best_worker == null:
			return  # every remaining pair is unreachable
		if best_job.has("holder"):
			best_job["holder"].give_up_job()  # the farther worker lets go and asks for other work
			best_job.erase("holder")
		if best_worker.assign(best_job):
			idle.erase(best_worker)
			jobs.erase(best_job)
		# If it failed, the worker now remembers that job as unreachable and the loop tries again.
