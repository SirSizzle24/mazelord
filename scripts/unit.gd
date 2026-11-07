extends "res://scripts/fighter.gd"
## A troop: a colored circle that walks freely along a navigation path.
## Combat (health, attacking raiders in range, being downed) comes from fighter.gd.
## Downed troops are injured: they die if the death timer runs out, unless they're on mycelium,
## where they heal. Workers carry injured troops to mycelium (rescues come before other work).
## Workers dig marked rock and build blueprints. The job dispatcher hands out the work; a worker
## tells it when it's free.

const SPEED := 300.0  # pixels per second
const DIG_TIME := 0.4  # seconds to dig one cell, so a block takes about 3.6 s (build time lives on the grid)
const DEATH_TIME := 60.0  # seconds an injured troop survives off mycelium
const HEAL_TIME := 20.0  # seconds on mycelium for an injured troop to get back up
const RECOVERED_HEALTH := 0.5  # share of full health it gets back up with
const MYCELIUM_REGEN := 2.0  # health per second a hurt (but standing) fungus regains on mycelium
# Fame earned, per deed. Placeholders to tune.
const FAME_PER_JOB := 1.0  # building and hauling
const FAME_PER_DUG_CELL := 0.12  # about 1 per block dug
const FAME_PER_RESCUE := 3.0
const FAME_PER_DAMAGE := 0.1  # so 10 damage dealt = 1 fame
const FAME_PER_DOWNED_RAIDER := 5.0
const FAME_FOR_SURVIVING := 5.0  # standing when a raid ends, or recovering from an injury
const FAME_PER_MINUTE := 1.0  # long service

@export var grid: Node2D
@export var start_tile := Vector2i(91, 91)
var dispatcher: Node  # set by the dungeon when summoning
var dungeon: Node  # set by the dungeon; receives hauled items

var type_id := ""  # which troop type this is, e.g. "worker"
var color := Color(0.6, 0.6, 0.6)
var can_dig := false  # workers only: digging and building
var radius := 20.0  # set from the troop type; everyone but workers is bigger
var size := "small"  # size class (see grid.SIZES): which tunnels it fits through
var roster_label := ""  # the troop type ("Worker") until it earns a name, then its name
var flight := 0  # which flight it's in: 1 to 5, or 0 for none
var element := 1  # which element of its flight: 1 to 4

var path: PackedVector2Array = []  # points still to walk to, in straight lines
var selected := false

var job: Dictionary = {}  # the current job ({"kind", "tile", "furnishing"}), or empty for none
var job_progress := 0.0  # seconds spent digging the current tile (build progress lives on the furnishing)
var unreachable: Dictionary = {}  # job tiles this worker couldn't reach; skipped until the map changes
var unreachable_version := -1  # the grid's nav_version when unreachable was last cleared

var death_time_left := 0.0  # while injured
var heal_time := 0.0  # seconds spent healing on mycelium while injured
var fame := 0.0
## What this troop has been through, for its card (and later, for what it remembers and says).
var history := {"raids_survived": 0, "raiders_downed": 0, "times_injured": 0, "injuries_survived": 0,
	"rescues": 0, "cells_dug": 0, "builds": 0, "hauls": 0}
var is_named := false
var is_hero := false  # heroes carry a unique skill; their card glows (no way to become one yet)
var troop_name := ""
var awaiting_name := false  # fame reached the threshold; the player is choosing a name
var service_time := 0.0
var door_bash_cooldown := 0.0
var carried_by: Node2D = null  # the worker carrying this injured troop, or null
var rescuer: Node2D = null  # the worker on its way to rescue it, or null


## Called by the dungeon before the unit enters the scene.
func setup(new_type_id: String, troop_type: Dictionary) -> void:
	type_id = new_type_id
	color = troop_type["color"]
	can_dig = troop_type["can_dig"]
	radius = troop_type["radius"]
	size = troop_type["size"]
	set_stats(troop_type)


