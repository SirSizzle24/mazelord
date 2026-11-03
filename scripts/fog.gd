extends Node2D
## Fog of war, drawn over the grid. Tiles never seen look like dim rock, so the unknown gives nothing away
## and can still be marked for digging. Tiles seen before show the last image you had, dimmed: changes
## out of sight don't appear until a troop looks again. Tiles in sight, the starting room, and finished
## rooms (plus the walls around them) are left clear, so the live grid shows through.

const SIGHT_RADIUS := 5  # tiles a troop can see in every direction
const UPDATE_INTERVAL := 0.2  # seconds between sight updates; every frame would be wasted work
const MEMORY_DARKEN := 0.55  # how much darker remembered tiles look than live ones

@export var grid: Node2D
@export var rooms: Node

var memory: Dictionary = {}  # tile -> its color when last seen
var visible_tiles: Dictionary = {}  # tiles in sight right now (used as a set)
var timer := 0.0
var fog_enabled := true  # debug: switch the fog off to see the whole map


func _ready() -> void:
	grid.marks_changed.connect(queue_redraw)  # marks show through the fog, so redraw when they change
	# Only the starting room, and the rock around it, start out known. (Not every floor tile:
	# the caves are floor too, and remembering them would reveal the whole labyrinth.)
	for tile in grid.starting_room:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				_remember(tile + Vector2i(dx, dy))
	queue_redraw()


func _remember(tile: Vector2i) -> void:
	if grid.is_in_bounds(tile):
		memory[tile] = grid.tile_color(tile)


func _process(delta: float) -> void:
	timer += delta
	if timer < UPDATE_INTERVAL:
		return
	timer = 0.0

	var now: Dictionary = {}
	for unit in get_tree().get_nodes_in_group("units"):
		_add_sight(grid.screen_to_tile(unit.position), now)
	# The starting room and every finished room stay lit, walls included.
	_add_lit(grid.starting_room, now)
	for room in rooms.rooms:
		if room["type"] != "":
			_add_lit(room["tiles"].keys(), now)

	for tile in now:
		_remember(tile)  # keep the memory fresh while it's in view
		if grid.is_marked(tile) and grid.is_floor(tile):
			grid.unmark(tile)  # a mark made in the fog turned out to be on open floor

	# Redraw only when what's in sight changed; redrawing 3,600 tiles for nothing is wasteful.
	if now != visible_tiles:
		visible_tiles = now
		queue_redraw()


## True if the player has ever seen this tile, or sees it now.
func is_known(tile: Vector2i) -> bool:
	return not fog_enabled or memory.has(tile) or visible_tiles.has(tile)


## Debug: hides or shows the fog. With it off, every tile counts as known.
func set_fog_enabled(enabled: bool) -> void:
	fog_enabled = enabled
	visible = enabled


## Adds tiles and the ring of tiles around them, so a lit room's walls show too.
func _add_lit(room_tiles: Array, into: Dictionary) -> void:
	for tile in room_tiles:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var near: Vector2i = tile + Vector2i(dx, dy)
				if grid.is_in_bounds(near):
					into[near] = true


## Adds every tile within SIGHT_RADIUS of center that has a clear line of sight.
func _add_sight(center: Vector2i, into: Dictionary) -> void:
	for dx in range(-SIGHT_RADIUS, SIGHT_RADIUS + 1):
		for dy in range(-SIGHT_RADIUS, SIGHT_RADIUS + 1):
			if dx * dx + dy * dy > SIGHT_RADIUS * SIGHT_RADIUS:
				continue  # outside the circle
			var tile := center + Vector2i(dx, dy)
			if grid.is_in_bounds(tile) and _line_clear(center, tile):
				into[tile] = true


## True if nothing blocks sight between two tiles. Steps along the straight line between them and
## checks each tile it passes; any rock in between blocks it. The end tile can be rock: you see walls.
func _line_clear(from: Vector2i, to: Vector2i) -> bool:
	var steps: int = max(abs(to.x - from.x), abs(to.y - from.y))
	for i in range(1, steps):
		var point := Vector2(from).lerp(Vector2(to), float(i) / steps)
		if not grid.is_floor(Vector2i(roundi(point.x), roundi(point.y))):
			return false
	return true


func _draw() -> void:
	for x in grid.GRID_WIDTH:
		for y in grid.GRID_HEIGHT:
			var tile := Vector2i(x, y)
			if visible_tiles.has(tile):
				continue  # in sight: let the live grid show
			# Never seen: dim rock, the same as remembered rock, so the unknown gives nothing away.
			var remembered: Color = memory.get(tile, grid.ROCK_COLOR)
			if grid.is_marked(tile):
				remembered = grid.MARKED_COLOR  # your own marks always show, so you can see what you queued
			draw_colored_polygon(grid.diamond(tile), remembered.darkened(MEMORY_DARKEN))
