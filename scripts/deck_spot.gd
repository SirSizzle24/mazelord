extends PanelContainer
## A deck spot above the roster: tap it to open that deck, or drop the middle card on it to move the
## troop there. Laid out in Scenes/deck_spot.tscn; restyle it freely, keeping the %Caption name.
## While a card is being dragged, every spot that can take it glows, and the one under your finger grows.
## The open deck's spot is empty: an outline with nothing to tap or drop on.

const HOVER_SCALE := 1.1
const GLOW := Color(1.3, 1.2, 0.85)  # tint while a drag is in progress
const EMPTY_OUTLINE := Color(1.0, 1.0, 1.0, 0.15)

var roster: Node  # set before the spot enters the scene
var number := 0  # 1 to 5 for a flight, 0 for flightless
var caption := ""  # empty for the open deck's spot
var hovering := false

@onready var caption_label: Label = %Caption


func _ready() -> void:
	pivot_offset = custom_minimum_size / 2.0  # grow from the middle
	if caption == "":
		var outline := StyleBoxFlat.new()
		outline.draw_center = false
		outline.set_border_width_all(2)
		outline.border_color = EMPTY_OUTLINE
		outline.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", outline)
		caption_label.visible = false
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
		if data is Dictionary and data.has("unit"):
			modulate = GLOW
	elif what == NOTIFICATION_DRAG_END:
		modulate = Color.WHITE
		_set_hover(false)


func _set_hover(on: bool) -> void:
	if on == hovering:
		return
	hovering = on
	create_tween().tween_property(self, "scale", Vector2.ONE * (HOVER_SCALE if on else 1.0), 0.08)


## A short bump, when a card lands here.
func pulse() -> void:
	scale = Vector2.ONE * 1.2
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(self, "scale", Vector2.ONE, 0.25)
