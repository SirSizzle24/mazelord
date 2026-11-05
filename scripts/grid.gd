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
const ITEM_COLORS := {"mana_cache": Color(0.45, 0.80, 1.0), "food_cache": Color(0.90, 0.75, 0.30),
	"treasure": Color(0.75, 0.45, 0.95), "lore": Color(0.95, 0.95, 0.90)}

# Cave generation. The map is new every game; each run prints its seed so a map can be replayed.
const FIXED_SEED := 0  # set to a printed seed to get that exact map again (0 = new map every run)
const CHAMBER_COUNT := 8  # open caverns spread around the map, joined by tunnels
const CHAMBER_RADIUS := Vector2(3.0, 6.0)  # smallest and largest chamber size, in tiles
const CHAMBER_GAP := 12.0  # least distance between chamber centers, so rock stays between them
const EXTRA_LINKS := 2  # tunnels beyond the minimum, so the network has some loops
const EDGE_TUNNELS := 2  # tunnels leading from a chamber off toward the map's edge
const TUNNEL_WOBBLE := 0.6  # how much tunnels wind on their way, in radians
const POCKET_COUNT := 5  # small sealed caves away from the network, found only by digging
const MIN_POCKET := 6  # caves smaller than this many tiles are filled in as rock
const START_CENTER := Vector2i(30, 30)
const SAFE_RADIUS := 7  # solid rock kept around the start, so the first passage takes some digging
const DEPOSIT_COUNT := 8  # mana deposits scattered through caves and rock
const LAIR_COUNT := 3  # monster lairs, placed only in larger caves
const LAIR_MIN_CAVE := 25  # caves smaller than this many tiles don't get lairs
const FEATURE_MIN_DISTANCE := 12  # deposits and lairs stay at least this far from the start
const RUIN_COUNT := 3  # small sealed rooms hidden in the rock, holding items
const ITEM_KINDS := ["mana_cache", "food_cache", "treasure", "lore"]

# Navigation layers: troops and raiders walk on different shapes, because doors are open for troops
# but closed to raiders, who must break them down.
const TROOP_LAYER := 1
const RAIDER_LAYER := 2
const DOOR_HEALTH := 60.0
const RIVAL_DOOR_COLOR := Color(0.35, 0.15, 0.40)

const MYCELIUM_COLOR := Color(0.70, 0.55, 0.85, 0.45)  # drawn over the floor, see-through
const MYCELIUM_SPREAD_TIME := 1.5  # seconds for each source to spread onto one more tile
const MYCELIUM_RADIUS := 4.0  # how far mycelium spreads from its source, in tiles

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
var nav_region := NavigationRegion2D.new()  # the troops' walkable shape: doors open
var raider_region := NavigationRegion2D.new()  # the raiders' walkable shape: finished doors closed
var nav_dirty := false  # true when tiles changed and the walkable shape needs rebuilding
var nav_version := 0  # goes up with every rebuild, so units can tell the walkable shape changed


