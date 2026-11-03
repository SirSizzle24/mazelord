extends Node2D
## The dungeon grid: stores which tiles are rock or floor, draws them as diamonds,
## and builds the navigation shape that units walk on.

const GRID_WIDTH := 60
const GRID_HEIGHT := 60
const TILE_WIDTH := 128   # diamond width in pixels
const TILE_HEIGHT := 128  # same as the width: squares turned 45°, no squash
const UNIT_RADIUS := 20.0  # how far units stay from rock; one unit size for now

enum Tile { ROCK, FLOOR }

signal layout_changed  # sent when floor is dug or a furnishing is finished, so rooms can be re-checked
signal marks_changed  # sent when dig marks are added or removed, so the fog can show them

const ROCK_COLOR := Color(0.35, 0.33, 0.30)
const FLOOR_COLOR := Color(0.75, 0.72, 0.65)
const LINE_COLOR := Color(0.2, 0.2, 0.2)
const MARKED_COLOR := Color(0.55, 0.38, 0.25)  # rock marked for digging
const DEPOSIT_COLOR := Color(0.30, 0.75, 0.95)  # a mana deposit, in rock or on open floor
const LAIR_COLOR := Color(0.80, 0.15, 0.15)  # a monster lair (a marker until combat exists)

# Cave generation. The map is new every game; each run prints its seed so a map can be replayed.
const FIXED_SEED := 0  # set to a printed seed to get that exact map again (0 = new map every run)
const CAVE_FILL := 0.45  # share of tiles that start open before smoothing
const CAVE_SMOOTHING := 5  # smoothing passes; more passes make smoother, larger caves
const MIN_POCKET := 6  # caves smaller than this many tiles are filled in as rock
const START_CENTER := Vector2i(30, 30)
const SAFE_RADIUS := 7  # solid rock kept around the start, so the first passage takes some digging
const DEPOSIT_COUNT := 8  # mana deposits scattered through caves and rock
const LAIR_COUNT := 3  # monster lairs, placed only in larger caves
const LAIR_MIN_CAVE := 25  # caves smaller than this many tiles don't get lairs
const FEATURE_MIN_DISTANCE := 12  # deposits and lairs stay at least this far from the start

const BUILD_TIME := 2.0  # seconds of work to build a furnishing
const SOLID_AT := 0.5  # fraction built at which a blocking furnishing starts blocking movement

const NO_TILE := Vector2i(-1, -1)  # stands for "no tile" when a search finds nothing
const NEIGHBORS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var tiles: Array = []  # tiles[x][y] holds a Tile value
var marked: Dictionary = {}  # rock tiles waiting to be dug; used as a set (tile -> true)
var furnishings: Array = []  # each one: {"id", "origin", "size", "color", "blocks", "progress", "solid", "built"}
var occupied: Dictionary = {}  # tile -> the furnishing covering it
var claimed: Dictionary = {}  # job tile -> the worker doing it, so two workers don't take the same job
var deposits: Dictionary = {}  # mana deposit tiles (used as a set)
var lairs: Dictionary = {}  # monster lair tiles (used as a set)
var starting_room: Array[Vector2i] = []  # the pre-dug room's tiles; the fog keeps it lit
var preview: Dictionary = {}  # the item about to be placed: {"origin", "size", "color", "valid"}, or empty
var nav_region := NavigationRegion2D.new()  # holds the walkable shape for units
var nav_dirty := false  # true when tiles changed and the walkable shape needs rebuilding
var nav_version := 0  # goes up with every rebuild, so units can tell the walkable shape changed


func _ready() -> void:
	for x in GRID_WIDTH:
		var column: Array = []
		for y in GRID_HEIGHT:
			column.append(Tile.ROCK)
		tiles.append(column)

	add_child(nav_region)
	_generate_caves()

	# A small pre-dug starting room in the middle of the map, as the onboarding design calls for.
	for x in range(START_CENTER.x - 1, START_CENTER.x + 2):
		for y in range(START_CENTER.y - 1, START_CENTER.y + 2):
			dig(Vector2i(x, y))
			starting_room.append(Vector2i(x, y))


