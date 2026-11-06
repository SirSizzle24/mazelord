extends Node2D
## The dungeon grid: stores which tiles are rock or floor, draws them as diamonds,
## and builds the navigation shape that units walk on.
##
## Naming: in the code, a "tile" is one grid cell (64 px, a sub-tile in the design). A 3 x 3 group of
## cells, what the design calls a tile, is a "block" here. Digging, building and features snap to blocks.

const BLOCK := 3  # cells per block side
const GRID_WIDTH := 180  # 60 blocks
const GRID_HEIGHT := 180
const TILE_WIDTH := 64   # one cell's diamond width in pixels
const TILE_HEIGHT := 64  # same as the width: squares turned 45°, no squash
const UNIT_RADIUS := 20.0  # how far units stay from rock; one unit size for now

enum Tile { ROCK, FLOOR }
## What each tile looks like on the ground layer: one placeholder texture per kind.
enum Ground { ROCK, FLOOR, MARKED, DEPOSIT_ROCK, DEPOSIT_FLOOR, LAIR }

const TileTextures = preload("res://scripts/tile_textures.gd")
const SurfaceMaterial = preload("res://scripts/surface_material.gd")

signal layout_changed  # sent when floor is dug or a furnishing is finished, so rooms can be re-checked
signal marks_changed(tile: Vector2i)  # sent when a dig mark is added or removed, so the fog can show it
signal cell_dug(tile: Vector2i)  # sent when rock becomes floor, so walls can update

const ROCK_COLOR := Color(0.35, 0.33, 0.30)
const FLOOR_COLOR := Color(0.75, 0.72, 0.65)
const MARKED_COLOR := Color(0.55, 0.38, 0.25)  # rock marked for digging
const DEPOSIT_COLOR := Color(0.30, 0.75, 0.95)  # a mana deposit, in rock or on open floor
const LAIR_COLOR := Color(0.80, 0.15, 0.15)  # a monster lair (a marker until combat exists)
# Tints for textured surfaces (see ground_colors): white leaves a texture as painted.
const MARKED_TINT := Color(1.0, 0.78, 0.55)  # warm orange: marked for digging
const DEPOSIT_TINT := Color(0.65, 0.88, 1.0)  # icy blue: a mana deposit
const LAIR_TINT := Color(1.0, 0.55, 0.55)  # red: a monster lair
const ITEM_COLORS := {"mana_cache": Color(0.45, 0.80, 1.0), "food_cache": Color(0.90, 0.75, 0.30),
	"treasure": Color(0.75, 0.45, 0.95), "lore": Color(0.95, 0.95, 0.90)}

# Cave generation. The map is new every game; each run prints its seed so a map can be replayed.
const FIXED_SEED := 0  # set to a printed seed to get that exact map again (0 = new map every run)
const CHAMBER_COUNT := 8  # open caverns spread around the map, joined by tunnels
const CHAMBER_RADIUS := Vector2(9.0, 18.0)  # smallest and largest chamber size, in cells (3 to 6 blocks)
const CHAMBER_GAP := 36.0  # least distance between chamber centers, so rock stays between them
const EXTRA_LINKS := 2  # tunnels beyond the minimum, so the network has some loops
const EDGE_TUNNELS := 2  # tunnels leading from a chamber off toward the map's edge
const TUNNEL_WOBBLE := 0.6  # how much tunnels wind on their way, in radians
const POCKET_COUNT := 5  # small sealed caves away from the network, found only by digging
const MIN_POCKET := 54  # caves smaller than this many cells (6 blocks' worth) are filled in as rock
const START_CENTER := Vector2i(91, 91)  # the middle cell of block (30, 30)
const SAFE_RADIUS := 21  # solid rock kept around the start, in cells, so reaching the network takes digging
const TUNNEL_RADIUS := 1.6  # tunnels are carved about one block (3 cells) wide
const DEPOSIT_COUNT := 8  # mana deposits scattered through caves and rock
const LAIR_COUNT := 3  # monster lairs, placed only in larger caves
const LAIR_MIN_CAVE := 225  # caves smaller than this many cells (25 blocks' worth) don't get lairs
const FEATURE_MIN_DISTANCE := 36  # deposits and lairs stay at least this many cells from the start
const RUIN_COUNT := 3  # small sealed rooms hidden in the rock, holding items
const ITEM_KINDS := ["mana_cache", "food_cache", "treasure", "lore"]

# Navigation layers: troops and raiders walk on different shapes, because doors are open for troops
# but closed to raiders, who must break them down.
const TROOP_LAYER := 1
const RAIDER_LAYER := 2
const DOOR_HEALTH := 60.0
const RIVAL_DOOR_COLOR := Color(0.35, 0.15, 0.40)

