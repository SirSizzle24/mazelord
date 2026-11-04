extends Node
## Dungeon-wide state: mana, food, the troop and furnishing types, and summoning.

signal mana_changed(new_amount: int)
signal food_changed(new_amount: int)
signal lore_found(text: String)
signal troop_summoned(unit: Node2D)  # the roster listens, to add a row

## Every troop type that can be summoned. Fungi only for now.
const TROOP_TYPES := {
	"worker": {"name": "Worker", "cost": 30, "color": Color(0.85, 0.55, 0.60), "can_dig": true,
		"health": 30.0, "damage": 3.0, "range": 50.0, "attack_interval": 1.2},
	"roundhead": {"name": "Roundhead", "cost": 20, "color": Color(0.55, 0.40, 0.30), "can_dig": false,
		"health": 60.0, "damage": 8.0, "range": 55.0, "attack_interval": 1.0},
}
## The generic raider for the prototype. Stats are placeholders to tune.
const RAIDER_STATS := {"health": 40.0, "damage": 6.0, "range": 52.0, "attack_interval": 1.0}
const RAIDER_MIN_DISTANCE := 10.0  # debug raiders appear at least this many tiles from the core

## Every furnishing that can be built. Size is in tiles along the grid; costs are placeholders to tune.
## Furnishings block movement unless they say "blocks": false.
const FURNISHINGS := {
	"soil_bed": {"name": "Damp soil bed", "size": Vector2i(1, 2), "cost": 10, "color": Color(0.36, 0.26, 0.18)},
	"mister": {"name": "Mister", "size": Vector2i(1, 1), "cost": 15, "color": Color(0.55, 0.75, 0.85)},
	"crop_bed": {"name": "Crop bed", "size": Vector2i(2, 2), "cost": 15, "color": Color(0.40, 0.60, 0.30)},
	"harvest_bin": {"name": "Harvest bin", "size": Vector2i(1, 1), "cost": 10, "color": Color(0.75, 0.60, 0.30)},
	"shelves": {"name": "Shelves", "size": Vector2i(1, 2), "cost": 10, "color": Color(0.55, 0.45, 0.35)},
	"crates": {"name": "Crates", "size": Vector2i(1, 1), "cost": 5, "color": Color(0.65, 0.50, 0.30)},
	"resource_vat": {"name": "Resource vat", "size": Vector2i(2, 2), "cost": 20, "color": Color(0.45, 0.35, 0.60)},
	"tables": {"name": "Tables and seats", "size": Vector2i(2, 2), "cost": 15, "color": Color(0.70, 0.45, 0.30)},
	"decorations": {"name": "Decorations", "size": Vector2i(1, 1), "cost": 10, "color": Color(0.85, 0.40, 0.60)},
	"rot_pit": {"name": "Rot pit", "size": Vector2i(2, 2), "cost": 20, "color": Color(0.30, 0.35, 0.20)},
	"mana_tap": {"name": "Mana tap", "size": Vector2i(1, 1), "cost": 25, "color": Color(0.55, 0.85, 1.0),
		"needs_deposit": true},
	"mycelium_source": {"name": "Mycelium source", "size": Vector2i(1, 1), "cost": 30, "color": Color(0.70, 0.55, 0.85)},
	"door": {"name": "Door", "size": Vector2i(1, 1), "cost": 5, "color": Color(0.50, 0.30, 0.15), "blocks": false},
}

## Every room type and the furnishings it needs (its minimum set). A room can hold extra items.
## If a room meets several sets, the type with the most matching items wins; ties go to the first listed.
const ROOM_TYPES := {
	"quarters": {"name": "Quarters", "needs": ["soil_bed", "mister"]},
	"farm": {"name": "Farm", "needs": ["crop_bed", "harvest_bin"]},
	"storage": {"name": "Storage", "needs": ["shelves", "crates", "resource_vat"]},
	"morale_room": {"name": "Morale room", "needs": ["tables", "decorations"]},
	"rotting_chamber": {"name": "Rotting chamber", "needs": ["rot_pit", "mister"]},
}

