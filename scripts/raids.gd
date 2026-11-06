extends Node
## Raids: a visible countdown, then a wave of raiders from the tunnels at the labyrinth's edge,
## heading for your core. A raid ends when every raider is downed (repelled), or after the raiders
## retreat: once one reaches the core and takes your mana, or when time runs out.
## Each raid is one raider bigger than the last, until combat score and lore decide raid size.

const FIRST_RAID := 240.0  # seconds of play before the first raid
const RAID_INTERVAL := 240.0  # seconds between the end of one raid and the next
const RAID_LENGTH := 300.0  # about five minutes, as designed
const FIRST_SIZE := 2
const CORE_RESERVE := 20  # mana raiders can never take: a big loss hurts, but doesn't end you
const RESULT_TIME := 8.0  # seconds a raid's result stays on screen

@export var dungeon: Node
@export var grid: Node2D
@export var fog: Node2D
@export var raider_scene: PackedScene
@export var units_parent: Node2D
@export var raid_label: Label

var countdown := FIRST_RAID
var raid_size := FIRST_SIZE
var active := false
var raid_time_left := 0.0
var core_taken := false
var lost_mana := 0
var result_text := ""
var result_time_left := 0.0


## Debug: starts the next raid now.
func raid_now() -> void:
	if not active:
		countdown = 0.0


func _process(delta: float) -> void:
	if active:
		_run_raid(delta)
	else:
		countdown -= delta
		if countdown <= 0.0:
			_start_raid()
	_update_label(delta)


func _start_raid() -> void:
	active = true
	raid_time_left = RAID_LENGTH
	core_taken = false
	var entry := _entry_point()
	for i in raid_size:
		var raider: Node2D = raider_scene.instantiate()
		raider.grid = grid
		raider.fog = fog
		raider.set_stats(dungeon.RAIDER_STATS)
		raider.position = entry + Vector2.from_angle(TAU * i / raid_size) * 30.0  # a little apart
		raider.exit_point = entry
		units_parent.add_child(raider)


## Where this raid comes in: the end of a random edge tunnel, or (on a map without one) a floor
## tile far from the core.
func _entry_point() -> Vector2:
	var options: Array[Vector2i] = []
	for exit in grid.edge_exits:
		if grid.is_floor(exit):
			options.append(exit)
	if options.is_empty():
		for x in grid.GRID_WIDTH:
			for y in grid.GRID_HEIGHT:
				var tile := Vector2i(x, y)
				if grid.is_floor(tile) and tile.distance_to(grid.START_CENTER) > 60:
					options.append(tile)
	return grid.tile_to_screen(options.pick_random())


func _run_raid(delta: float) -> void:
	raid_time_left -= delta
	var raiders := get_tree().get_nodes_in_group("raiders")
	var standing: Array = []
	for raider in raiders:
		if not raider.is_queued_for_deletion() and not raider.downed:
			standing.append(raider)

	# A raider at the core takes all your mana but the reserve, and the whole raid turns back.
	if not core_taken:
		for raider in standing:
			if raider.position.distance_to(raider.core_position()) < raider.ARRIVE_DISTANCE:
				core_taken = true
				lost_mana = max(dungeon.mana - CORE_RESERVE, 0)
				dungeon.add_mana(-lost_mana)
				raider.carrying_loot = true
				for other in standing:
					other.retreat()
				break

	if raid_time_left <= 0.0:
		for raider in standing:
			if not raider.retreating:
				raider.retreat()  # out of time: they leave with whatever they took

	if standing.is_empty():
		if core_taken:
			_end_raid("The core was raided: %d mana lost." % lost_mana)
		elif raid_time_left <= 0.0:
			_end_raid("The raiders withdrew.")
		else:
			_end_raid("Raid repelled!")


func _end_raid(text: String) -> void:
	active = false
	for unit in get_tree().get_nodes_in_group("units"):
		if not unit.downed:
			unit.add_fame(unit.FAME_FOR_SURVIVING)  # on its feet when the raid ended
			unit.record("raids_survived")
	for raider in get_tree().get_nodes_in_group("raiders"):
		raider.queue_free()  # clear away downed raiders too
	raid_size += 1
	countdown = RAID_INTERVAL
	result_text = text
	result_time_left = RESULT_TIME


func _update_label(delta: float) -> void:
	if result_time_left > 0.0:
		result_time_left -= delta
		raid_label.text = result_text
	elif active:
		var standing := 0
		for raider in get_tree().get_nodes_in_group("raiders"):
			if not raider.downed:
				standing += 1
		raid_label.text = "RAID! %s left, %d raiders standing" % [_clock(raid_time_left), standing]
	else:
		raid_label.text = "Next raid in %s (%d raiders)" % [_clock(countdown), raid_size]


func _clock(seconds: float) -> String:
	var whole: int = max(ceili(seconds), 0)
	return "%d:%02d" % [whole / 60, whole % 60]
