extends Node
## Hands out work. Workers don't look for jobs themselves; when they're free, they say so, and the
## dispatcher matches idle workers with open jobs, closest pair first, so each job goes to the
## nearest free worker rather than whichever worker happened to look first.

const INTERVAL := 0.5  # seconds between regular checks; a free worker can also ask for one right away

@export var grid: Node2D

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


func _dispatch() -> void:
	var idle: Array = []
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.is_idle_worker():
			idle.append(unit)
	if idle.is_empty():
		return
	var jobs: Array = grid.open_jobs()

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
				if distance < best_distance:
					best_worker = worker
					best_job = job
					best_distance = distance
		if best_worker == null:
			return  # every remaining pair is unreachable
		if best_worker.assign(best_job):
			idle.erase(best_worker)
			jobs.erase(best_job)
		# If it failed, the worker now remembers that job as unreachable and the loop tries again.
