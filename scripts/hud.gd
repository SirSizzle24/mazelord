extends CanvasLayer
## The on-screen controls: mana display, summon buttons and the debug mana button.

@export var dungeon: Node

@onready var mana_label: Label = $ManaLabel


func _ready() -> void:
	dungeon.mana_changed.connect(_on_mana_changed)
	_on_mana_changed(dungeon.mana)  # show the starting amount

	# Each button calls the dungeon directly. func(): ... is a small unnamed function, like a Python lambda.
	$SummonWorkerButton.pressed.connect(func(): dungeon.summon("worker"))
	$SummonRoundheadButton.pressed.connect(func(): dungeon.summon("roundhead"))
	$DebugManaButton.pressed.connect(func(): dungeon.add_mana(100))


func _on_mana_changed(amount: int) -> void:
	mana_label.text = "Mana: %d" % amount