func _ready() -> void:
	add_to_group("units")  # lets the controller find every unit
	enemy_group = "hostiles"  # raiders, rival guards and rival workers
	grid.dig(start_tile)  # make sure it starts on floor
	position = grid.tile_to_screen(start_tile)


## Adds fame. Crossing the threshold asks the player to name this troop.
func add_fame(amount: float) -> void:
	fame += amount
	if not is_named and not awaiting_name and fame >= dungeon.name_threshold():
		awaiting_name = true
		dungeon.name_earned.emit(self)


## The player chose a name. From now on this troop is named: it hurts more to lose, and later it can
## become a hero.
func give_name(chosen: String) -> void:
	is_named = true
	awaiting_name = false
	troop_name = chosen
	roster_label = chosen
	queue_redraw()


## Rival doors are closed to your troops; a troop next to one breaks it down.
func _bash_rival_door(delta: float) -> void:
	door_bash_cooldown = max(door_bash_cooldown - delta, 0.0)
	if door_bash_cooldown > 0.0:
		return
	var reach: float = attack_range + grid.TILE_WIDTH * grid.BLOCK / 2.0  # the door's block is out of walking range
	var door: Dictionary = grid.door_near(position, reach, "rival")
	if door.is_empty():
		return
	grid.damage_door(door, damage)
	door_bash_cooldown = attack_interval
	flash_at = grid.tile_to_screen(door["origin"]) - position
	flash_time_left = FLASH_TIME
	add_fame(damage * FAME_PER_DAMAGE)
	queue_redraw()


func _on_hit_landed(damage_dealt: float, downed_it: bool) -> void:
	add_fame(damage_dealt * FAME_PER_DAMAGE)
	if downed_it:
		add_fame(FAME_PER_DOWNED_RAIDER)
		record("raiders_downed")


## The tile the unit is currently over.
func get_tile() -> Vector2i:
	return grid.screen_to_tile(position)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color.darkened(0.5) if downed else color)
	if selected:
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 32, Color.YELLOW, 2.0)
	if flight > 0:
		# Flight and element above the troop, e.g. "2-1".
		draw_string(ThemeDB.fallback_font, Vector2(-30, -radius - 6.0), "%d-%d" % [flight, element],
			HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color.WHITE)
	if is_named:
		draw_string(ThemeDB.fallback_font, Vector2(-60, radius + 26.0), troop_name,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1.0, 0.9, 0.5))
	_draw_combat(radius)
	if downed:
		if grid.has_mycelium(get_tile()):
			# Healing: a green ring fills up.
			draw_arc(Vector2.ZERO, radius + 6.0, -PI / 2.0, -PI / 2.0 + TAU * heal_time / HEAL_TIME, 32, Color(0.4, 0.95, 0.4), 3.0)
		else:
			# Dying: a red ring shrinks as time runs out.
			draw_arc(Vector2.ZERO, radius + 6.0, -PI / 2.0, -PI / 2.0 + TAU * death_time_left / DEATH_TIME, 32, Color(0.95, 0.25, 0.25), 3.0)
	if not job.is_empty() and job["kind"] == "haul" and job["carrying"]:
		# A carried item rides above the troop.
		draw_circle(Vector2(0, -radius - 8.0), 7.0, grid.ITEM_COLORS[job["item"]["kind"]])
	var fraction := _job_fraction()
	if fraction > 0.0 and path.is_empty():
		# An orange ring fills up while working.
		draw_arc(Vector2.ZERO, radius + 8.0, -PI / 2.0, -PI / 2.0 + TAU * fraction, 32, Color.ORANGE, 3.0)