const MYCELIUM_SPREAD_TIME := 0.17  # seconds per cell spread (about a block every 1.5 seconds)
const MYCELIUM_RADIUS := 12.0  # how far mycelium spreads from its source, in cells (4 blocks)

const REBUILD_INTERVAL := 0.25  # at most four rebuilds a second, so digging a block isn't nine rebuilds

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
var mycelium: Dictionary = {}  # floor tiles covered in mycelium (used as a set); heals fungi
var mycelium_timer := 0.0
var rival_core: Vector2i = Vector2i(-1, -1)  # the rival dungeon's core, in the farthest chamber
var rival_room: Array[Vector2i] = []  # the rival room's floor tiles
var rival_mycelium: Array[Vector2i] = []  # where rival workers carry their downed guards
var rival_doors: Array[Vector2i] = []  # the rival room's two doors
var edge_exits: Array[Vector2i] = []  # where tunnels lead off toward the map edge; raiders enter here
var items: Dictionary = {}  # tile -> an item lying there: {"kind", "lore_index"}
var starting_room: Array[Vector2i] = []  # the pre-dug room's tiles; the fog keeps it lit
var preview: Dictionary = {}  # the item about to be placed: {"origin", "size", "color", "valid"}, or empty
var ground := TileMapLayer.new()  # draws rock and floor; only changed cells are updated
var mycelium_layer := TileMapLayer.new()  # mycelium over the floor; its texture's clear parts show the floor
var nav_region := NavigationRegion2D.new()  # the troops' walkable shape: doors open
var raider_region := NavigationRegion2D.new()  # the raiders' walkable shape: finished doors closed
var nav_dirty := false  # true when tiles changed and the walkable shape needs rebuilding
var nav_version := 0  # goes up with every rebuild, so units can tell the walkable shape changed
var baking := 0  # walkable shapes still being built in the background (0 when idle)
var row_runs: Array = []  # row y -> outlines of that row's floor runs, kept between rebuilds
var dirty_rows: Dictionary = {}  # rows whose floor changed since their runs were last worked out
var rebuild_cooldown := 0.0  # seconds until another rebuild may start
var bake_started_usec := 0


func _ready() -> void:
	for x in GRID_WIDTH:
		var column: Array = []
		for y in GRID_HEIGHT:
			column.append(Tile.ROCK)
		tiles.append(column)

	ground.tile_set = TileTextures.build(ground_colors(), TILE_WIDTH)
	ground.material = SurfaceMaterial.make(null, "floor")  # world-space texture detail
	ground.show_behind_parent = true  # drawn under this node's own drawing (furnishings, items)
	add_child(ground)
	# Line the layer's cells up exactly with tile_to_screen(), whatever offset Godot's layout uses.
	ground.position = tile_to_screen(Vector2i.ZERO) - ground.map_to_local(Vector2i.ZERO)
	# Check the layout really matches tile_to_screen() away from the origin too.
	var probe := Vector2i(5, 3)
	if (ground.position + ground.map_to_local(probe)).distance_to(tile_to_screen(probe)) > 1.0:
		push_warning("Ground tiles don't line up with tile_to_screen(): check the TileSet layout")

	# Mycelium: one plain white diamond, textured by world position like the floor, so its pattern
	# runs across cells. Added after the ground, so it draws on top of it.
	mycelium_layer.tile_set = TileTextures.build([Color.WHITE], TILE_WIDTH)
	mycelium_layer.material = SurfaceMaterial.make(null, "mycelium")
	mycelium_layer.material.set_shader_parameter("top_alpha", true)
	mycelium_layer.show_behind_parent = true
	add_child(mycelium_layer)
	mycelium_layer.position = ground.position

	nav_region.navigation_layers = TROOP_LAYER
	raider_region.navigation_layers = RAIDER_LAYER
	add_child(nav_region)
	add_child(raider_region)
	_generate_caves()

	# A small pre-dug starting room in the middle of the map, as the onboarding design calls for.
	# 3 x 3 blocks: the 9 x 9 cells around the start.
	for x in range(START_CENTER.x - 4, START_CENTER.x + 5):
		for y in range(START_CENTER.y - 4, START_CENTER.y + 5):
			dig(Vector2i(x, y))
			starting_room.append(Vector2i(x, y))

	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			_update_ground(Vector2i(x, y))  # paint the whole map once; after that only changes


