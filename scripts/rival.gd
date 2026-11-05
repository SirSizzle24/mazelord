extends Node
## The rival dungeon: spawns its guards and workers, and lets your troops loot its core once.
## Loot spills onto the floor around the core as items, for your workers to haul home.

const GuardScript = preload("res://scripts/guard.gd")
const RivalWorkerScript = preload("res://scripts/rival_worker.gd")
const GUARDS_INSIDE := 2
const RIVAL_WORKERS := 2
const LOOT := ["mana_cache", "mana_cache", "food_cache", "treasure"]
const LOOT_DISTANCE := 90.0  # how close one of your troops must get to the core
const MESSAGE_TIME := 6.0

@export var grid: Node2D
@export var dungeon: Node
@export var fog: Node2D
@export var units_parent: Node2D
@export var message_label: Label

var looted := false
var message_left := 0.0


func _ready() -> void:
	message_label.visible = false
	var core: Vector2 = grid.tile_to_screen(grid.rival_core)
	for i in GUARDS_INSIDE:
		_spawn(GuardScript, dungeon.GUARD_STATS, core + Vector2.from_angle(PI * i) * 90.0)
	for door_tile in grid.rival_doors:
		var door_center: Vector2i = door_tile + Vector2i(1, 1)
		var outside: Vector2i = door_center + (door_center - grid.rival_core).sign() * grid.BLOCK  # just past the door
		_spawn(GuardScript, dungeon.GUARD_STATS, grid.tile_to_screen(outside))
	for i in RIVAL_WORKERS:
		var worker := _spawn(RivalWorkerScript, dungeon.RIVAL_WORKER_STATS, core + Vector2(45.0 * i, 60.0))
		worker.home = worker.position


func _spawn(script: GDScript, stats: Dictionary, at: Vector2) -> Node2D:
	var fighter: Node2D = script.new()
	fighter.grid = grid
	fighter.fog = fog
	fighter.set_stats(stats)
	fighter.position = at
	if "post" in fighter:
		fighter.post = at
	units_parent.add_child.call_deferred(fighter)  # deferred: Main is still setting up its children
	return fighter


func _process(delta: float) -> void:
	if message_left > 0.0:
		message_left -= delta
		if message_left <= 0.0:
			message_label.visible = false
	if looted:
		return
	var core: Vector2 = grid.tile_to_screen(grid.rival_core)
	for unit in get_tree().get_nodes_in_group("units"):
		if not unit.downed and unit.position.distance_to(core) < LOOT_DISTANCE:
			_loot()
			return


## Spills the rival's stores onto free floor around its core, for your workers to haul home.
func _loot() -> void:
	looted = true
	var spots: Array[Vector2i] = []
	for tile in grid.rival_room:
		if not grid.items.has(tile) and not grid.occupied.has(tile):
			spots.append(tile)
	spots.sort_custom(func(a, b): return a.distance_to(grid.rival_core) < b.distance_to(grid.rival_core))
	for i in min(LOOT.size(), spots.size()):
		grid.drop_item(spots[i], {"kind": LOOT[i], "lore_index": 0})
	message_label.text = "The rival's core is looted! Workers can haul the spoils home."
	message_label.visible = true
	message_left = MESSAGE_TIME
