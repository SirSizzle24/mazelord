extends Node
## Dungeon-wide state: the mana pool, the troop types, and summoning.

signal mana_changed(new_amount: int)

## Every troop type that can be summoned. Fungi only for now.
const TROOP_TYPES := {
	"worker": {"name": "Worker", "cost": 30, "color": Color(0.85, 0.55, 0.60), "can_dig": true},
	"roundhead": {"name": "Roundhead", "cost": 20, "color": Color(0.55, 0.40, 0.30), "can_dig": false},
}
const SUMMON_TILE := Vector2i(10, 10)  # the summoning spot in the starting room

@export var grid: Node2D
@export var unit_scene: PackedScene   # the unit "blueprint" to copy when summoning
@export var units_parent: Node2D      # where new units are placed in the scene tree

var mana := 100


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