## Carves the labyrinth: mostly solid rock, with separate chambers joined by narrow winding tunnels
## (every chamber is reachable), a couple of tunnels leading off toward the edge, and a few small
## sealed pockets hidden in the rock.
func _generate_caves() -> void:
	var rng := RandomNumberGenerator.new()
	if FIXED_SEED != 0:
		rng.seed = FIXED_SEED
	else:
		rng.randomize()
	print("Map seed: ", rng.seed, "  (set FIXED_SEED to this to replay this map)")

	# Everything starts as rock; caves are carved out of it.
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			tiles[x][y] = Tile.ROCK

	# 1. Chambers: irregular caverns, kept apart from each other and from the start.
	var chambers: Array[Vector2] = []
	var chamber_tries := 0
	while chambers.size() < CHAMBER_COUNT and chamber_tries < 500:
		chamber_tries += 1
		var center := Vector2(rng.randi_range(18, GRID_WIDTH - 19), rng.randi_range(18, GRID_HEIGHT - 19))
		if center.distance_to(Vector2(START_CENTER)) < SAFE_RADIUS + 18:
			continue
		var too_close := false
		for other in chambers:
			if center.distance_to(other) < CHAMBER_GAP:
				too_close = true
		if not too_close:
			chambers.append(center)
			_carve_blob(center, rng.randf_range(CHAMBER_RADIUS.x, CHAMBER_RADIUS.y), rng)

	# 2. Links: a minimum spanning tree (the shortest set of links that reaches every chamber),
	# built by repeatedly joining the closest chamber not yet connected. Then a few extra links for loops.
	var links: Array = []  # pairs of chamber indexes
	var joined: Array[int] = [0]
	while joined.size() < chambers.size():
		var best_pair := [-1, -1]
		var best_distance := INF
		for a in joined:
			for b in chambers.size():
				if joined.has(b):
					continue
				var distance := chambers[a].distance_to(chambers[b])
				if distance < best_distance:
					best_distance = distance
					best_pair = [a, b]
		links.append(best_pair)
		joined.append(best_pair[1])
	for _n in EXTRA_LINKS:
		links.append([rng.randi_range(0, chambers.size() - 1), rng.randi_range(0, chambers.size() - 1)])

	# 3. Tunnels: each link becomes a narrow tunnel that winds toward the other chamber.
	for link in links:
		if link[0] != link[1]:
			_carve_tunnel(chambers[link[0]], chambers[link[1]], rng)
	for _n in EDGE_TUNNELS:
		var from: Vector2 = chambers[rng.randi_range(0, chambers.size() - 1)]
		var edge_point := Vector2(rng.randi_range(9, GRID_WIDTH - 10), [4, GRID_HEIGHT - 5][rng.randi_range(0, 1)])
		_carve_tunnel(from, edge_point, rng)
		edge_exits.append(Vector2i(roundi(edge_point.x), roundi(edge_point.y)))

	# Sealed pockets: small caves anywhere in the rock, not joined to the network.
	for _n in POCKET_COUNT:
		var pocket := Vector2(rng.randi_range(12, GRID_WIDTH - 13), rng.randi_range(12, GRID_HEIGHT - 13))
		if _area_is_rock(Vector2i(pocket), 12):
			_carve_blob(pocket, rng.randf_range(4.5, 7.5), rng)

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

	# 5. Mana deposits, one block each, anywhere away from the start, in caves or in the rock.
	var deposit_blocks := 0
	while deposit_blocks < DEPOSIT_COUNT:
		var block := Vector2i(rng.randi_range(1, GRID_WIDTH / BLOCK - 2), rng.randi_range(1, GRID_HEIGHT / BLOCK - 2))
		if block_center(block).distance_to(START_CENTER) >= FEATURE_MIN_DISTANCE and not deposits.has(block * BLOCK):
			for cell in block_cells(block):
				deposits[cell] = true
			deposit_blocks += 1

	# 6. Ruins: small rooms carved into solid rock, sealed on every side so only digging finds them.
	var lore_count := 0
	var ruin_tries := 0
	var ruins_made := 0
	while ruins_made < RUIN_COUNT and ruin_tries < 300:
		ruin_tries += 1
		# 3-4 by 3-5 blocks, on the block grid.
		var size := Vector2i(rng.randi_range(3, 4), rng.randi_range(3, 5)) * BLOCK
		var corner := Vector2i(rng.randi_range(1, (GRID_WIDTH - size.x) / BLOCK - 2),
			rng.randi_range(1, (GRID_HEIGHT - size.y) / BLOCK - 2)) * BLOCK
		if _ruin_fits(corner, size):
			var ruin_tiles: Array[Vector2i] = []
			for dx in size.x:
				for dy in size.y:
					var tile := corner + Vector2i(dx, dy)
					tiles[tile.x][tile.y] = Tile.FLOOR
					ruin_tiles.append(tile)
			for _n in rng.randi_range(1, 2):  # one or two items per ruin (_n: the count itself isn't used)
				var spot: Vector2i = ruin_tiles[rng.randi_range(0, ruin_tiles.size() - 1)]
				var kind: String = ITEM_KINDS[rng.randi_range(0, ITEM_KINDS.size() - 1)]
				items[spot] = {"kind": kind, "lore_index": lore_count}
				if kind == "lore":
					lore_count += 1
			ruins_made += 1

	# 7. Monster lairs, one block each, on open floor in the larger caves, one cave each where possible.
	var tries := 0
	var lair_blocks := 0
	while lair_blocks < LAIR_COUNT and not big_caves.is_empty() and tries < 200:
		tries += 1  # a safety limit, in case no spot fits
		var cave: Array = big_caves[rng.randi_range(0, big_caves.size() - 1)]
		var tile: Vector2i = cave[rng.randi_range(0, cave.size() - 1)]
		if tile.distance_to(START_CENTER) >= FEATURE_MIN_DISTANCE and not deposits.has(tile):
			for cell in block_cells(block_of(tile)):
				if is_floor(cell):
					lairs[cell] = true
			lair_blocks += 1
			if big_caves.size() > LAIR_COUNT - lair_blocks:
				big_caves.erase(cave)  # spread lairs across caves while there are enough caves

	# 8. The rival dungeon, in the chamber farthest from the start.
	var farthest: Vector2 = chambers[0]
	for center in chambers:
		if center.distance_to(Vector2(START_CENTER)) > farthest.distance_to(Vector2(START_CENTER)):
			farthest = center
	_build_rival_room(block_center(block_of(Vector2i(farthest))))  # centered on a block

	nav_dirty = true


