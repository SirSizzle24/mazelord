extends Node
## Dungeon-wide state: the mana pool, the troop types, and summoning.

signal mana_changed(new_amount: int)

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

@export var grid: Node2D
@export var unit_scene: PackedScene   # the unit "blueprint" to copy when summoning
@export var units_parent: Node2D      # where new units are placed in the scene tree

var mana := 100


## Spends mana if there's enough. Returns false, spending nothing, if there isn't.
func try_spend(amount: int) -> bool:
	if mana < amount:
		return false
	add_mana(-amount)
	return true


func add_mana(amount: int) -> void:
	mana += amount
	mana_changed.emit(mana)  # tell anyone listening, like the mana display


## Spends mana to create a troop at the summoning spot. Returns false if there isn't enough mana.
func summon(type_id: String) -> bool:
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