## Carves natural caves into the rock with cellular automata: random noise, smoothed until it clumps
## into cave shapes. The biggest connected cave becomes the main labyrinth; smaller ones are pockets.
func _generate_caves() -> void:
	var rng := RandomNumberGenerator.new()
	if FIXED_SEED != 0:
		rng.seed = FIXED_SEED
	else:
		rng.randomize()
	print("Map seed: ", rng.seed, "  (set FIXED_SEED to this to replay this map)")

	# 1. Random fill. The outer edge always stays rock.
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var edge := x == 0 or y == 0 or x == GRID_WIDTH - 1 or y == GRID_HEIGHT - 1
			tiles[x][y] = Tile.ROCK if edge or rng.randf() >= CAVE_FILL else Tile.FLOOR

	# 2. Smoothing: a tile mostly surrounded by rock becomes rock; mostly surrounded by open, opens.
	for pass_number in CAVE_SMOOTHING:
		var next: Array = tiles.duplicate(true)  # read the old grid while writing the new one
		for x in range(1, GRID_WIDTH - 1):
			for y in range(1, GRID_HEIGHT - 1):
				var rock_around := 0
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if (dx != 0 or dy != 0) and tiles[x + dx][y + dy] == Tile.ROCK:
							rock_around += 1
				if rock_around >= 5:
					next[x][y] = Tile.ROCK
				elif rock_around <= 3:
					next[x][y] = Tile.FLOOR
		tiles = next

	# 3. Solid rock around the start.
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			if Vector2i(x, y).distance_to(START_CENTER) <= SAFE_RADIUS:
				tiles[x][y] = Tile.ROCK

	# 4. Fill in caves too small to matter, and keep the rest for placing lairs.
	var seen: Dictionary = {}
	var big_caves: Array = []
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var start := Vector2i(x, y)
			if seen.has(start) or tiles[x][y] != Tile.FLOOR:
				continue
			var cave := _connected_floor(start, seen)
			if cave.size() < MIN_POCKET:
				for tile in cave:
					tiles[tile.x][tile.y] = Tile.ROCK
			elif cave.size() >= LAIR_MIN_CAVE:
				big_caves.append(cave)

	# 5. Mana deposits anywhere away from the start, in caves or in the rock.
	while deposits.size() < DEPOSIT_COUNT:
		var tile := Vector2i(rng.randi_range(1, GRID_WIDTH - 2), rng.randi_range(1, GRID_HEIGHT - 2))
		if tile.distance_to(START_CENTER) >= FEATURE_MIN_DISTANCE:
			deposits[tile] = true

	# 6. Monster lairs on open floor in the larger caves, one cave each where possible.
	var tries := 0
	while lairs.size() < LAIR_COUNT and not big_caves.is_empty() and tries < 200:
		tries += 1  # a safety limit, in case no spot fits
		var cave: Array = big_caves[rng.randi_range(0, big_caves.size() - 1)]
		var tile: Vector2i = cave[rng.randi_range(0, cave.size() - 1)]
		if tile.distance_to(START_CENTER) >= FEATURE_MIN_DISTANCE and not deposits.has(tile):
			lairs[tile] = true
			if big_caves.size() > LAIR_COUNT - lairs.size():
				big_caves.erase(cave)  # spread lairs across caves while there are enough caves

	nav_dirty = true


## All floor tiles joined to start through shared sides (a flood fill, as rooms.gd uses).
func _connected_floor(start: Vector2i, seen: Dictionary) -> Array[Vector2i]:
	var cave: Array[Vector2i] = []
	var to_visit: Array[Vector2i] = [start]
	seen[start] = true
	while not to_visit.is_empty():
		var tile: Vector2i = to_visit.pop_back()
		cave.append(tile)
		for offset in NEIGHBORS:
			var next: Vector2i = tile + offset
			if is_in_bounds(next) and not seen.has(next) and tiles[next.x][next.y] == Tile.FLOOR:
				seen[next] = true
				to_visit.append(next)
	return cave


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


## Marks a rock tile to be dug by a worker. In fog, the player can't tell rock from a hidden passage,
## so hidden tiles can be marked whatever they really are (hidden = true); the fog drops marks that
## turn out to be on open floor once a troop sees them, so marking never gives a passage away.
func mark(tile: Vector2i, hidden: bool = false) -> void:
	if not is_in_bounds(tile) or marked.has(tile):
		return
	if hidden or tiles[tile.x][tile.y] == Tile.ROCK:
		marked[tile] = true
		queue_redraw()
		marks_changed.emit()


func is_marked(tile: Vector2i) -> bool:
	return marked.has(tile)


## Clears a dig mark.
func unmark(tile: Vector2i) -> void:
	if marked.erase(tile):
		queue_redraw()
		marks_changed.emit()


## True if a finished door stands on this tile. Doors divide rooms.
func is_door(tile: Vector2i) -> bool:
	return occupied.has(tile) and occupied[tile]["id"] == "door" and occupied[tile]["built"]


## True if the tile shares a side with a floor tile, so a worker can reach it to dig.
func has_floor_neighbor(tile: Vector2i) -> bool:
	for offset in NEIGHBORS:
		if is_floor(tile + offset):
			return true
	return false