## Carves the rival's walled room: 5 x 5 blocks of floor inside a one-block ring of rock, with the core
## in the middle, mycelium (3 x 3 blocks) around it, and a one-block rival door on two opposite sides,
## each with a short block-wide passage outward. center is the middle cell of a block.
func _build_rival_room(center: Vector2i) -> void:
	rival_core = center
	for dx in range(-10, 11):
		for dy in range(-10, 11):
			var tile := center + Vector2i(dx, dy)
			if not is_in_bounds(tile):
				continue
			deposits.erase(tile)
			lairs.erase(tile)
			items.erase(tile)
			if max(abs(dx), abs(dy)) >= 8:
				tiles[tile.x][tile.y] = Tile.ROCK  # the wall ring, one block thick
			else:
				tiles[tile.x][tile.y] = Tile.FLOOR
				rival_room.append(tile)
				if max(abs(dx), abs(dy)) <= 4:
					_add_mycelium(tile)
					rival_mycelium.append(tile)
	for side in [Vector2i(0, -1), Vector2i(0, 1)]:
		var door_tile: Vector2i = center + side * 9 - Vector2i(1, 1)  # the door block's first cell
		for cell in footprint(door_tile, Vector2i(BLOCK, BLOCK)):
			tiles[cell.x][cell.y] = Tile.FLOOR
		for step in range(11, 23):  # a short passage out, so the door always connects to the chamber
			for across in range(-1, 2):
				var passage: Vector2i = center + side * step + Vector2i(across, 0)
				if is_in_bounds(passage) and _well_inside(Vector2(passage)):
					tiles[passage.x][passage.y] = Tile.FLOOR
		var door := {"id": "door", "origin": door_tile, "size": Vector2i(BLOCK, BLOCK), "color": RIVAL_DOOR_COLOR,
			"blocks": false, "rotation": 0, "progress": BUILD_TIME, "solid": false, "built": true,
			"health": DOOR_HEALTH, "owner": "rival"}
		furnishings.append(door)
		for cell in footprint(door_tile, Vector2i(BLOCK, BLOCK)):
			occupied[cell] = door
		rival_doors.append(door_tile)


## The closest finished door of the given owner within reach of a point, or an empty dictionary.
## Your troops use it to find rival doors to bash.
func door_near(point: Vector2, reach: float, owner: String) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := reach
	for furnishing in furnishings:
		if furnishing["id"] != "door" or not furnishing["built"] or furnishing.get("owner", "player") != owner:
			continue
		var distance := point.distance_to(footprint_center(furnishing))
		if distance <= best_distance:
			best = furnishing
			best_distance = distance
	return best


