extends Node2D
## Fog of war, drawn over the grid. Tiles never seen look like dim rock, so the unknown gives nothing away
## and can still be marked for digging. Tiles seen before show the last image you had, dimmed: changes
## out of sight don't appear until a troop looks again. Tiles in sight, the starting room, and finished
## rooms (plus the walls around them) are left clear, so the live grid shows through.
## The fog is a TileMapLayer of darkened ground tiles, and only cells whose visibility changed are updated.

const TileTextures = preload("res://scripts/tile_textures.gd")
const SurfaceMaterial = preload("res://scripts/surface_material.gd")
const SIGHT_RADIUS := 15  # cells (5 blocks) a troop can see in every direction
const UPDATE_INTERVAL := 0.2  # seconds between sight updates; every frame would be wasted work
const MEMORY_DARKEN := 0.30  # how much darker remembered tiles look than live ones
## How bright never-seen rock is, so a tunnel that runs into the unknown looks different from a real
## dead end (seen rock stays at memory brightness). Try 0.35 for "darker unknown", 0.05 for a black void.
const UNKNOWN_BRIGHTNESS := 0.25
## The frontier: never-seen cells right next to floor you know. They go darker still, fading into the
## walls around them, so a tunnel that leads into the unknown ends in a dark mouth, and a real dead end
## (seen rock) doesn't.
const FRONTIER_BRIGHTNESS := 0.05
const WALL_FACE_HEIGHT := 32.0  # pixels of front face along a wall's lower edge; taller looks taller
## The wall tiles, in atlas order: lit and remembered rock, lit and remembered deposit rock, and a mark.
enum Wall { ROCK, ROCK_DIM, DEPOSIT, DEPOSIT_DIM, MARKED }

@export var grid: Node2D
@export var rooms: Node

var layer := TileMapLayer.new()  # flat fog over the ground
var walls := TileMapLayer.new()  # rock with height, drawn inside each cell; only where rock is known
var marked_kind := 0  # the fog's extra tile: a mark at full brightness, so your marks always show
var memory: Dictionary = {}  # tile -> its ground kind when last seen
var memory_overlays: Dictionary = {}  # tile -> color of what stood on it when last seen (if anything)
var visible_tiles: Dictionary = {}  # tiles in sight right now (used as a set)
## One pixel per cell; the shader blends between cells smoothly. Red: in sight now. Green: ever seen.
## Blue: marked for digging (marks stay bright even in the unknown). Alpha: the frontier.
var vis_image: Image
var vis_texture: ImageTexture
var vis_dirty := false  # the image changed and needs sending to the graphics card
var timer := 0.0
var fog_enabled := true  # debug: switch the fog off to see the whole map


func _ready() -> void:
	# The fog's tiles: every ground kind darkened, plus one bright mark.
	var colors: Array = []
	for color in grid.ground_colors():
		colors.append(color.darkened(MEMORY_DARKEN))
	marked_kind = colors.size()
	colors.append(grid.MARKED_TINT)
	layer.tile_set = TileTextures.build(colors, grid.TILE_WIDTH)
	vis_image = Image.create(grid.GRID_WIDTH, grid.GRID_HEIGHT, false, Image.FORMAT_RGBA8)  # starts all zero
	vis_texture = ImageTexture.create_from_image(vis_image)
	layer.material = SurfaceMaterial.make(null, "floor")  # remembered ground keeps its texture, dimmed
	_add_fog_settings(layer.material, 1)
	layer.show_behind_parent = true  # under the remembered furnishings this node draws
	add_child(layer)
	layer.position = grid.tile_to_screen(Vector2i.ZERO) - layer.map_to_local(Vector2i.ZERO)

	# Walls stay inside their own cells, so they never cover troops or neighbors, and need no depth sorting.
	var rock: Color = Color.WHITE  # tints: the wall textures carry the color
	var deposit: Color = grid.DEPOSIT_TINT
	var wall_art: Dictionary = TileTextures.build_walls([rock, rock.darkened(MEMORY_DARKEN), deposit,
		deposit.darkened(MEMORY_DARKEN), grid.MARKED_TINT], grid.TILE_WIDTH, WALL_FACE_HEIGHT)
	walls.tile_set = wall_art["tile_set"]
	walls.material = SurfaceMaterial.make(wall_art["mask"], "wall_top")  # tops and faces textured separately
	_add_fog_settings(walls.material, 2)
	add_child(walls)
	walls.position = layer.position
	grid.cell_dug.connect(_on_cell_dug)

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
	vis_texture.update(vis_image)
	vis_dirty = false


