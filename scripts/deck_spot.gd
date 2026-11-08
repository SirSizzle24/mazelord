extends Control
## A deck's tray on the war table. The tray itself is in the table painting; this sits over it, placed
## by the roster, and shows the deck lying on it: its first few cards, stacked, with the deck's name on
## the crossbar. Tap it to open that deck, or drop the middle card on it to move the troop there.
## The open deck's tray is bare (its cards are out on the table) and takes no taps or drops.
## While a card is being dragged, every tray that can take it glows in the tray's own shape (%Glow uses
## a mask cut from the painting), and the one under your finger glows brighter and grows.
##
## The stack is drawn in perspective, lying on the slab: it's built flat in a small offscreen viewport,
## then drawn by perspective.gdshader so its corners land on the slab's corners (measured from the
## painting), far end narrower, like the trays themselves.
## Laid out in Scenes/deck_spot.tscn; restyle it freely, keeping the %Glow and %Caption names.

const PerspectiveShader := preload("res://scripts/perspective.gdshader")
const HOVER_SCALE := 1.06
const GLOW_ALPHA := 0.35  # how strongly a tray glows while a card is in the air
const HOVER_GLOW_ALPHA := 0.7  # and the one under your finger
const CARD_SCALE := 0.5  # the flat stack's cards, against a full card: about twice their size on screen
const STACK_HEIGHT := 0.84  # how much of the slab's length the stack covers, so stone shows around it
const CARD_THICKNESS := 1.2  # pixels (in the flat deck) each card adds to the deck's thickness
const MIN_THICKNESS := 3.0
const MAX_THICKNESS := 16.0
const SIDE_VIEW := 1.6  # how much side shows on the outermost trays, against the near edge
const EDGE_COLOR := Color(0.12, 0.10, 0.09)
const EDGE_LINE := Color(0.42, 0.36, 0.28, 0.5)

var roster: Node  # set before the spot enters the scene
var number := 0  # 1 to 5 for a flight, 0 for flightless
var caption := ""  # the deck's name and count, on the crossbar
var open := false  # the deck out on the table: the tray is bare
var mask: Texture2D  # the tray's shape, for the glow
var cards: Array = []  # the deck's troops, first on top
var side := 0.0  # where the tray sits across the table: -1 far left, 0 middle, 1 far right
## The slab's corners in the painting, as fractions of this spot's size: top-left, top-right,
## bottom-right, bottom-left.
var slab_corners := PackedVector2Array([Vector2(0.15, 0.26), Vector2(0.85, 0.26), Vector2(0.88, 0.86),
	Vector2(0.12, 0.86)])
var hovering := false
var dragging := false
var warp: ColorRect  # draws the flat stack in perspective
var flat_size := Vector2.ZERO  # the flat stack's size

@onready var glow: TextureRect = %Glow
@onready var caption_label: Label = %Caption


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if open else Control.MOUSE_FILTER_STOP
	glow.texture = mask
	caption_label.text = caption
	resized.connect(_layout)
	if not open and not cards.is_empty():
		_build_stack()
	_layout()


## The deck, built flat in an offscreen viewport: a soft shadow, the deck's edges, then its top card.
## The deck has thickness (more cards, thicker), so the top card sits above the bottom one: shifted up
## the slab, because the camera looks from the near side of the table, and sideways, away from the
## middle of the table, because the camera sits over the middle. That uncovers the edges you'd really
## see: the near edge always, and the side facing the middle (the right side on the left trays, the
## left side on the right trays, almost none in the middle).
func _build_stack() -> void:
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	add_child(viewport)
	var thickness: float = clampf(cards.size() * CARD_THICKNESS, MIN_THICKNESS, MAX_THICKNESS)
	var lift := Vector2(side * thickness * SIDE_VIEW, -thickness)  # top card, from the bottom card
	var probe: Control = roster.new_card(cards[0], false, viewport, true)  # the top card, added last below
	var card_size: Vector2 = probe.custom_minimum_size * CARD_SCALE
	viewport.remove_child(probe)
	# The bottom card's corner, so everything fits in the viewport with the top card shifted.
	var base := Vector2(maxf(0.0, -lift.x), -lift.y)
	var shadow := Panel.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	look.set_corner_radius_all(6)
	shadow.add_theme_stylebox_override("panel", look)
	shadow.position = base + Vector2(0, 4)
	shadow.size = card_size
	viewport.add_child(shadow)
	var edges := Control.new()  # draws the deck's near edge and its side
	edges.size = card_size + Vector2(absf(lift.x), -lift.y) + Vector2(0, 8)
	edges.draw.connect(_draw_edges.bind(edges, base, card_size, lift, cards.size()))
	viewport.add_child(edges)
	probe.scale = Vector2.ONE * CARD_SCALE
	probe.position = base + lift
	viewport.add_child(probe)
	flat_size = card_size + Vector2(absf(lift.x), -lift.y) + Vector2(0, 4)
	viewport.size = Vector2i(ceili(flat_size.x), ceili(flat_size.y))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE  # it never moves; draw it once

	warp = ColorRect.new()
	warp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warp.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = PerspectiveShader
	material.set_shader_parameter("picture", viewport.get_texture())
	warp.material = material
	add_child(warp)
	move_child(warp, caption_label.get_index())  # over the glow, under the caption


