extends CanvasLayer
## The on-screen controls: mana, food and troop displays, summon buttons and the debug mana button.

## Morale is hidden from players by design; they learn it from how troops behave.
## Keep this on while developing to see the number, and off to play as a player would.
const SHOW_DEBUG_STATS := true

@export var dungeon: Node
@export var fog: Node2D

@onready var mana_label: Label = $ManaLabel
@onready var food_label: Label = $FoodLabel
@onready var troop_label: Label = $TroopLabel
@onready var hunger_warning: Label = $HungerWarning
@onready var morale_label: Label = $MoraleLabel
@onready var treasure_label: Label = $TreasureLabel
@onready var lore_label: Label = $LoreLabel

const LORE_SHOW_TIME := 6.0  # seconds a found lore note stays on screen
var lore_time_left := 0.0


func _ready() -> void:
	dungeon.mana_changed.connect(_on_mana_changed)
	_on_mana_changed(dungeon.mana)  # show the starting amount
	dungeon.food_changed.connect(_on_food_changed)
	_on_food_changed(dungeon.food)

	# Each button calls the dungeon directly. func(): ... is a small unnamed function, like a Python lambda.
	$SummonWorkerButton.pressed.connect(func(): dungeon.summon("worker"))
	$SummonRoundheadButton.pressed.connect(func(): dungeon.summon("roundhead"))
	$DebugManaButton.pressed.connect(func(): dungeon.add_mana(100))
	$DebugFogButton.toggled.connect(fog.set_fog_enabled)  # pressed = fog on
	$DebugRaiderButton.pressed.connect(func(): dungeon.spawn_raider())
	dungeon.lore_found.connect(_on_lore_found)
	lore_label.visible = false


func _on_lore_found(text: String) -> void:
	lore_label.text = text
	lore_label.visible = true
	lore_time_left = LORE_SHOW_TIME


func _process(delta: float) -> void:
	treasure_label.text = "Treasure: %d" % dungeon.treasure
	if lore_time_left > 0.0:
		lore_time_left -= delta
		if lore_time_left <= 0.0:
			lore_label.visible = false
	# The troop count and cap come from several things (summons, beds, rooms), so they're simplest
	# to read fresh each frame rather than tracking every change with signals.
	troop_label.text = "Troops: %d / %d" % [dungeon.troop_count(), dungeon.troop_cap()]
	hunger_warning.visible = dungeon.food == 0 and dungeon.troop_count() > 0
	# Morale drifts every frame, so it's read fresh too. Shown with its target to make the drift visible.
	morale_label.visible = SHOW_DEBUG_STATS
	morale_label.text = "[debug] Morale: %d (heading to %d)" % [roundi(dungeon.morale), roundi(dungeon.morale_target())]


func _on_food_changed(amount: int) -> void:
	food_label.text = "Food: %d" % amount


func _on_mana_changed(amount: int) -> void:
	mana_label.text = "Mana: %d" % amount