## How far along the current job is, from 0 to 1. Hauling shows no ring.
func _job_fraction() -> float:
	if job.is_empty() or job["kind"] == "haul" or job["kind"] == "rescue":
		return 0.0
	if job["kind"] == "build":
		return job["furnishing"]["progress"] / grid.BUILD_TIME
	return job_progress / DIG_TIME


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## True if this is a worker with nothing to do: no job and nowhere to walk.
## The dispatcher only gives work to idle workers, so a troop sent somewhere finishes the trip first.
## Workers never join flights, and sheltered workers (the alarm) do no work.
func is_idle_worker() -> bool:
	return can_dig and not downed and not dungeon.workers_sheltered and job.is_empty() and path.is_empty()


## Puts a fighter in a flight and element (flight 0 takes it out). Workers can't join flights:
## they belong to the workforce and shouldn't flood the front lines.
## Counts one more of something in this troop's history.
func record(event: String) -> void:
	history[event] += 1


func set_flight(new_flight: int, new_element: int) -> void:
	if can_dig:
		return
	flight = new_flight
	element = new_element
	queue_redraw()


## A short description of what the troop is doing, for its card.
func status_text() -> String:
	if downed:
		return "Injured (%d s left)" % ceili(death_time_left) if not grid.has_mycelium(get_tile()) else "Healing"
	if can_dig and dungeon.workers_sheltered:
		return "In quarters"
	if not job.is_empty():
		return {"dig": "Digging", "build": "Building", "haul": "Hauling", "rescue": "Rescuing"}[job["kind"]]
	return "Moving" if not path.is_empty() else "Idle"


## Walks to a point (snapped onto walkable ground). Used by flight moves. Cancels any work.
func move_to_point(point: Vector2) -> void:
	if downed:
		return
	_stop_working()
	var map: RID = get_world_2d().navigation_map
	_walk_to(NavigationServer2D.map_get_closest_point(map, point))


## True if this worker tried and failed to reach that job since the walkable shape last changed.
func has_failed_to_reach(some_job: Dictionary) -> bool:
	_refresh_unreachable()
	return unreachable.has(some_job["tile"])


## True if a closer free worker may take this worker's job: it's still walking there (no progress
## to lose), it isn't carrying anything, and the player didn't assign it directly ("manual").
func can_be_taken_over() -> bool:
	if job.is_empty() or path.is_empty() or job.get("manual", false) or job["kind"] == "rescue":
		return false
	return not (job["kind"] == "haul" and job["carrying"])


## Lets another worker have this job: stops, lets go, and asks the dispatcher for something else.
func give_up_job() -> void:
	_stop_working()
	path = PackedVector2Array()
	dispatcher.request()


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
	if downed:
		return
	_stop_working()
	if grid.is_floor(target_tile):
		_walk_to(grid.tile_to_screen(target_tile))


## The player's direct order: work on the job at the tapped tile if it's free; otherwise go back to
## the dispatcher for whatever's closest.
func start_working(tapped: Vector2i) -> void:
	if not can_dig or downed:
		return  # only standing workers dig and build
	_stop_working()
	var first := {}
	var blueprint: Dictionary = grid.blueprint_at(tapped)
	if not blueprint.is_empty() and not grid.claimed.has(blueprint["origin"]):
		first = {"kind": "build", "tile": blueprint["origin"], "furnishing": blueprint, "manual": true}
	elif grid.is_marked(tapped) and grid.has_floor_neighbor(tapped) and not grid.claimed.has(tapped):
		first = {"kind": "dig", "tile": tapped, "furnishing": {}, "manual": true}
	if first.is_empty() or not _take_job(first):
		dispatcher.request()


## Claims a job and walks to the nearest side of it. Returns false, claiming nothing, if it can't be reached.
func _take_job(new_job: Dictionary) -> bool:
	job = new_job
	job_progress = 0.0
	if job["kind"] == "rescue":
		job["patient"].rescuer = self  # a rescue is claimed on the patient, not a tile
	else:
		grid.claimed[job["tile"]] = self

	# Hauling: walk onto the item's tile. Rescuing: walk to the patient. Otherwise: the nearest side.
	var reached: bool
	if job["kind"] == "rescue":
		reached = _walk_to(job["patient"].position)
	elif job["kind"] == "haul":
		reached = _walk_to(grid.tile_to_screen(job["tile"]))
	else:
		reached = _walk_to_nearest(grid.work_spots(job))
	if not reached:
		_release_job()
		return false
	return true