func _ready() -> void:
	for x in GRID_WIDTH:
		var column: Array = []
		for y in GRID_HEIGHT:
			column.append(Tile.ROCK)
		tiles.append(column)

	nav_region.navigation_layers = TROOP_LAYER
	raider_region.navigation_layers = RAIDER_LAYER
	add_child(nav_region)
	add_child(raider_region)
	_generate_caves()

	# A small pre-dug starting room in the middle of the map, as the onboarding design calls for.
	for x in range(START_CENTER.x - 1, START_CENTER.x + 2):
		for y in range(START_CENTER.y - 1, START_CENTER.y + 2):
			dig(Vector2i(x, y))
			starting_room.append(Vector2i(x, y))


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
		var center := Vector2(rng.randi_range(6, GRID_WIDTH - 7), rng.randi_range(6, GRID_HEIGHT - 7))
		if center.distance_to(Vector2(START_CENTER)) < SAFE_RADIUS + 6:
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
		var edge_point := Vector2(rng.randi_range(3, GRID_WIDTH - 4), [3, GRID_HEIGHT - 4][rng.randi_range(0, 1)])
		_carve_tunnel(from, edge_point, rng)
		edge_exits.append(Vector2i(roundi(edge_point.x), roundi(edge_point.y)))

	# Sealed pockets: small caves anywhere in the rock, not joined to the network.
	for _n in POCKET_COUNT:
		var pocket := Vector2(rng.randi_range(4, GRID_WIDTH - 5), rng.randi_range(4, GRID_HEIGHT - 5))
		if _area_is_rock(Vector2i(pocket), 4):
			_carve_blob(pocket, rng.randf_range(1.5, 2.5), rng)

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

	# 6. Ruins: small rooms carved into solid rock, sealed on every side so only digging finds them.
	var lore_count := 0
	var ruin_tries := 0
	var ruins_made := 0
	while ruins_made < RUIN_COUNT and ruin_tries < 300:
		ruin_tries += 1
		var size := Vector2i(rng.randi_range(3, 4), rng.randi_range(3, 5))
		var corner := Vector2i(rng.randi_range(2, GRID_WIDTH - size.x - 3), rng.randi_range(2, GRID_HEIGHT - size.y - 3))
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

	# 7. Monster lairs on open floor in the larger caves, one cave each where possible.
	var tries := 0
	while lairs.size() < LAIR_COUNT and not big_caves.is_empty() and tries < 200:
		tries += 1  # a safety limit, in case no spot fits
		var cave: Array = big_caves[rng.randi_range(0, big_caves.size() - 1)]
		var tile: Vector2i = cave[rng.randi_range(0, cave.size() - 1)]
		if tile.distance_to(START_CENTER) >= FEATURE_MIN_DISTANCE and not deposits.has(tile):
			lairs[tile] = true
			if big_caves.size() > LAIR_COUNT - lairs.size():
				big_caves.erase(cave)  # spread lairs across caves while there are enough caves

	# 8. The rival dungeon, in the chamber farthest from the start.
	var farthest: Vector2 = chambers[0]
	for center in chambers:
		if center.distance_to(Vector2(START_CENTER)) > farthest.distance_to(Vector2(START_CENTER)):
			farthest = center
	_build_rival_room(Vector2i(farthest))

	nav_dirty = true


## Carves the rival's walled room: a 5 x 5 floor inside a ring of rock, with the core in the middle,
## mycelium around it, and a rival door on two opposite sides, each with a short passage outward.
func _build_rival_room(center: Vector2i) -> void:
	rival_core = center
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var tile := center + Vector2i(dx, dy)
			deposits.erase(tile)
			lairs.erase(tile)
			items.erase(tile)
			if max(abs(dx), abs(dy)) == 3:
				tiles[tile.x][tile.y] = Tile.ROCK  # the wall ring
			else:
				tiles[tile.x][tile.y] = Tile.FLOOR
				rival_room.append(tile)
				if max(abs(dx), abs(dy)) <= 1:
					mycelium[tile] = true
					rival_mycelium.append(tile)
	for side in [Vector2i(0, -1), Vector2i(0, 1)]:
		var door_tile: Vector2i = center + side * 3
		tiles[door_tile.x][door_tile.y] = Tile.FLOOR
		for step in range(4, 8):  # a short passage out, so the door always connects to the chamber
			var passage: Vector2i = center + side * step
			if is_in_bounds(passage) and _well_inside(Vector2(passage)):
				tiles[passage.x][passage.y] = Tile.FLOOR
		var door := {"id": "door", "origin": door_tile, "size": Vector2i(1, 1), "color": RIVAL_DOOR_COLOR,
			"blocks": false, "rotation": 0, "progress": BUILD_TIME, "solid": false, "built": true,
			"health": DOOR_HEALTH, "owner": "rival"}
		furnishings.append(door)
		occupied[door_tile] = door
		rival_doors.append(door_tile)


## The closest finished door of the given owner within reach of a point, or an empty dictionary.
## Your troops use it to find rival doors to bash.
func door_near(point: Vector2, reach: float, owner: String) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := reach
	for furnishing in furnishings:
		if furnishing["id"] != "door" or not furnishing["built"] or furnishing.get("owner", "player") != owner:
			continue
		var distance := point.distance_to(tile_to_screen(furnishing["origin"]))
		if distance <= best_distance:
			best = furnishing
			best_distance = distance
	return best


## True if a ruin of this size fits here: far from the start, and the ruin plus a one-tile border
## are all solid rock, so it stays sealed until someone digs in.
func _ruin_fits(corner: Vector2i, size: Vector2i) -> bool:
	if (corner + size / 2).distance_to(START_CENTER) < FEATURE_MIN_DISTANCE:
		return false
	for dx in range(-1, size.x + 1):
		for dy in range(-1, size.y + 1):
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
	for _step in 400:  # a safety limit on length
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
		_carve_circle(point, 0.8)  # about one to two tiles wide
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
		var source: Vector2i = furnishing["origin"]
		var best: Vector2i = NO_TILE
		var best_distance := INF
		var reach := ceili(MYCELIUM_RADIUS)
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var tile := source + Vector2i(dx, dy)
				var distance := Vector2(dx, dy).length()
				if distance > MYCELIUM_RADIUS or distance >= best_distance:
					continue
				if not is_floor(tile) or mycelium.has(tile) or not _touches_mycelium(tile, source):
					continue
				best = tile
				best_distance = distance
		if best != NO_TILE:
			mycelium[best] = true
			queue_redraw()