const SUMMON_TILE := Vector2i(30, 30)  # the summoning spot in the starting room (the grid's START_CENTER)

const FREE_TROOPS := 2  # troops you can have before beds are needed
const FARM_INTERVAL := 10.0  # seconds between harvests
const FOOD_PER_CROP_BED := 1  # food each crop bed in a farm adds per harvest
const EAT_INTERVAL := 20.0  # seconds between meals; each troop eats 1 food per meal
const MANA_INTERVAL := 5.0  # seconds between mana harvests from taps
const MANA_PER_TAP := 2  # mana each working tap adds per harvest
const MANA_CACHE := 30  # mana from a hauled mana cache
const FOOD_CACHE := 20  # food from a hauled food cache
## What the ruins say. Placeholders: yours to write. Ruins use these in order.
const LORE_TEXTS := ["[Lore 1]", "[Lore 2]", "[Lore 3]", "[Lore 4]", "[Lore 5]", "[Lore 6]"]

# Morale settles toward a target set by the dungeon; events push it away, and it drifts back.
# All placeholders to tune.
const BASE_MORALE := 50.0
const MORALE_PER_ROOM := 10.0  # each morale room raises the target
const HUNGER_PENALTY := 25.0  # target drops this much while food is at 0
const BED_PENALTY := 5.0  # target drops this much for each troop without a bed
const MORALE_DRIFT := 2.0  # points per second morale moves toward its target
const DEATH_HIT := 15.0
const NAMED_DEATH_HIT := 30.0
const FUNGI_DEATH_FACTOR := 0.5  # fungi see decay as good, so deaths hurt them half as much
const INJURY_HIT := 5.0
const HEALED_BOOST := 8.0  # healing lifts morale more than the injury cost

@export var grid: Node2D
@export var unit_scene: PackedScene   # the unit "blueprint" to copy when summoning
@export var units_parent: Node2D      # where new units are placed in the scene tree
@export var rooms: Node              # tells us which beds and crop beds are in working rooms
@export var dispatcher: Node         # hands out work; every new troop gets a link to it
@export var raider_scene: PackedScene
@export var fog: Node2D             # raiders hide in it, and debug raiders appear on seen ground

var mana := 100
var food := 20
var treasure := 0  # sellable finds, waiting for the merchant
var summoned_counts: Dictionary = {}  # type id -> how many have been summoned, for roster labels
var morale := BASE_MORALE
var farm_timer := 0.0
var mana_timer := 0.0
# Meals start out of step with harvests, so the two never land on the same frame and hide each other
# on the food display (troops seemed to stop eating when a harvest cancelled out a meal).
var eat_timer := EAT_INTERVAL - FARM_INTERVAL / 2.0


func _process(delta: float) -> void:
	morale = move_toward(morale, morale_target(), MORALE_DRIFT * delta)

	farm_timer += delta
	if farm_timer >= FARM_INTERVAL:
		farm_timer -= FARM_INTERVAL
		var grown: int = rooms.count_items("farm", "crop_bed") * FOOD_PER_CROP_BED
		if grown > 0:
			add_food(grown)

	mana_timer += delta
	if mana_timer >= MANA_INTERVAL:
		mana_timer -= MANA_INTERVAL
		var tapped: int = rooms.count_working_taps() * MANA_PER_TAP
		if tapped > 0:
			add_mana(tapped)

	eat_timer += delta
	if eat_timer >= EAT_INTERVAL:
		eat_timer -= EAT_INTERVAL
		var eaten: int = min(food, troop_count())  # can't eat more than there is
		if eaten > 0:
			add_food(-eaten)


## Where morale settles if nothing happens: better with morale rooms, worse when hungry or short of beds.
func morale_target() -> float:
	var target: float = BASE_MORALE + MORALE_PER_ROOM * rooms.count_rooms("morale_room")
	if food == 0 and troop_count() > 0:
		target -= HUNGER_PENALTY
	var missing_beds: int = max(0, troop_count() - rooms.count_items("quarters", "soil_bed"))
	target -= BED_PENALTY * missing_beds
	return clamp(target, 0.0, 100.0)