## Hands the shader what it needs for smooth fog edges. mode 1 fades the flat fog; mode 2 dims walls.
func _add_fog_settings(material: ShaderMaterial, mode: int) -> void:
	material.set_shader_parameter("fog_mode", mode)
	material.set_shader_parameter("vis_tex", vis_texture)
	material.set_shader_parameter("grid_cells", Vector2(grid.GRID_WIDTH, grid.GRID_HEIGHT))
	material.set_shader_parameter("cell_size", float(grid.TILE_WIDTH))
	material.set_shader_parameter("memory_brightness", 1.0 - MEMORY_DARKEN)
	material.set_shader_parameter("unknown_brightness", UNKNOWN_BRIGHTNESS)
	material.set_shader_parameter("frontier_brightness", FRONTIER_BRIGHTNESS)


func _remember(tile: Vector2i) -> void:
	if not grid.is_in_bounds(tile):
		return
	var kind: int = grid.ground_kind(tile)
	var changed: bool = memory.get(tile, -1) != kind
	memory[tile] = kind
	_set_vis(tile, 1, 1.0)  # seen
	if changed:
		# Only when the memory really changed: this runs for every cell in sight, several times a second.
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var near := tile + Vector2i(dx, dy)
				if grid.is_in_bounds(near):
					_set_vis(near, 3, 1.0 if _is_frontier(near) else 0.0)
	var overlay: Color = grid.overlay_color(tile)
	if overlay.a > 0.0:
		memory_overlays[tile] = overlay
	else:
		memory_overlays.erase(tile)


## Updates one cell: the flat fog (clear if in sight; otherwise the remembered ground, dim rock if never
## seen, or a bright mark), and its wall.
func _paint(tile: Vector2i) -> void:
	_paint_wall(tile)
	# Every cell keeps a fog tile, even in sight: the shader makes it see-through there, fading smoothly
	# at the edge of sight instead of switching per cell.
	var kind: int = memory.get(tile, grid.Ground.ROCK)
	if grid.is_marked(tile):
		kind = marked_kind
	layer.set_cell(tile, 0, Vector2i(kind, 0))


## A wall stands wherever rock is known or nothing is known: bright in sight, dim from memory. The
## unknown is solid rock with no faces, so a hidden cave looks the same as the rock around it.
func _paint_wall(tile: Vector2i) -> void:
	var in_sight := visible_tiles.has(tile) or not fog_enabled
	var kind: int = grid.ground_kind(tile) if in_sight else memory.get(tile, grid.Ground.ROCK)
	var is_rock: bool = kind == grid.Ground.ROCK or kind == grid.Ground.DEPOSIT_ROCK \
		or (kind == grid.Ground.MARKED and not grid.is_floor(tile) if in_sight else kind == grid.Ground.MARKED)
	_set_vis(tile, 2, 1.0 if grid.is_marked(tile) else 0.0)
	if not is_rock:
		walls.erase_cell(tile)
		return
	var wall: int
	if grid.is_marked(tile):
		wall = Wall.MARKED  # your own marks always show
	elif kind == grid.Ground.DEPOSIT_ROCK:
		wall = Wall.DEPOSIT  # dimmed out of sight by the shader, smoothly
	else:
		wall = Wall.ROCK
	# Faces only where they face floor you know about: lower-left looks at (x, y + 1), lower-right at
	# (x + 1, y), and the inside-corner piece at the diagonal (x + 1, y + 1). The atlas row is the
	# bit flag of which show (1 left, 2 right, 4 corner).
	var faces := 0
	if _known_floor(tile + Vector2i(0, 1)):
		faces += 1
	if _known_floor(tile + Vector2i(1, 0)):
		faces += 2
	if _known_floor(tile + Vector2i(1, 1)):
		faces += 4
	walls.set_cell(tile, 0, Vector2i(wall, faces))


## True if this cell has never been seen but touches floor you know about (sides or corners).
func _is_frontier(tile: Vector2i) -> bool:
	if memory.has(tile) or not fog_enabled:
		return false
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var kind: int = memory.get(tile + Vector2i(dx, dy), -1)
			if kind == grid.Ground.FLOOR or kind == grid.Ground.DEPOSIT_FLOOR or kind == grid.Ground.LAIR:
				return true
	return false


## Sets one channel of a cell's pixel in the visibility image (0 in sight, 1 seen, 2 marked).
func _set_vis(tile: Vector2i, channel: int, value: float) -> void:
	# (0 in sight, 1 seen, 2 marked, 3 frontier)
	var pixel := vis_image.get_pixelv(tile)
	if pixel[channel] == value:
		return
	pixel[channel] = value
	vis_image.set_pixelv(tile, pixel)
	vis_dirty = true