## The deck's visible edges: each is the strip between the bottom card's edge and the top card's,
## dark like the frames' stone, with faint lines where the cards meet.
func _draw_edges(edges: Control, base: Vector2, card: Vector2, lift: Vector2, count: int) -> void:
	var bottom_left := base + Vector2(0, card.y)
	var bottom_right := base + card
	var near := PackedVector2Array([bottom_left, bottom_right, bottom_right + lift, bottom_left + lift])
	edges.draw_colored_polygon(near, EDGE_COLOR)
	if absf(lift.x) > 0.5:
		# The side facing the middle of the table: the right side when the top card shifted left.
		var x := base.x + (card.x if lift.x < 0.0 else 0.0)
		var low := Vector2(x, base.y + card.y)
		var high := Vector2(x, base.y)
		edges.draw_colored_polygon(PackedVector2Array([high, low, low + lift, high + lift]),
			EDGE_COLOR.darkened(0.4))
	var lines: int = min(count, 12) - 1
	for n in lines:
		var t := float(n + 1) / float(lines + 1)
		edges.draw_line(bottom_left + lift * t, bottom_right + lift * t, EDGE_LINE, 1.0)


## Works out where the flat stack lands: a card-shaped area centered on the slab, in the slab's
## perspective. The slab's own shape on screen is its four corners; the card area inside it keeps the
## stack's proportions, measured along the slab.
func _layout() -> void:
	pivot_offset = size / 2.0  # grow from the middle
	if warp == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var c := slab_corners
	# The slab's rough proportions on screen (width over length), to keep the stack from stretching.
	var slab_width: float = ((c[1].x - c[0].x) + (c[2].x - c[3].x)) / 2.0 * size.x
	var slab_length: float = ((c[3].y - c[0].y) + (c[2].y - c[1].y)) / 2.0 * size.y
	var high := STACK_HEIGHT
	var wide: float = high * (flat_size.x / flat_size.y) * slab_length / slab_width
	var to_slab := _square_to_quad(c)  # a spot on the slab (0 to 1 each way) to a spot on this node
	# The stack's own 0..1 to a spot on the slab: centered, wide x high.
	var into_slab := Basis(Vector3(wide, 0.0, 0.0), Vector3(0.0, high, 0.0),
		Vector3((1.0 - wide) / 2.0, (1.0 - high) / 2.0, 1.0))
	warp.material.set_shader_parameter("to_picture", (to_slab * into_slab).inverse())


## The perspective map that takes the unit square's corners (0,0), (1,0), (1,1), (0,1) to these four
## points, in that order: the standard square-to-quad formula (Heckbert, 1989). Columns are the matrix's.
func _square_to_quad(q: PackedVector2Array) -> Basis:
	var dx1 := q[1].x - q[2].x
	var dx2 := q[3].x - q[2].x
	var dx3 := q[0].x - q[1].x + q[2].x - q[3].x
	var dy1 := q[1].y - q[2].y
	var dy2 := q[3].y - q[2].y
	var dy3 := q[0].y - q[1].y + q[2].y - q[3].y
	var den := dx1 * dy2 - dx2 * dy1
	var g := (dx3 * dy2 - dx2 * dy3) / den
	var h := (dx1 * dy3 - dx3 * dy1) / den
	return Basis(
		Vector3(q[1].x - q[0].x + g * q[1].x, q[1].y - q[0].y + g * q[1].y, g),
		Vector3(q[3].x - q[0].x + h * q[3].x, q[3].y - q[0].y + h * q[3].y, h),
		Vector3(q[0].x, q[0].y, 1.0))


func is_empty() -> bool:
	return open


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = not open and data is Dictionary and data.has("unit") \
		and is_instance_valid(data["unit"]) and not data["unit"].can_dig  # workers can't join flights
	_set_hover(ok)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	roster.card_dropped(number, data["unit"], get_global_rect().get_center())


func _gui_input(event: InputEvent) -> void:
	if not open and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		roster.open_deck(number)


## Every Control hears when any drag starts and ends: glow while a card is in the air.
func _notification(what: int) -> void:
	if open:
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
	elif what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(false)


func _update_glow() -> void:
	var alpha := 0.0
	if dragging:
		alpha = HOVER_GLOW_ALPHA if hovering else GLOW_ALPHA
	create_tween().tween_property(glow, "modulate:a", alpha, 0.1)


func _set_hover(on: bool) -> void:
	if on == hovering:
		return
	hovering = on
	create_tween().tween_property(self, "scale", Vector2.ONE * (HOVER_SCALE if on else 1.0), 0.08)
	_update_glow()


## A short bump, when a card lands here.
func pulse() -> void:
	scale = Vector2.ONE * 1.15
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(self, "scale", Vector2.ONE, 0.25)