## Pushes morale up or down right now; it then drifts back toward its target.
func shift_morale(amount: float) -> void:
	morale = clamp(morale + amount, 0.0, 100.0)


# Hooks for raids and the hospital to call later. Nothing calls them yet.
func on_troop_died(troop_type_id: String, is_named: bool) -> void:
	var hit := NAMED_DEATH_HIT if is_named else DEATH_HIT
	if troop_type_id in ["worker", "roundhead"]:  # the fungi troops; replace with a class check later
		hit *= FUNGI_DEATH_FACTOR
	shift_morale(-hit)


func on_troop_injured() -> void:
	shift_morale(-INJURY_HIT)


func on_troop_healed() -> void:
	shift_morale(HEALED_BOOST)


func add_food(amount: int) -> void:
	food += amount
	food_changed.emit(food)


## A hauled item arrives in storage, and only now takes effect.
func receive_item(item: Dictionary) -> void:
	match item["kind"]:
		"mana_cache":
			add_mana(MANA_CACHE)
		"food_cache":
			add_food(FOOD_CACHE)
		"treasure":
			treasure += 1
		"lore":
			lore_found.emit(LORE_TEXTS[item["lore_index"] % LORE_TEXTS.size()])


## Debug: drops a raider on a random seen floor tile far enough from the core. Returns false if none fits.
func spawn_raider() -> bool:
	var spots: Array[Vector2i] = []
	for x in grid.GRID_WIDTH:
		for y in grid.GRID_HEIGHT:
			var tile := Vector2i(x, y)
			if grid.is_floor(tile) and fog.is_known(tile) and tile.distance_to(grid.START_CENTER) >= RAIDER_MIN_DISTANCE:
				spots.append(tile)
	if spots.is_empty():
		return false
	var raider: Node2D = raider_scene.instantiate()
	raider.grid = grid
	raider.fog = fog
	raider.set_stats(RAIDER_STATS)
	raider.position = grid.tile_to_screen(spots.pick_random())
	units_parent.add_child(raider)
	return true


func troop_count() -> int:
	return get_tree().get_nodes_in_group("units").size()


## How many troops you can have: FREE_TROOPS, or one per soil bed in quarters, whichever is higher.
## Your first beds house the troops you already have; only beds beyond FREE_TROOPS raise the cap.
func troop_cap() -> int:
	return max(FREE_TROOPS, rooms.count_items("quarters", "soil_bed"))


## Spends mana if there's enough. Returns false, spending nothing, if there isn't.
func try_spend(amount: int) -> bool:
	if mana < amount:
		return false
	add_mana(-amount)
	return true


func add_mana(amount: int) -> void:
	mana += amount
	mana_changed.emit(mana)  # tell anyone listening, like the mana display


## Spends mana to create a troop at the summoning spot.
## Returns false if there isn't enough mana or no room for another troop.
func summon(type_id: String) -> bool:
	if troop_count() >= troop_cap():
		return false  # needs more beds
	var troop_type: Dictionary = TROOP_TYPES[type_id]
	if mana < troop_type["cost"]:
		return false
	add_mana(-troop_type["cost"])

	var unit: Node2D = unit_scene.instantiate()
	unit.grid = grid
	unit.start_tile = SUMMON_TILE
	unit.dispatcher = dispatcher
	unit.dungeon = self
	unit.setup(type_id, troop_type)
	# Troops are unnamed until they earn fame, so the roster calls them "Worker 1", "Roundhead 2"...
	summoned_counts[type_id] = summoned_counts.get(type_id, 0) + 1
	unit.roster_label = "%s %d" % [troop_type["name"], summoned_counts[type_id]]
	units_parent.add_child(unit)  # the unit's _ready runs here
	troop_summoned.emit(unit)
	return true