## True if you know this cell is open floor: live in sight, or remembered. Unknown counts as rock, so
## a wall's face never gives away a hidden cave.
func _known_floor(tile: Vector2i) -> bool:
	if not grid.is_in_bounds(tile):
		return false
	if visible_tiles.has(tile) or not fog_enabled:
		return grid.is_floor(tile)
	var kind: int = memory.get(tile, -1)
	return kind == grid.Ground.FLOOR or kind == grid.Ground.DEPOSIT_FLOOR or kind == grid.Ground.LAIR


## Redraws the cell and the three walls whose faces look at it (up-left, up-right, and straight up on
## screen), since what they show depends on this cell.
func _paint_with_neighbors(tile: Vector2i) -> void:
	_paint(tile)
	for wall_cell in [tile - Vector2i(0, 1), tile - Vector2i(1, 0), tile - Vector2i(1, 1)]:
		if grid.is_in_bounds(wall_cell):
			_paint_wall(wall_cell)


## Rock became floor. In sight, the wall comes down now; out of sight, the remembered wall stays
## until a troop looks again (the last-image rule).
func _on_cell_dug(tile: Vector2i) -> void:
	if visible_tiles.has(tile) or not fog_enabled:
		_remember(tile)
		_paint_with_neighbors(tile)


func _process(delta: float) -> void:
	if vis_dirty:
		vis_texture.update(vis_image)  # send changed visibility, memory and marks to the graphics card
		vis_dirty = false
	timer += delta
	if timer < UPDATE_INTERVAL:
		return
	timer = 0.0

	var now: Dictionary = {}
	for unit in get_tree().get_nodes_in_group("units"):
		_add_sight(grid.screen_to_tile(unit.position), now)
	_add_walls_of_seen_floor(now)
	# The starting room and every finished room stay lit, walls included.
	_add_lit(grid.starting_room, now)
	for room in rooms.rooms:
		if room["type"] != "":
			_add_lit(room["tiles"].keys(), now)
	_add_walls_behind(now)

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
		_paint_with_neighbors(tile)
		_set_vis(tile, 0, 1.0 if now.has(tile) else 0.0)
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
	for x in grid.GRID_WIDTH:
		for y in grid.GRID_HEIGHT:
			var tile := Vector2i(x, y)
			# With the fog off, everything counts as in sight and seen.
			var lit := 1.0 if not enabled or visible_tiles.has(tile) else 0.0
			var seen := 1.0 if not enabled or memory.has(tile) else 0.0
			var mark: float = 1.0 if grid.is_marked(tile) else 0.0
			var edge: float = 1.0 if _is_frontier(tile) else 0.0
			vis_image.set_pixelv(tile, Color(lit, seen, mark, edge))
	vis_dirty = true
	layer.visible = enabled  # hide the flat fog, but keep the walls
	for x in grid.GRID_WIDTH:
		for y in grid.GRID_HEIGHT:
			_paint_wall(Vector2i(x, y))  # with the fog off, every rock cell shows its wall
	queue_redraw()


## Seeing a floor cell means seeing the rock around it (sides and corners): rays can slip past the
## corner cells of a diagonal tunnel. Only rock is added, so an opening into an unseen cave stays dark.
func _add_walls_behind(into: Dictionary) -> void:
	for tile in into.keys():  # a copy: the loop adds to into
		if not grid.is_floor(tile):
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var near: Vector2i = tile + Vector2i(dx, dy)
				if grid.is_in_bounds(near) and not grid.is_floor(near):
					into[near] = true


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


## If you can see a floor cell, you can see the walls right around it. Rays move in steps and can slip
## past a wall cell diagonally, leaving a gap of unseen wall along a tunnel you can see the whole floor of.
func _add_walls_of_seen_floor(into: Dictionary) -> void:
	var walls_seen: Array[Vector2i] = []
	for tile in into:
		if not grid.is_floor(tile):
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var near: Vector2i = tile + Vector2i(dx, dy)
				if grid.is_in_bounds(near) and not into.has(near) and not grid.is_floor(near):
					walls_seen.append(near)
	for tile in walls_seen:
		into[tile] = true


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
	if not fog_enabled:
		return
	for tile in memory_overlays:
		if not visible_tiles.has(tile):
			var remembered: Color = memory_overlays[tile]
			draw_colored_polygon(grid.diamond(tile), remembered.darkened(MEMORY_DARKEN))
