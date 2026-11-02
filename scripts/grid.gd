extends Node2D
## The dungeon grid: stores which tiles are rock or floor, draws them as diamonds,
## and builds the navigation shape that units walk on.

const GRID_WIDTH := 20
const GRID_HEIGHT := 20
const TILE_WIDTH := 128   # diamond width in pixels
const TILE_HEIGHT := 128  # same as the width: squares turned 45°, no squash
const UNIT_RADIUS := 20.0  # how far units stay from rock; one unit size for now

enum Tile { ROCK, FLOOR }

const ROCK_COLOR := Color(0.35, 0.33, 0.30)
const FLOOR_COLOR := Color(0.75, 0.72, 0.65)
const LINE_COLOR := Color(0.2, 0.2, 0.2)
const MARKED_COLOR := Color(0.55, 0.38, 0.25)  # rock marked for digging

const NO_TILE := Vector2i(-1, -1)  # stands for "no tile" when a search finds nothing
const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var tiles: Array = []  # tiles[x][y] holds a Tile value
var marked: Dictionary = {}  # rock tiles waiting to be dug; used as a set (tile -> true)
var furnishings: Array = []  # each one: {"id", "origin", "size", "color", "built"}
var occupied: Dictionary = {}  # tile -> the furnishing covering it
var nav_region := NavigationRegion2D.new()  # holds the walkable shape for units
var nav_dirty := false  # true when tiles changed and the walkable shape needs rebuilding


func _ready() -> void:
	for x in GRID_WIDTH:
		var column: Array = []
		for y in GRID_HEIGHT:
			column.append(Tile.ROCK)
		tiles.append(column)

	add_child(nav_region)

	# A small pre-dug starting room, as the onboarding design calls for.
	for x in range(9, 12):
		for y in range(9, 12):
			dig(Vector2i(x, y))


func _process(_delta: float) -> void:
	# Rebuild at most once per frame, so dragging across many tiles costs one rebuild.
	# Wait until the navigation server has synced its map at least once (iteration 0 means
	# not yet); a mesh handed over before then is lost, which broke the starting room.
	var map_ready := NavigationServer2D.map_get_iteration_id(get_world_2d().navigation_map) > 0
	if nav_dirty and map_ready:
		nav_dirty = false
		rebuild_navigation()


## True if the tile is inside the grid.
func is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < GRID_WIDTH and tile.y >= 0 and tile.y < GRID_HEIGHT


## True if the tile is inside the grid and dug out.
func is_floor(tile: Vector2i) -> bool:
	return is_in_bounds(tile) and tiles[tile.x][tile.y] == Tile.FLOOR


## Marks a rock tile to be dug by a worker.
func mark(tile: Vector2i) -> void:
	if is_in_bounds(tile) and tiles[tile.x][tile.y] == Tile.ROCK and not marked.has(tile):
		marked[tile] = true
		queue_redraw()


func is_marked(tile: Vector2i) -> bool:
	return marked.has(tile)


## True if the tile shares a side with a floor tile, so a worker can reach it to dig.
func has_floor_neighbor(tile: Vector2i) -> bool:
	for offset in NEIGHBORS:
		if is_floor(tile + offset):
			return true
	return false


## The closest marked tile a worker could start digging now, or NO_TILE if there isn't one.
func nearest_diggable(from: Vector2) -> Vector2i:
	var best := NO_TILE
	var best_distance := INF
	for tile in marked:
		if has_floor_neighbor(tile):
			var distance := from.distance_to(tile_to_screen(tile))
			if distance < best_distance:
				best = tile
				best_distance = distance
	return best


