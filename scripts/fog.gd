extends Node2D
## Fog of war, drawn over the grid. Tiles never seen look like dim rock, so the unknown gives nothing away
## and can still be marked for digging. Tiles seen before show the last image you had, dimmed: changes
## out of sight don't appear until a troop looks again. Tiles in sight, the starting room, and finished
## rooms (plus the walls around them) are left clear, so the live grid shows through.
## The fog is a TileMapLayer of darkened ground tiles, and only cells whose visibility changed are updated.

const TileTextures = preload("res://scripts/tile_textures.gd")
const SIGHT_RADIUS := 15  # cells (5 blocks) a troop can see in every direction
const UPDATE_INTERVAL := 0.2  # seconds between sight updates; every frame would be wasted work
const MEMORY_DARKEN := 0.55  # how much darker remembered tiles look than live ones

@export var grid: Node2D
@export var rooms: Node

var layer := TileMapLayer.new()
var marked_kind := 0  # the fog's extra tile: a mark at full brightness, so your marks always show
var memory: Dictionary = {}  # tile -> its ground kind when last seen
var memory_overlays: Dictionary = {}  # tile -> color of what stood on it when last seen (if anything)
var visible_tiles: Dictionary = {}  # tiles in sight right now (used as a set)
var timer := 0.0
var fog_enabled := true  # debug: switch the fog off to see the whole map


func _ready() -> void:
	# The fog's tiles: every ground kind darkened, plus one bright mark.
	var colors: Array = []
	for color in grid.ground_colors():
		colors.append(color.darkened(MEMORY_DARKEN))
	marked_kind = colors.size()
	colors.append(grid.MARKED_COLOR)
	layer.tile_set = TileTextures.build(colors, grid.TILE_WIDTH)
	layer.show_behind_parent = true  # under the remembered furnishings this node draws
	add_child(layer)
	layer.position = grid.tile_to_screen(Vector2i.ZERO) - layer.map_to_local(Vector2i.ZERO)

	grid.marks_changed.connect(_paint)  # marks show through the fog
	# Only the starting room, and the rock around it, start out known. (Not every floor tile:
	# the caves are floor too, and remembering them would reveal the whole labyrinth.)
	for tile in grid.starting_room:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				_remember(tile + Vector2i(dx, dy))
	for x in grid.GRID_WIDTH:
		for y in grid.GRID_HEIGHT:
			_paint(Vector2i(x, y))


func _remember(tile: Vector2i) -> void:
	if not grid.is_in_bounds(tile):
		return
	memory[tile] = grid.ground_kind(tile)
	var overlay: Color = grid.overlay_color(tile)
	if overlay.a > 0.0:
		memory_overlays[tile] = overlay
	else:
		memory_overlays.erase(tile)


## Updates one fog cell: clear if in sight; otherwise the remembered ground (dim rock if never seen),
## or a bright mark if you've marked it.
func _paint(tile: Vector2i) -> void:
	if visible_tiles.has(tile):
		layer.erase_cell(tile)
		return
	var kind: int = memory.get(tile, grid.Ground.ROCK)
	if grid.is_marked(tile):
		kind = marked_kind
	layer.set_cell(tile, 0, Vector2i(kind, 0))


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

	# Only cells that came into or went out of sight change.
	var changed: Array = []
	for tile in now:
		if not visible_tiles.has(tile):
			changed.append(tile)
	for tile in visible_tiles:
		if not now.has(tile):
			changed.append(tile)
	if changed.is_empty():
		return
	visible_tiles = now
	for tile in changed:
		_paint(tile)
	queue_redraw()  # remembered furnishings and items may have come into or out of view


## True if the player has ever seen this tile, or sees it now.
func is_known(tile: Vector2i) -> bool:
	return not fog_enabled or memory.has(tile) or visible_tiles.has(tile)


## True if a troop can see this tile right now (always, with the fog off). Raiders use it to hide.
func is_in_sight(tile: Vector2i) -> bool:
	return not fog_enabled or visible_tiles.has(tile)


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


## Adds every tile a troop at center can see, by casting rays: one ray from the center to each cell on
## the edge of the sight square, marking cells as it goes and stopping at the first rock (which is seen:
## you see walls) or at SIGHT_RADIUS. Far cheaper than checking a separate line to every cell in range,
## which matters now that the radius is three times bigger.
func _add_sight(center: Vector2i, into: Dictionary) -> void:
	into[center] = true
	for i in range(-SIGHT_RADIUS, SIGHT_RADIUS + 1):
		for edge in [Vector2i(i, -SIGHT_RADIUS), Vector2i(i, SIGHT_RADIUS), Vector2i(-SIGHT_RADIUS, i), Vector2i(SIGHT_RADIUS, i)]:
			_cast_ray(center, center + edge, into)


func _cast_ray(from: Vector2i, to: Vector2i, into: Dictionary) -> void:
	var steps: int = max(abs(to.x - from.x), abs(to.y - from.y))
	for i in range(1, steps + 1):
		var point := Vector2(from).lerp(Vector2(to), float(i) / steps)
		var tile := Vector2i(roundi(point.x), roundi(point.y))
		if not grid.is_in_bounds(tile) or Vector2(tile - from).length() > SIGHT_RADIUS:
			return
		into[tile] = true
		if not grid.is_floor(tile):
			return  # rock: seen, but blocks everything beyond it


## Remembered furnishings and items, darkened, on top of the fog tiles.
func _draw() -> void:
	for tile in memory_overlays:
		if not visible_tiles.has(tile):
			var remembered: Color = memory_overlays[tile]
			draw_colored_polygon(grid.diamond(tile), remembered.darkened(MEMORY_DARKEN))