## True if a ruin of this size fits here: far from the start, and the ruin plus a one-tile border
## are all solid rock, so it stays sealed until someone digs in.
func _ruin_fits(corner: Vector2i, size: Vector2i) -> bool:
	if (corner + size / 2).distance_to(START_CENTER) < FEATURE_MIN_DISTANCE:
		return false
	for dx in range(-BLOCK, size.x + BLOCK):  # a one-block border of rock
		for dy in range(-BLOCK, size.y + BLOCK):
			var tile := corner + Vector2i(dx, dy)
			if not is_in_bounds(tile) or tiles[tile.x][tile.y] != Tile.ROCK or deposits.has(tile):
				return false
	return true


## Carves an irregular blob: a circle whose edge bulges in and out, so chambers don't look round.
func _carve_blob(center: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var phase_a := rng.randf() * TAU
	var phase_b := rng.randf() * TAU
	var reach := ceili(radius * 1.4)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var offset := Vector2(dx, dy)
			var angle := offset.angle()
			# Two overlapping waves around the edge make the outline lumpy.
			var edge := radius * (1.0 + 0.25 * sin(3.0 * angle + phase_a) + 0.15 * sin(5.0 * angle + phase_b))
			if offset.length() <= edge:
				_carve_circle(center + offset, 0.0)


## Carves a narrow tunnel from one point toward another, wandering a little on the way.
## Steers around the safe ring instead of cutting through it.
func _carve_tunnel(from: Vector2, to: Vector2, rng: RandomNumberGenerator) -> void:
	var point := from
	var wobble := 0.0
	for _step in 1500:  # a safety limit on length
		if point.distance_to(to) < 1.5:
			return
		wobble = clamp(wobble + rng.randf_range(-0.3, 0.3), -TUNNEL_WOBBLE, TUNNEL_WOBBLE)
		var angle := (to - point).angle() + wobble
		var ahead := point + Vector2.from_angle(angle)
		if ahead.distance_to(Vector2(START_CENTER)) <= SAFE_RADIUS + 1:
			angle = (point - Vector2(START_CENTER)).angle() + PI / 2.0  # go around the safe ring
			ahead = point + Vector2.from_angle(angle)
		var previous_tile := Vector2i(roundi(point.x), roundi(point.y))
		point = ahead
		_carve_circle(point, TUNNEL_RADIUS)  # about a block wide
		# A diagonal step leaves two tiles touching only at a corner, which units can't pass
		# (the walkable shape closes off corner gaps), so open a side tile to join them.
		var tile_now := Vector2i(roundi(point.x), roundi(point.y))
		if tile_now.x != previous_tile.x and tile_now.y != previous_tile.y:
			_carve_circle(Vector2(tile_now.x, previous_tile.y), 0.0)


## Opens every tile within radius of a point, except inside the safe ring around the start.
func _carve_circle(center: Vector2, radius: float) -> void:
	var reach := ceili(radius)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var tile := Vector2i(roundi(center.x) + dx, roundi(center.y) + dy)
			if not _well_inside(Vector2(tile)) or Vector2(tile).distance_to(center) > radius:
				continue
			if tile.distance_to(START_CENTER) <= SAFE_RADIUS:
				continue  # keep the safe ring solid, so reaching the network takes some digging
			tiles[tile.x][tile.y] = Tile.FLOOR


## True if a point is far enough from the map's edge to carve, leaving a solid rock border.
func _well_inside(point: Vector2) -> bool:
	return point.x >= 2 and point.y >= 2 and point.x <= GRID_WIDTH - 3 and point.y <= GRID_HEIGHT - 3


## True if every tile within radius of center is still rock: room for a sealed pocket.
func _area_is_rock(center: Vector2i, radius: int) -> bool:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var tile := center + Vector2i(dx, dy)
			if not is_in_bounds(tile) or tiles[tile.x][tile.y] != Tile.ROCK:
				return false
	return true


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


func _process(delta: float) -> void:
	mycelium_timer += delta
	if mycelium_timer >= MYCELIUM_SPREAD_TIME:
		mycelium_timer -= MYCELIUM_SPREAD_TIME
		_spread_mycelium()

	# Rebuild at most every REBUILD_INTERVAL, and only when no rebuild is still running in the background;
	# changes made meanwhile keep nav_dirty on and are picked up by the next one.
	# Wait until the navigation server has synced its map at least once (iteration 0 means
	# not yet); a mesh handed over before then is lost, which broke the starting room.
	rebuild_cooldown = max(rebuild_cooldown - delta, 0.0)
	var map_ready := NavigationServer2D.map_get_iteration_id(get_world_2d().navigation_map) > 0
	if nav_dirty and map_ready and baking == 0 and rebuild_cooldown == 0.0:
		nav_dirty = false
		rebuild_cooldown = REBUILD_INTERVAL
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
		_update_ground(tile)
		marks_changed.emit(tile)


func is_marked(tile: Vector2i) -> bool:
	return marked.has(tile)


## Clears a dig mark.
func unmark(tile: Vector2i) -> void:
	if marked.erase(tile):
		_update_ground(tile)
		marks_changed.emit(tile)


## True if this tile is covered in mycelium belonging to that side ("player" or "rival").
## Mycelium only heals its own side: your troops can't heal in the rival's room, and the reverse.
func has_mycelium(tile: Vector2i, owner: String = "player") -> bool:
	if not mycelium.has(tile):
		return false
	var is_rival: bool = rival_mycelium.has(tile)
	return is_rival if owner == "rival" else not is_rival


## Each finished mycelium source spreads onto one more floor tile: the closest open tile to it that
## touches mycelium already, out to MYCELIUM_RADIUS. So it grows outward from the source.
func _spread_mycelium() -> void:
	for furnishing in furnishings:
		if furnishing["id"] != "mycelium_source" or not furnishing["built"]:
			continue
		var source_cells: Array[Vector2i] = footprint(furnishing["origin"], furnishing["size"])
		var source: Vector2i = furnishing["origin"] + furnishing["size"] / 2  # its middle cell
		var best: Vector2i = NO_TILE
		var best_distance := INF
		var reach := ceili(MYCELIUM_RADIUS)
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var tile := source + Vector2i(dx, dy)
				var distance := Vector2(dx, dy).length()
				if distance > MYCELIUM_RADIUS or distance >= best_distance:
					continue
				if not is_floor(tile) or mycelium.has(tile) or not _touches_mycelium(tile, source_cells):
					continue
				best = tile
				best_distance = distance
		if best != NO_TILE:
			_add_mycelium(best)


func _add_mycelium(tile: Vector2i) -> void:
	mycelium[tile] = true
	mycelium_layer.set_cell(tile, 0, Vector2i(0, 0))


func _touches_mycelium(tile: Vector2i, source_cells: Array[Vector2i]) -> bool:
	for offset in NEIGHBORS:
		var next: Vector2i = tile + offset
		if source_cells.has(next) or mycelium.has(next):
			return true
	return false


## The closest mycelium tile to a point that isn't under a blocking furnishing, or NO_TILE.
## Rescuers carry injured troops here.
func nearest_free_mycelium(from: Vector2) -> Vector2i:
	var best: Vector2i = NO_TILE
	var best_distance := INF
	for tile in mycelium:
		if occupied.has(tile) and occupied[tile]["blocks"]:
			continue
		if rival_mycelium.has(tile):
			continue  # never carry your injured into the rival's room
		var distance := from.distance_to(tile_to_screen(tile))
		if distance < best_distance:
			best = tile
			best_distance = distance
	return best


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
		if items.has(tile):
			return false  # haul the item away first
	return true


## Adds an unbuilt furnishing (a see-through ghost) for a worker to build later.
## Ghosts are walkable; a blocking furnishing turns solid once it's SOLID_AT built.
## rotation is in quarter turns (0 to 3), kept so later art can face the right way.
func place_blueprint(id: String, origin: Vector2i, size: Vector2i, color: Color, blocks: bool, rotation_steps: int = 0) -> void:
	var furnishing := {"id": id, "origin": origin, "size": size, "color": color, "blocks": blocks,
		"rotation": rotation_steps, "progress": 0.0, "solid": false, "built": false, "owner": "player"}
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
	if job["kind"] == "haul":
		return job.get("carrying", false) or items.has(job["tile"])
	return furnishings.has(job["furnishing"]) and not job["furnishing"]["built"]


## Picks up the item on a tile: it's removed from the floor and returned. Empty if there was none.
func take_item(tile: Vector2i) -> Dictionary:
	var item: Dictionary = items.get(tile, {})
	if items.erase(tile):
		queue_redraw()
	return item


## Puts an item back down, e.g. when a worker can't reach storage.
func drop_item(tile: Vector2i, item: Dictionary) -> void:
	items[tile] = item
	queue_redraw()


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
		if furnishing["id"] == "door":
			furnishing["health"] = DOOR_HEALTH
			nav_dirty = true  # a finished door closes the raiders' shape
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
		_update_ground(tile)
		marks_changed.emit(tile)
	if is_in_bounds(tile) and tiles[tile.x][tile.y] == Tile.ROCK:
		tiles[tile.x][tile.y] = Tile.FLOOR
		_update_ground(tile)
		dirty_rows[tile.y] = true  # this row's floor runs need working out again
		cell_dug.emit(tile)
		nav_dirty = true  # the walkable shape is out of date
		queue_redraw()  # the data changed, so the picture must update
		layout_changed.emit()


## Builds the walkable shape from every floor tile, shrunk by UNIT_RADIUS so units keep clear of rock.
## Starts rebuilding both walkable shapes in the background. Gathering the outlines happens here, on the
## main thread (it's quick); the slow part, baking, runs on another thread, and each shape is swapped in
## when it's done. Until then troops keep using the old shapes, a few frames out of date.
func rebuild_navigation() -> void:
	bake_started_usec = Time.get_ticks_usec()
	baking = 2
	_refresh_rows()  # once, shared by both shapes
	_bake_in_background(nav_region, "rival")  # your troops: rival doors are closed
	_bake_in_background(raider_region, "player")  # hostiles: your doors are closed


func _bake_in_background(region: NavigationRegion2D, closed_owner: String) -> void:
	var source := _walkable_source(closed_owner)
	var nav_polygon := NavigationPolygon.new()
	nav_polygon.agent_radius = UNIT_RADIUS
	# The callback can arrive from the background thread, so hand the result to the main thread with
	# call_deferred before touching the scene.
	NavigationServer2D.bake_from_source_geometry_data_async(nav_polygon, source,
		func(): _finish_bake.call_deferred(region, nav_polygon))


func _finish_bake(region: NavigationRegion2D, nav_polygon: NavigationPolygon) -> void:
	region.navigation_polygon = nav_polygon
	baking -= 1
	if baking == 0:
		nav_version += 1  # both shapes are new: units may retry jobs they couldn't reach
		# Measured Nov 5 on the laptop: about 0.35 ms on the main thread, 32 ms in the background.


## Gathers the outlines for a walkable shape: every floor tile, minus solid furnishings (the baker shrinks
## it by UNIT_RADIUS so units keep clear of rock). Finished doors belonging to closed_owner are cut out
## too: each side's doors are open for its own troops and closed to the other side.
func _walkable_source(closed_owner: String) -> NavigationMeshSourceGeometryData2D:
	var source := NavigationMeshSourceGeometryData2D.new()
	# Floor goes in as runs: each unbroken stretch of floor cells along a row is one long outline,
	# worked out ahead of time by _refresh_rows() and shared by both shapes.
	for outlines in row_runs:
		for outline in outlines:
			source.add_traversable_outline(outline)
	# Solid furnishings cut holes in the walkable shape (ghosts stay walkable until SOLID_AT).
	for furnishing in furnishings:
		var closed_door: bool = furnishing["id"] == "door" and furnishing["built"] \
			and furnishing.get("owner", "player") == closed_owner
		if furnishing["solid"] or closed_door:
			source.add_obstruction_outline(_cells_outline(furnishing["origin"], furnishing["size"]))
	return source


## Works out the floor runs again for rows that changed since last time, and only those: digging touches
## a few rows, not all of them, so this stays cheap. The very first time, every row is done.
func _refresh_rows() -> void:
	if row_runs.size() != GRID_HEIGHT:
		row_runs.resize(GRID_HEIGHT)
		for y in GRID_HEIGHT:
			dirty_rows[y] = true
	for y in dirty_rows:
		row_runs[y] = _row_outlines(y)
	dirty_rows.clear()


## One outline per unbroken stretch of floor cells in a row. Far fewer outlines than one per cell.
func _row_outlines(y: int) -> Array:
	var outlines: Array = []
	var x := 0
	while x < GRID_WIDTH:
		if tiles[x][y] != Tile.FLOOR:
			x += 1
			continue
		var run_start := x
		while x < GRID_WIDTH and tiles[x][y] == Tile.FLOOR:
			x += 1
		outlines.append(_cells_outline(Vector2i(run_start, y), Vector2i(x - run_start, 1)))
	return outlines


## The outline of a rectangle of cells on the grid (size cells along x and y from first): four corners
## on screen. Used to hand the navigation builder big shapes instead of one diamond per cell.
func _cells_outline(first: Vector2i, size: Vector2i) -> PackedVector2Array:
	var low := Vector2(first) - Vector2(0.5, 0.5)
	var high := Vector2(first + size) - Vector2(0.5, 0.5)
	return PackedVector2Array([_grid_point(low), _grid_point(Vector2(high.x, low.y)),
		_grid_point(high), _grid_point(Vector2(low.x, high.y))])


## Any point in grid coordinates (fractions allowed) to screen position; tile_to_screen for in-between points.
func _grid_point(point: Vector2) -> Vector2:
	return Vector2((point.x - point.y) * TILE_WIDTH / 2.0, (point.x + point.y) * TILE_HEIGHT / 2.0)


## The block a cell belongs to.
func block_of(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(tile.x / float(BLOCK)), floori(tile.y / float(BLOCK)))


## The first (top) cell of the block a cell belongs to: where block-sized things snap to.
func block_origin(tile: Vector2i) -> Vector2i:
	return block_of(tile) * BLOCK


## The middle cell of a block.
func block_center(block: Vector2i) -> Vector2i:
	return block * BLOCK + Vector2i(1, 1)


## The nine cells of a block.
func block_cells(block: Vector2i) -> Array[Vector2i]:
	return footprint(block * BLOCK, Vector2i(BLOCK, BLOCK))


## Raiders hit a door. At zero health it's destroyed (no refund), and both walkable shapes update.
func damage_door(door: Dictionary, amount: float) -> void:
	door["health"] = door.get("health", DOOR_HEALTH) - amount
	if door["health"] <= 0.0:
		remove_furnishing(door)
		nav_dirty = true  # the raiders' shape opens up here
	queue_redraw()


## Draws what sits on the ground. The ground itself is the TileMapLayer, drawn underneath.
func _draw() -> void:
	# Furnishings on top of the floor: see-through until built, solid once built.
	for furnishing in furnishings:
		var color: Color = furnishing["color"]
		if not furnishing["built"]:
			color.a = 0.35
		for tile in footprint(furnishing["origin"], furnishing["size"]):
			draw_colored_polygon(diamond(tile), color)
		# A door under attack shows its health.
		if furnishing["id"] == "door" and furnishing.get("health", DOOR_HEALTH) < DOOR_HEALTH:
			var spot := footprint_center(furnishing) + Vector2(-30, -10)
			draw_rect(Rect2(spot, Vector2(60, 6)), Color(0.2, 0.2, 0.2))
			draw_rect(Rect2(spot, Vector2(60 * furnishing["health"] / DOOR_HEALTH, 6)), Color(0.95, 0.6, 0.2))

	# Items lying on the floor: a small diamond in the middle of the tile.
	for tile in items:
		var center := tile_to_screen(tile)
		var small := PackedVector2Array()
		for corner in diamond(tile):
			small.append(center + (corner - center) * 0.8)  # most of one cell
		draw_colored_polygon(small, ITEM_COLORS[items[tile]["kind"]])

	# The placement preview: fainter than a ghost, and red where the item can't go.
	if not preview.is_empty():
		var preview_color: Color = preview["color"] if preview["valid"] else Color(1.0, 0.2, 0.2)
		preview_color.a = 0.18
		for tile in footprint(preview["origin"], preview["size"]):
			if is_in_bounds(tile):
				draw_colored_polygon(diamond(tile), preview_color)


## The placeholder color for each Ground kind, in enum order. The fog builds a darkened copy.
## These are tints, not colors: the textures carry the real colors and the shader multiplies these onto
## them, so white shows a texture exactly as painted and anything else tints it.
func ground_colors() -> Array:
	return [Color.WHITE, Color.WHITE, MARKED_TINT, DEPOSIT_TINT.darkened(0.15), DEPOSIT_TINT, LAIR_TINT]


## Which kind of ground a tile shows: marks first, then deposits and lairs, then rock or floor.
func ground_kind(tile: Vector2i) -> int:
	if marked.has(tile):
		return Ground.MARKED
	var rock: bool = tiles[tile.x][tile.y] == Tile.ROCK
	if deposits.has(tile):
		return Ground.DEPOSIT_ROCK if rock else Ground.DEPOSIT_FLOOR
	if lairs.has(tile):
		return Ground.LAIR
	return Ground.ROCK if rock else Ground.FLOOR


## The color of whatever stands on a tile, for the fog to remember: a finished furnishing, an item,
## or nothing (fully see-through).
func overlay_color(tile: Vector2i) -> Color:
	if occupied.has(tile) and occupied[tile]["built"]:
		return occupied[tile]["color"]
	if items.has(tile):
		return ITEM_COLORS[items[tile]["kind"]]
	return Color(0, 0, 0, 0)


func _update_ground(tile: Vector2i) -> void:
	ground.set_cell(tile, 0, Vector2i(ground_kind(tile), 0))


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