## Every tile a furnishing covers, counting from its origin tile along the grid.
func footprint(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var tiles_covered: Array[Vector2i] = []
	for dx in size.x:
		for dy in size.y:
			tiles_covered.append(origin + Vector2i(dx, dy))
	return tiles_covered


## True if every tile under the footprint is open floor with nothing on it.
func can_place(origin: Vector2i, size: Vector2i) -> bool:
	for tile in footprint(origin, size):
		if not is_floor(tile) or occupied.has(tile):
			return false
	return true


## Adds an unbuilt furnishing (a see-through ghost) for a worker to build later.
func place_blueprint(id: String, origin: Vector2i, size: Vector2i, color: Color) -> void:
	var furnishing := {"id": id, "origin": origin, "size": size, "color": color, "built": false}
	furnishings.append(furnishing)
	for tile in footprint(origin, size):
		occupied[tile] = furnishing
	queue_redraw()


## Turns a rock tile into floor. Does nothing for floor or out-of-bounds tiles.
func dig(tile: Vector2i) -> void:
	if is_in_bounds(tile) and tiles[tile.x][tile.y] == Tile.ROCK:
		tiles[tile.x][tile.y] = Tile.FLOOR
		marked.erase(tile)  # dug tiles are no longer waiting
		nav_dirty = true  # the walkable shape is out of date
		queue_redraw()  # the data changed, so the picture must update


## Builds the walkable shape from every floor tile, shrunk by UNIT_RADIUS so units keep clear of rock.
func rebuild_navigation() -> void:
	var start_time := Time.get_ticks_usec()

	var source := NavigationMeshSourceGeometryData2D.new()
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			if tiles[x][y] == Tile.FLOOR:
				source.add_traversable_outline(_diamond(Vector2i(x, y)))

	var nav_polygon := NavigationPolygon.new()
	nav_polygon.agent_radius = UNIT_RADIUS
	NavigationServer2D.bake_from_source_geometry_data(nav_polygon, source)
	nav_region.navigation_polygon = nav_polygon

	var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
	print("Navigation rebuilt in %.2f ms" % elapsed_ms)  # temporary: measuring the cost


func _draw() -> void:
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var diamond := _diamond(Vector2i(x, y))
			var color: Color = FLOOR_COLOR
			if marked.has(Vector2i(x, y)):
				color = MARKED_COLOR
			elif tiles[x][y] == Tile.ROCK:
				color = ROCK_COLOR
			draw_colored_polygon(diamond, color)

			var outline := diamond.duplicate()
			outline.append(diamond[0])  # back to the first corner to close the shape
			draw_polyline(outline, LINE_COLOR, 1.0)

	# Furnishings on top of the floor: see-through until built, solid once built.
	for furnishing in furnishings:
		var color: Color = furnishing["color"]
		if not furnishing["built"]:
			color.a = 0.35
		for tile in footprint(furnishing["origin"], furnishing["size"]):
			draw_colored_polygon(_diamond(tile), color)


## The four corners of a tile's diamond: top, right, bottom, left.
func _diamond(tile: Vector2i) -> PackedVector2Array:
	var center := tile_to_screen(tile)
	return PackedVector2Array([
		center + Vector2(0, -TILE_HEIGHT / 2.0),
		center + Vector2(TILE_WIDTH / 2.0, 0),
		center + Vector2(0, TILE_HEIGHT / 2.0),
		center + Vector2(-TILE_WIDTH / 2.0, 0),
	])


## Tile coordinates -> the screen position of that tile's center.
func tile_to_screen(tile: Vector2i) -> Vector2:
	return Vector2(
		(tile.x - tile.y) * TILE_WIDTH / 2.0,
		(tile.x + tile.y) * TILE_HEIGHT / 2.0
	)


## A screen position -> the tile it falls inside. The reverse of tile_to_screen.
func screen_to_tile(point: Vector2) -> Vector2i:
	var a := point.x / (TILE_WIDTH / 2.0)
	var b := point.y / (TILE_HEIGHT / 2.0)
	return Vector2i(roundi((a + b) / 2.0), roundi((b - a) / 2.0))


## The rectangle on screen that the whole diamond-shaped grid fits inside.
func get_world_rect() -> Rect2:
	var left := -GRID_HEIGHT * TILE_WIDTH / 2.0
	var right := GRID_WIDTH * TILE_WIDTH / 2.0
	var top := -TILE_HEIGHT / 2.0
	var bottom := (GRID_WIDTH + GRID_HEIGHT - 1) * TILE_HEIGHT / 2.0
	return Rect2(left, top, right - left, bottom - top)
