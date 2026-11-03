extends CanvasLayer
## The on-screen controls: mana, food and troop displays, summon buttons and the debug mana button.

@export var dungeon: Node

@onready var mana_label: Label = $ManaLabel
@onready var food_label: Label = $FoodLabel
@onready var troop_label: Label = $TroopLabel
@onready var hunger_warning: Label = $HungerWarning


func _ready() -> void:
	dungeon.mana_changed.connect(_on_mana_changed)
	_on_mana_changed(dungeon.mana)  # show the starting amount
	dungeon.food_changed.connect(_on_food_changed)
	_on_food_changed(dungeon.food)

	# Each button calls the dungeon directly. func(): ... is a small unnamed function, like a Python lambda.
	$SummonWorkerButton.pressed.connect(func(): dungeon.summon("worker"))
	$SummonRoundheadButton.pressed.connect(func(): dungeon.summon("roundhead"))
	$DebugManaButton.pressed.connect(func(): dungeon.add_mana(100))


func _process(_delta: float) -> void:
	# The troop count and cap come from several things (summons, beds, rooms), so they're simplest
	# to read fresh each frame rather than tracking every change with signals.
	troop_label.text = "Troops: %d / %d" % [dungeon.troop_count(), dungeon.troop_cap()]
	hunger_warning.visible = dungeon.food == 0 and dungeon.troop_count() > 0


func _on_food_changed(amount: int) -> void:
	food_label.text = "Food: %d" % amount


func _on_mana_changed(amount: int) -> void:
	mana_label.text = "Mana: %d" % amount