func _touches_mycelium(tile: Vector2i, source: Vector2i) -> bool:
	for offset in NEIGHBORS:
		var next: Vector2i = tile + offset
		if next == source or mycelium.has(next):
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

	nav_region.navigation_polygon = _bake_walkable("rival")  # your troops: rival doors are closed
	raider_region.navigation_polygon = _bake_walkable("player")  # hostiles: your doors are closed
	nav_version += 1

	var elapsed_ms := (Time.get_ticks_usec() - start_time) / 1000.0
	print("Navigation rebuilt in %.2f ms" % elapsed_ms)  # temporary: measuring the cost


## Builds a walkable shape from every floor tile, minus solid furnishings, shrunk by UNIT_RADIUS so
## units keep clear of rock. Finished doors belonging to closed_owner are cut out too: each side's
## doors are open for its own troops and closed to the other side.
func _bake_walkable(closed_owner: String) -> NavigationPolygon:
	var source := NavigationMeshSourceGeometryData2D.new()
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			if tiles[x][y] == Tile.FLOOR:
				source.add_traversable_outline(diamond(Vector2i(x, y)))
	# Solid furnishings cut holes in the walkable shape (ghosts stay walkable until SOLID_AT).
	for furnishing in furnishings:
		var closed_door: bool = furnishing["id"] == "door" and furnishing["built"] \
			and furnishing.get("owner", "player") == closed_owner
		if furnishing["solid"] or closed_door:
			for tile in footprint(furnishing["origin"], furnishing["size"]):
				source.add_obstruction_outline(diamond(tile))
	var nav_polygon := NavigationPolygon.new()
	nav_polygon.agent_radius = UNIT_RADIUS
	NavigationServer2D.bake_from_source_geometry_data(nav_polygon, source)
	return nav_polygon


## Raiders hit a door. At zero health it's destroyed (no refund), and both walkable shapes update.
func damage_door(door: Dictionary, amount: float) -> void:
	door["health"] = door.get("health", DOOR_HEALTH) - amount
	if door["health"] <= 0.0:
		remove_furnishing(door)
		nav_dirty = true  # the raiders' shape opens up here
	queue_redraw()


func _draw() -> void:
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var shape := diamond(Vector2i(x, y))
			draw_colored_polygon(shape, _ground_color(Vector2i(x, y)))

			var outline := shape.duplicate()
			outline.append(shape[0])  # back to the first corner to close the shape
			draw_polyline(outline, LINE_COLOR, 1.0)

	# Mycelium over the floor.
	for tile in mycelium:
		draw_colored_polygon(diamond(tile), MYCELIUM_COLOR)

	# Furnishings on top of the floor: see-through until built, solid once built.
	for furnishing in furnishings:
		var color: Color = furnishing["color"]
		if not furnishing["built"]:
			color.a = 0.35
		for tile in footprint(furnishing["origin"], furnishing["size"]):
			draw_colored_polygon(diamond(tile), color)
		# A door under attack shows its health.
		if furnishing["id"] == "door" and furnishing.get("health", DOOR_HEALTH) < DOOR_HEALTH:
			var spot := tile_to_screen(furnishing["origin"]) + Vector2(-30, -10)
			draw_rect(Rect2(spot, Vector2(60, 6)), Color(0.2, 0.2, 0.2))
			draw_rect(Rect2(spot, Vector2(60 * furnishing["health"] / DOOR_HEALTH, 6)), Color(0.95, 0.6, 0.2))

	# Items lying on the floor: a small diamond in the middle of the tile.
	for tile in items:
		var center := tile_to_screen(tile)
		var small := PackedVector2Array()
		for corner in diamond(tile):
			small.append(center + (corner - center) * 0.35)
		draw_colored_polygon(small, ITEM_COLORS[items[tile]["kind"]])

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
	if items.has(tile):
		return ITEM_COLORS[items[tile]["kind"]]  # so the fog remembers where items lie
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