## Every tile a furnishing covers, counting from its origin tile along the grid.
func footprint(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var tiles_covered: Array[Vector2i] = []
	for dx in size.x:
		for dy in size.y:
			tiles_covered.append(origin + Vector2i(dx, dy))
	return tiles_covered


## True if every tile under the footprint is open floor with nothing on it.
## needs_deposit is for items like the mana tap, which can only stand on a mana deposit.
func can_place(origin: Vector2i, size: Vector2i, needs_deposit: bool = false) -> bool:
	for tile in footprint(origin, size):
		if not is_floor(tile) or occupied.has(tile):
			return false
		if needs_deposit and not deposits.has(tile):
			return false
	return true


## Adds an unbuilt furnishing (a see-through ghost) for a worker to build later.
## Ghosts are walkable; a blocking furnishing turns solid once it's SOLID_AT built.
## rotation is in quarter turns (0 to 3), kept so later art can face the right way.
func place_blueprint(id: String, origin: Vector2i, size: Vector2i, color: Color, blocks: bool, rotation_steps: int = 0) -> void:
	var furnishing := {"id": id, "origin": origin, "size": size, "color": color, "blocks": blocks,
		"rotation": rotation_steps, "progress": 0.0, "solid": false, "built": false}
	furnishings.append(furnishing)
	for tile in footprint(origin, size):
		occupied[tile] = furnishing
	queue_redraw()


## The unbuilt furnishing covering a tile, or an empty dictionary if there isn't one.
func blueprint_at(tile: Vector2i) -> Dictionary:
	if occupied.has(tile) and not occupied[tile]["built"]:
		return occupied[tile]
	return {}


## Shows a faint preview of an item before it's placed; red if it can't go there.
func set_preview(origin: Vector2i, size: Vector2i, color: Color, valid: bool) -> void:
	var new_preview := {"origin": origin, "size": size, "color": color, "valid": valid}
	if new_preview == preview:
		return  # unchanged; skip redrawing the whole grid
	preview = new_preview
	queue_redraw()


func clear_preview() -> void:
	if not preview.is_empty():
		preview = {}
		queue_redraw()


## The furnishing covering a tile, built or not, or an empty dictionary if there isn't one.
func furnishing_at(tile: Vector2i) -> Dictionary:
	return occupied.get(tile, {})


## Takes a furnishing off the grid entirely, built or not.
func remove_furnishing(furnishing: Dictionary) -> void:
	furnishings.erase(furnishing)
	for tile in footprint(furnishing["origin"], furnishing["size"]):
		occupied.erase(tile)
	if furnishing["solid"]:
		nav_dirty = true  # its hole in the walkable shape closes up
	if furnishing["built"]:
		layout_changed.emit()  # rooms may change type
	queue_redraw()


## True if a job still exists: its rock is still marked, or its blueprint is still on the grid and unbuilt.
## The player can remove jobs while a worker is on its way or mid-job.
func job_still_exists(job: Dictionary) -> bool:
	if job["kind"] == "dig":
		return marked.has(job["tile"])
	return furnishings.has(job["furnishing"]) and not job["furnishing"]["built"]


## The middle of a furnishing, in screen position.
func footprint_center(furnishing: Dictionary) -> Vector2:
	var first: Vector2 = tile_to_screen(furnishing["origin"])
	var last: Vector2 = tile_to_screen(furnishing["origin"] + furnishing["size"] - Vector2i.ONE)
	return (first + last) / 2.0


## Adds build progress. Blocking furnishings turn solid at SOLID_AT. Returns true once fully built.
## Progress is stored on the furnishing, so an interrupted build can be finished by any worker.
func add_build_progress(furnishing: Dictionary, seconds: float) -> bool:
	furnishing["progress"] += seconds
	if furnishing["blocks"] and not furnishing["solid"] and furnishing["progress"] >= BUILD_TIME * SOLID_AT:
		furnishing["solid"] = true
		nav_dirty = true  # the walkable shape now needs a hole here
	if furnishing["progress"] >= BUILD_TIME:
		furnishing["built"] = true
		queue_redraw()
		layout_changed.emit()
		return true
	return false


## Every spot a worker could stand to work on a job: one per open floor tile touching the job's side,
## placed just inside that tile so the worker clears the rock or furnishing by its radius.
## The worker picks the one with the shortest walk.
func work_spots(job: Dictionary) -> PackedVector2Array:
	var spots := PackedVector2Array()
	var work_tiles: Array[Vector2i] = [job["tile"]]
	if job["kind"] == "build":
		work_tiles = footprint(job["furnishing"]["origin"], job["furnishing"]["size"])
	for tile in work_tiles:
		for offset in NEIGHBORS:
			var beside: Vector2i = tile + offset
			if work_tiles.has(beside) or not is_floor(beside):
				continue
			if occupied.has(beside) and occupied[beside]["blocks"]:
				continue  # don't stand where a furnishing is or will be solid
			var edge_middle := (tile_to_screen(tile) + tile_to_screen(beside)) / 2.0
			var inward := (tile_to_screen(beside) - edge_middle).normalized()
			spots.append(edge_middle + inward * (UNIT_RADIUS + 4.0))
	return spots


## Every job nobody has claimed yet: digging marked rock a worker can reach, and building blueprints.
## Each is {"kind", "tile", "furnishing", "position"}. For a build job, "tile" is the furnishing's
## origin, which identifies it; "position" is where the job is, for measuring distance.
func open_jobs() -> Array:
	var jobs: Array = []
	for tile in marked:
		if has_floor_neighbor(tile) and not claimed.has(tile):
			jobs.append({"kind": "dig", "tile": tile, "furnishing": {}, "position": tile_to_screen(tile)})
	for furnishing in furnishings:
		if not furnishing["built"] and not claimed.has(furnishing["origin"]):
			jobs.append({"kind": "build", "tile": furnishing["origin"], "furnishing": furnishing,
				"position": footprint_center(furnishing)})
	return jobs


## Turns a rock tile into floor. Does nothing for floor or out-of-bounds tiles.
func dig(tile: Vector2i) -> void:
	if marked.erase(tile):  # dug tiles are no longer waiting, even if there was no rock after all
		queue_redraw()
		marks_changed.emit()
	if is_in_bounds(tile) and tiles[tile.x][tile.y] == Tile.ROCK:
		tiles[tile.x][tile.y] = Tile.FLOOR
		nav_dirty = true  # the walkable shape is out of date
		queue_redraw()  # the data changed, so the picture must update
		layout_changed.emit()


## Builds the walkable shape from every floor tile, shrunk by UNIT_RADIUS so units keep clear of rock.
func rebuild_navigation() -> void:
	var start_time := Time.get_ticks_usec()

	var source := NavigationMeshSourceGeometryData2D.new()
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			if tiles[x][y] == Tile.FLOOR:
				source.add_traversable_outline(diamond(Vector2i(x, y)))
	# Solid furnishings cut holes in the walkable shape (ghosts stay walkable until SOLID_AT).
	for furnishing in furnishings:
		if furnishing["solid"]:
			for tile in footprint(furnishing["origin"], furnishing["size"]):
				source.add_obstruction_outline(diamond(tile))

	var nav_polygon := NavigationPolygon.new()
	nav_polygon.agent_radius = UNIT_RADIUS
	NavigationServer2D.bake_from_source_geometry_data(nav_polygon, source)
	nav_region.navigation_polygon = nav_polygon
	nav_version += 1

	var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
	print("Navigation rebuilt in %.2f ms" % elapsed_ms)  # temporary: measuring the cost


func _draw() -> void:
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var shape := diamond(Vector2i(x, y))
			draw_colored_polygon(shape, _ground_color(Vector2i(x, y)))

			var outline := shape.duplicate()
			outline.append(shape[0])  # back to the first corner to close the shape
			draw_polyline(outline, LINE_COLOR, 1.0)

	# Furnishings on top of the floor: see-through until built, solid once built.
	for furnishing in furnishings:
		var color: Color = furnishing["color"]
		if not furnishing["built"]:
			color.a = 0.35
		for tile in footprint(furnishing["origin"], furnishing["size"]):
			draw_colored_polygon(diamond(tile), color)

	# The placement preview: fainter than a ghost, and red where the item can't go.
	if not preview.is_empty():
		var preview_color: Color = preview["color"] if preview["valid"] else Color(1.0, 0.2, 0.2)
		preview_color.a = 0.18
		for tile in footprint(preview["origin"], preview["size"]):
			if is_in_bounds(tile):
				draw_colored_polygon(diamond(tile), preview_color)


## The color a tile shows right now, counting marks and finished furnishings. The fog remembers this.
func tile_color(tile: Vector2i) -> Color:
	if occupied.has(tile) and occupied[tile]["built"]:
		return occupied[tile]["color"]
	return _ground_color(tile)


## The color of the ground itself: marks first, then deposits and lairs, then rock or floor.
func _ground_color(tile: Vector2i) -> Color:
	if marked.has(tile):
		return MARKED_COLOR
	if deposits.has(tile):
		return DEPOSIT_COLOR if tiles[tile.x][tile.y] == Tile.FLOOR else DEPOSIT_COLOR.darkened(0.35)
	if lairs.has(tile):
		return LAIR_COLOR
	if tiles[tile.x][tile.y] == Tile.ROCK:
		return ROCK_COLOR
	return FLOOR_COLOR


## The four corners of a tile's diamond: top, right, bottom, left.
func diamond(tile: Vector2i) -> PackedVector2Array:
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
