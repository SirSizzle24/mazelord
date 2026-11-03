extends Node
## Dungeon-wide state: mana, food, the troop and furnishing types, and summoning.

signal mana_changed(new_amount: int)
signal food_changed(new_amount: int)

## Every troop type that can be summoned. Fungi only for now.
const TROOP_TYPES := {
	"worker": {"name": "Worker", "cost": 30, "color": Color(0.85, 0.55, 0.60), "can_dig": true},
	"roundhead": {"name": "Roundhead", "cost": 20, "color": Color(0.55, 0.40, 0.30), "can_dig": false},
}
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

const SUMMON_TILE := Vector2i(10, 10)  # the summoning spot in the starting room

const FREE_TROOPS := 2  # troops you can have before beds are needed
const FARM_INTERVAL := 10.0  # seconds between harvests
const FOOD_PER_CROP_BED := 1  # food each crop bed in a farm adds per harvest
const EAT_INTERVAL := 20.0  # seconds between meals; each troop eats 1 food per meal

@export var grid: Node2D
@export var unit_scene: PackedScene   # the unit "blueprint" to copy when summoning
@export var units_parent: Node2D      # where new units are placed in the scene tree
@export var rooms: Node              # tells us which beds and crop beds are in working rooms

var mana := 100
var food := 20
var farm_timer := 0.0
# Meals start out of step with harvests, so the two never land on the same frame and hide each other
# on the food display (troops seemed to stop eating when a harvest cancelled out a meal).
var eat_timer := EAT_INTERVAL - FARM_INTERVAL / 2.0


func _process(delta: float) -> void:
	farm_timer += delta
	if farm_timer >= FARM_INTERVAL:
		farm_timer -= FARM_INTERVAL
		var grown: int = rooms.count_items("farm", "crop_bed") * FOOD_PER_CROP_BED
		if grown > 0:
			add_food(grown)

	eat_timer += delta
	if eat_timer >= EAT_INTERVAL:
		eat_timer -= EAT_INTERVAL
		var eaten: int = min(food, troop_count())  # can't eat more than there is
		if eaten > 0:
			add_food(-eaten)


func add_food(amount: int) -> void:
	food += amount
	food_changed.emit(food)


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
	unit.setup(type_id, troop_type)
	units_parent.add_child(unit)  # the unit's _ready runs here
	return true