## Lets go of the current job, so another worker can take it.
func _stop_working() -> void:
	_release_job()
	queue_redraw()


func _release_job() -> void:
	if not job.is_empty() and job["kind"] == "haul" and job["carrying"]:
		_put_down(job["item"])  # never lose an item: interrupted haulers put it down where they stand
	if not job.is_empty() and job["kind"] == "rescue":
		var patient: Node2D = job["patient"]
		if is_instance_valid(patient):
			if patient.carried_by == self:
				patient.carried_by = null  # set the patient down here
			if patient.rescuer == self:
				patient.rescuer = null
	if not job.is_empty() and grid.claimed.get(job["tile"]) == self:
		grid.claimed.erase(job["tile"])
	job = {}
	job_progress = 0.0


## Plans a path to a point. Returns false, and stays put, if there's no way there.
func _walk_to(point: Vector2) -> bool:
	var map: RID = get_world_2d().navigation_map
	var new_path: PackedVector2Array = NavigationServer2D.map_get_path(map, position, point, true,
		grid.nav_layer("troops", size))
	# The server returns the closest reachable point when the target can't be reached,
	# so check that the path really ends at the target.
	if new_path.is_empty() or new_path[new_path.size() - 1].distance_to(point) > radius:
		return false
	path = new_path
	return true


## Walks to whichever spot has the shortest walking path. Returns false if none can be reached.
func _walk_to_nearest(spots: PackedVector2Array) -> bool:
	var map: RID = get_world_2d().navigation_map
	var best_path := PackedVector2Array()
	var best_length := INF
	for spot in spots:
		var spot_on_ground: Vector2 = NavigationServer2D.map_get_closest_point(map, spot)  # snap onto walkable ground
		var candidate: PackedVector2Array = NavigationServer2D.map_get_path(map, position, spot_on_ground, true,
			grid.nav_layer("troops", size))
		if candidate.is_empty() or candidate[candidate.size() - 1].distance_to(spot_on_ground) > radius:
			continue  # can't get there
		var length := _path_length(candidate)
		if length < best_length:
			best_length = length
			best_path = candidate
	if best_path.is_empty():
		return false
	path = best_path
	return true


## Called when a hauler stops walking: either it just reached the item, or it reached storage.
func _haul_step() -> void:
	if not job["carrying"]:
		# At the item: pick it up and head for storage.
		job["item"] = grid.take_item(job["tile"])
		job["carrying"] = true
		queue_redraw()
		if not _walk_to(grid.tile_to_screen(job["drop"])):
			_release_job()  # can't get to storage; releasing puts the item down here
			queue_redraw()
			dispatcher.request()
		return
	# At storage: deliver it, and only now does it take effect.
	dungeon.receive_item(job["item"])
	add_fame(FAME_PER_JOB)
	record("hauls")
	job["carrying"] = false  # delivered, so releasing the job mustn't put it down again
	_release_job()
	queue_redraw()
	dispatcher.request()


## Called when a rescuer stops walking: either it just reached the patient, or it reached mycelium.
func _rescue_step() -> void:
	var patient: Node2D = job["patient"]
	if not job["carrying"]:
		patient.carried_by = self
		job["carrying"] = true
		if not _walk_to(grid.tile_to_screen(job["drop"])):
			_release_job()  # can't get there; releasing sets the patient down here
			dispatcher.request()
		return
	# At the mycelium: set the patient down to heal.
	patient.carried_by = null
	add_fame(FAME_PER_RESCUE)
	record("rescues")
	patient.position = position
	job["carrying"] = false
	_release_job()
	queue_redraw()
	dispatcher.request()


