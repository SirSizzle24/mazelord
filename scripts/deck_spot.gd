extends PanelContainer
## A deck's tray on the war table. The tray itself is in the table painting; this is the see-through
## area over it, placed by the roster: tap it to open that deck, or drop the middle card on it to move
## the troop there. Laid out in Scenes/deck_spot.tscn; restyle it freely, keeping the %Caption name.
## While a card is being dragged, every tray that can take it glows warm, and the one under your finger
## glows brighter and grows. The open deck's tray shows no caption: its cards are out on the table.

const HOVER_SCALE := 1.08
const GLOW_ALPHA := 0.16  # how strongly a tray glows while a card is in the air
const HOVER_GLOW_ALPHA := 0.32  # and the one under your finger

var roster: Node  # set before the spot enters the scene
var number := 0  # 1 to 5 for a flight, 0 for flightless
var caption := ""  # empty for the open deck's spot
var hovering := false
var dragging := false
var glow: StyleBoxFlat

@onready var caption_label: Label = %Caption


func _ready() -> void:
	glow = get_theme_stylebox("panel").duplicate()  # its own copy, so each tray glows on its own
	add_theme_stylebox_override("panel", glow)
	resized.connect(func(): pivot_offset = size / 2.0)  # grow from the middle
	if caption == "":
		caption_label.visible = false  # the open deck's tray: its cards are out on the table
	else:
		caption_label.text = caption
	mouse_exited.connect(func(): _set_hover(false))


func is_empty() -> bool:
	return caption == ""


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = not is_empty() and data is Dictionary and data.has("unit") \
		and is_instance_valid(data["unit"]) and not data["unit"].can_dig  # workers can't join flights
	_set_hover(ok)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	roster.card_dropped(number, data["unit"], get_global_rect().get_center())


func _gui_input(event: InputEvent) -> void:
	if not is_empty() and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		roster.open_deck(number)


## Every Control hears when any drag starts and ends: glow while a card is in the air.
func _notification(what: int) -> void:
	if is_empty():
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.has("unit") and not data["unit"].can_dig:
			dragging = true
			_update_glow()
	elif what == NOTIFICATION_DRAG_END:
		dragging = false
		_set_hover(false)
		_update_glow()


func _update_glow() -> void:
	var alpha := 0.0
	if dragging:
		alpha = HOVER_GLOW_ALPHA if hovering else GLOW_ALPHA
	create_tween().tween_property(glow, "bg_color:a", alpha, 0.1)


func _set_hover(on: bool) -> void:
	if on == hovering:
		return
	hovering = on
	create_tween().tween_property(self, "scale", Vector2.ONE * (HOVER_SCALE if on else 1.0), 0.08)
	_update_glow()


## A short bump, when a card lands here.
func pulse() -> void:
	scale = Vector2.ONE * 1.2
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(self, "scale", Vector2.ONE, 0.25)