## True if the current job still makes sense. Rescues check the patient; everything else asks the grid.
func _job_still_exists() -> bool:
	if job["kind"] == "rescue":
		var patient: Node2D = job["patient"]
		return is_instance_valid(patient) and patient.downed
	return grid.job_still_exists(job)


## Puts an item on the floor here, or on the nearest free floor tile if this one already has one.
func _put_down(item: Dictionary) -> void:
	var here := get_tile()
	var spots: Array[Vector2i] = [here]
	for offset in grid.NEIGHBORS:
		spots.append(here + offset)
	for spot in spots:
		if grid.is_floor(spot) and not grid.items.has(spot):
			grid.drop_item(spot, item)
			return
	grid.drop_item(here, item)  # crowded on all sides; it's rare, so stack it here


## Total walking distance along a path, from the unit's position.
func _path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	var previous := position
	for point in points:
		total += previous.distance_to(point)
		previous = point
	return total


## A downed troop is injured: it drops what it's doing, and its death timer starts.
func _on_downed() -> void:
	record("times_injured")
	_stop_working()
	path = PackedVector2Array()
	set_selected(false)
	death_time_left = DEATH_TIME
	heal_time = 0.0
	dungeon.on_troop_injured()


## Injured, each frame: carried along, healing on mycelium, or running out of time.
func _process_injured(delta: float) -> void:
	if carried_by != null:
		if not is_instance_valid(carried_by):
			carried_by = null
		else:
			position = carried_by.position + Vector2(0, -radius)  # riding on the rescuer
			return
	if grid.has_mycelium(get_tile()):
		heal_time += delta
		if heal_time >= HEAL_TIME:
			_recover()
	else:
		death_time_left -= delta
		if death_time_left <= 0.0:
			_die()
			return
	queue_redraw()  # the healing or dying ring changes every frame


func _recover() -> void:
	downed = false
	health = max_health * RECOVERED_HEALTH
	dungeon.on_troop_healed()
	add_fame(FAME_FOR_SURVIVING)
	record("injuries_survived")
	queue_redraw()
	if can_dig:
		dispatcher.request()


func _die() -> void:
	dungeon.on_troop_died(type_id, is_named)  # named troops hurt more to lose
	remove_from_group("units")  # leaves the troop count, the roster and the dispatcher right away
	queue_free()


func _process(delta: float) -> void:
	if downed:
		_process_injured(delta)
		return
	_fight(delta)  # attacks any raider in range, even while walking
	if target == null:
		_bash_rival_door(delta)  # nothing to fight: break any rival door within reach
	service_time += delta
	if service_time >= 60.0:
		service_time -= 60.0
		add_fame(FAME_PER_MINUTE)
	if health < max_health and grid.has_mycelium(get_tile()):
		health = min(health + MYCELIUM_REGEN * delta, max_health)  # mycelium mends hurt fungi too
		queue_redraw()

	# A rescuer carries its patient along.
	if not job.is_empty() and job["kind"] == "rescue" and job["carrying"] and is_instance_valid(job["patient"]):
		job["patient"].position = position + Vector2(0, -radius)

	# The player may have cancelled this job (unmarked the rock or removed the blueprint).
	if not job.is_empty() and not _job_still_exists():
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

	if job["kind"] == "haul":
		_haul_step()
		return
	if job["kind"] == "rescue":
		_rescue_step()
		return

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
	add_fame(FAME_PER_DUG_CELL if done["kind"] == "dig" else FAME_PER_JOB)
	record("cells_dug" if done["kind"] == "dig" else "builds")
	if done["kind"] == "dig":
		grid.dig(done["tile"])
		# Tunnel in: step straight into the freshly dug tile, then look for the next job on arrival.
		path = PackedVector2Array([grid.tile_to_screen(done["tile"])])
	else:
		dispatcher.request()  # built it; free for the next job
