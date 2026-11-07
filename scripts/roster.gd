extends PanelContainer
## The roster: your troops as trading cards in six decks, one per flight plus the flightless deck
## (fighters in no flight, then workers). The card you're looking at hovers large in the middle, with the
## cards you've passed in a face-up pile on the left and the cards still to come in a face-up pile on the
## right. Swipe the middle card: it follows your finger, and past a point it slides onto a pile while the
## next card rises from the other. Above sit spots for the six decks, the open one left empty: tap a spot
## to open that deck, or pull the middle card up and drop it on one to move the troop there.
## Long-press a troop on the map to open the roster at its card.
##
## The roster takes the whole screen: a stone war table in candlelight, with the decks' trays along the
## far edge. The game keeps running behind it, so the bottom bar shows the raid clock.
## The screen's layout lives in Scenes/roster.tscn and each card's in Scenes/card.tscn, so both can be
## restyled in the editor. The code finds the parts by their unique names (%DeckSpots and so on).
## The table is your render (Assets/UI/roster_table.png), kept at its own shape and cropped to fill the
## screen. Its lighting is added here: a warm pool in the middle, the candle's glow (which flickers), the
## lantern's red glow, and a vignette, all as see-through layers over the picture.

const CardScene := preload("res://Scenes/card.tscn")
const DeckSpotScene := preload("res://Scenes/deck_spot.tscn")
## Each tray's slab corners, as fractions of the tray's rect: top-left, top-right, bottom-right,
## bottom-left (x, y each). The cards lying on it are drawn in this perspective. The camera sits over the
## middle of the table, so the slabs fan out: the middle ones point straight at you, the outer ones lean
## outward, and every slab is a touch wider at the near (bottom) end. Each slab's lean was measured from
## its right edge in the painting (the left edges are blurred by the trays' shadows, which is what made
## every stack lean left before); the left edge is given the same lean.
const TRAY_SLABS := [
	[0.145, 0.2, 0.825, 0.2, 0.751, 0.8, -0.01, 0.8],
	[0.155, 0.2, 0.845, 0.2, 0.809, 0.8, 0.049, 0.8],
	[0.155, 0.2, 0.845, 0.2, 0.855, 0.8, 0.1, 0.8],
	[0.155, 0.2, 0.845, 0.2, 0.897, 0.8, 0.145, 0.8],
	[0.155, 0.2, 0.845, 0.2, 0.927, 0.8, 0.207, 0.8],
	[0.155, 0.2, 0.845, 0.2, 1.002, 0.8, 0.252, 0.8],
]
## Each tray's shape, cut from the table picture, for its glow (in DECK_ORDER).
const TRAY_MASKS := [preload("res://Assets/UI/Trays/tray_1.png"), preload("res://Assets/UI/Trays/tray_2.png"),
	preload("res://Assets/UI/Trays/tray_3.png"), preload("res://Assets/UI/Trays/tray_4.png"),
	preload("res://Assets/UI/Trays/tray_5.png"), preload("res://Assets/UI/Trays/tray_6.png")]
const ELEMENTS_PER_FLIGHT := 4
const DECK_ORDER := [1, 2, 3, 4, 5, 0]  # the spots, left to right: flights, then flightless
## Where each tray is in the table painting (roster_table.png), as fractions of the picture's width and
## height, in DECK_ORDER. The spots sit on these, so they follow the picture however it's cropped.
const TRAY_RECTS := [
	Rect2(0.181, 0.0, 0.100, 0.276),
	Rect2(0.2885, 0.0, 0.094, 0.276),
	Rect2(0.392, 0.0, 0.0955, 0.276),
	Rect2(0.496, 0.0, 0.095, 0.276),
	Rect2(0.599, 0.0, 0.096, 0.276),
	Rect2(0.702, 0.0, 0.0965, 0.276),
]
const REFRESH_TIME := 0.5  # seconds between updates of the cards' text while open
const PILE_SCALE := 0.62  # pile cards are the middle card shrunk
const PILE_OFFSET := 8.0  # pixels each card down a pile is shifted, down and right
const PILE_DEPTH := 3  # how many cards each pile shows stacked; the rest are counted
const FLY_TIME := 0.22  # seconds for a card to slide between the middle and a pile
const DROP_TIME := 0.25  # seconds for a dropped card to shrink into its deck spot
const FLICKER := 0.35  # how much the candlelight wavers
const FLICKER_SPEED := 2.5  # how fast it wavers
const RAID_WARNING := 30.0  # seconds before a raid when the clock turns red
## Debug: the first three cards of every deck show as unnamed, named and hero, to compare the frames.
## Set false once heroes exist.
const DEBUG_TIERS := true

@export var dungeon: Node
@export var roster_button: Button
@export var raids: Node  # for the raid clock in the top bar

var current_deck := 0  # the open deck: 1 to 5 for that flight, 0 for flightless
var deck: Array = []  # the troops in the open deck, in order
var index := 0  # which of them is in the middle
var center_card: Control = null
var dragged_card: Control = null  # the middle card while it's being dragged onto a spot
var animating := false  # a card is sliding; swipes wait until it lands
var refresh_left := 0.0
var card_size := Vector2.ZERO  # the card scene's size, read once from the scene itself
var flicker_noise := FastNoiseLite.new()
var flicker_time := 0.0

@onready var deck_spots: Control = %DeckSpots  # spots are pinned over the trays in the table picture
@onready var left_pile: Control = %LeftPile
@onready var right_pile: Control = %RightPile
@onready var stage: Control = %CardStage  # where the middle card sits
@onready var count_label: Label = %CountLabel
@onready var fly_layer: Control = %FlyLayer  # over everything, so sliding cards pass above the piles
@onready var close_button: Button = %CloseButton
@onready var raid_label: Label = %RaidLabel
@onready var candle_light: CanvasItem = %CandleLight


func _ready() -> void:
	visible = false
	var probe := CardScene.instantiate()
	card_size = probe.custom_minimum_size
	probe.free()
	roster_button.toggled.connect(_on_roster_toggled)
	close_button.pressed.connect(func(): roster_button.button_pressed = false)
	dungeon.troop_summoned.connect(_on_troop_summoned)


func _on_troop_summoned(_unit: Node2D) -> void:
	if visible:
		_rebuild()


func _on_roster_toggled(toggled_on: bool) -> void:
	visible = toggled_on
	if toggled_on:
		move_to_front()  # over the HUD and debug buttons (the naming panel brings itself in front of this)
		_rebuild()


## Opens the roster at this troop's card, in its deck.
func open_for(unit: Node2D) -> void:
	current_deck = unit.flight
	if not roster_button.button_pressed:
		roster_button.button_pressed = true  # opening runs _rebuild
	_rebuild(unit)


## Opens a deck: 1 to 5 for a flight, 0 for flightless. Tapping a deck spot does this.
func open_deck(number: int) -> void:
	if animating:
		return
	current_deck = number
	index = 0
	deck = []  # forget the old deck, so _rebuild starts at its first card
	_rebuild()


## The troops in a deck. A flight's deck is in element order; the flightless deck is fighters, then workers.
func _collect(number: int) -> Array:
	var troops: Array = get_tree().get_nodes_in_group("units")
	if number == 0:
		var fighters := troops.filter(func(unit): return not unit.can_dig and unit.flight == 0)
		var workers := troops.filter(func(unit): return unit.can_dig)
		return fighters + workers
	var members := troops.filter(func(unit): return unit.flight == number)
	members.sort_custom(func(a, b): return a.element < b.element)
	return members


## Gathers the deck again and redraws, keeping the same troop in the middle if it's still in this deck
## (or the one asked for).
func _rebuild(keep: Node2D = null) -> void:
	if keep == null and index < deck.size() and is_instance_valid(deck[index]):
		keep = deck[index]
	deck = _collect(current_deck)
	if keep != null and deck.has(keep):
		index = deck.find(keep)
	else:
		index = clampi(index, 0, max(deck.size() - 1, 0))
	_rebuild_spots()
	_show_card()


func _rebuild_spots() -> void:
	for child in deck_spots.get_children():
		child.queue_free()
	for i in DECK_ORDER.size():
		var n: int = DECK_ORDER[i]
		var spot := DeckSpotScene.instantiate()
		spot.roster = self
		spot.number = n
		spot.mask = TRAY_MASKS[i]
		var slab: Array = TRAY_SLABS[i]
		spot.slab_corners = PackedVector2Array([Vector2(slab[0], slab[1]), Vector2(slab[2], slab[3]),
			Vector2(slab[4], slab[5]), Vector2(slab[6], slab[7])])
		var members := _collect(n)
		var deck_name := "Flight %d" % n if n > 0 else "Flightless"
		spot.caption = "%s · %d" % [deck_name, members.size()]
		spot.open = n == current_deck  # its cards are out on the table, so its tray is bare
		spot.cards = members
		# Pinned to its tray in the picture: anchors are fractions of the picture's size.
		var tray: Rect2 = TRAY_RECTS[i]
		spot.anchor_left = tray.position.x
		spot.anchor_top = tray.position.y
		spot.anchor_right = tray.end.x
		spot.anchor_bottom = tray.end.y
		deck_spots.add_child(spot)
		spot.offset_left = 0.0
		spot.offset_top = 0.0
		spot.offset_right = 0.0
		spot.offset_bottom = 0.0


func _spot_for(number: int) -> Control:
	for spot in deck_spots.get_children():
		if spot.number == number and not spot.is_queued_for_deletion():
			return spot
	return null


## Makes a card for a troop and puts it under parent. mini is for the trays' stacks: no text, just the
## frame, the portrait and the rank, since words can't be read that small.
func new_card(unit: Node2D, large: bool, parent: Node, mini := false) -> Control:
	var card := CardScene.instantiate()
	card.roster = self
	card.unit = unit
	card.large = large
	card.mini = mini
	if DEBUG_TIERS and deck.find(unit) in [0, 1, 2]:
		card.tier_override = deck.find(unit)
	parent.add_child(card)  # its _ready fills it in
	return card


## Where a middle card rests: centered on the stage.
func _rest_position(card: Control) -> Vector2:
	return (stage.custom_minimum_size - card.custom_minimum_size) / 2.0


## Where to put a card (by its position) so that, at this scale, its top-left corner lands on corner.
## A card scales around its pivot, so the corner moves when the scale changes.
func _position_for(card: Control, corner: Vector2, at_scale: float) -> Vector2:
	return corner - card.pivot_offset * (1.0 - at_scale)


## Puts the current card in the middle and fills both piles, without animating.
func _show_card() -> void:
	for child in stage.get_children():
		child.queue_free()
	center_card = null
	_update_count()
	if deck.is_empty():
		var empty := Label.new()
		empty.text = "No troops in this deck"
		empty.position = stage.custom_minimum_size / 2.0 - Vector2(90, 10)
		stage.add_child(empty)
		_fill_pile(left_pile, [])
		_fill_pile(right_pile, [])
		return
	center_card = new_card(deck[index], true, stage)
	center_card.rest_position = _rest_position(center_card)
	center_card.position = center_card.rest_position
	_fill_pile(left_pile, _behind())
	_fill_pile(right_pile, _ahead())


func _behind() -> Array:
	var cards := deck.slice(0, index)
	cards.reverse()  # the card just passed is on top
	return cards


func _ahead() -> Array:
	return deck.slice(index + 1)


func _update_count() -> void:
	count_label.text = "%d / %d" % [index + 1, deck.size()] if not deck.is_empty() else ""


## Where a pile's top card sits (its corner, inside the pile) when the pile holds count cards. The bottom
## card stays put and each card above sits a little higher and further left, so a pile grows upward.
func _pile_top(count: int) -> Vector2:
	return Vector2.ONE * PILE_OFFSET * (PILE_DEPTH - min(PILE_DEPTH, count))


## Stacks the first few cards face up, the first on top.
func _fill_pile(pile: Control, cards: Array) -> void:
	for child in pile.get_children():
		child.queue_free()
	var shown: int = min(PILE_DEPTH, cards.size())
	for i in range(shown - 1, -1, -1):  # the bottom card first, so the top one draws last
		var card := new_card(cards[i], false, pile)
		card.scale = Vector2.ONE * PILE_SCALE
		card.position = _pile_top(shown) + Vector2(i, i) * PILE_OFFSET  # i = 0 is the top card
	if cards.size() > PILE_DEPTH:
		var more := Label.new()
		more.text = "+%d more" % (cards.size() - PILE_DEPTH)
		more.position = Vector2(0, card_size.y * PILE_SCALE + PILE_DEPTH * PILE_OFFSET)
		pile.add_child(more)


## Moves a card to another parent without it jumping on screen.
func _move_to(card: Control, parent: Node) -> void:
	var at := card.global_position
	card.get_parent().remove_child(card)
	parent.add_child(card)
	card.global_position = at


## Flips through the deck: 1 for the next card, -1 for the previous one. The middle card slides onto
## the pile behind it while the next card rises from the other pile into the middle.
func flip(step: int) -> void:
	var next := index + step
	if animating or center_card == null or next < 0 or next >= deck.size():
		if center_card != null:
			center_card.spring_back()  # the end of the deck: nowhere to go
		return
	animating = true
	var to_pile: Control = left_pile if step > 0 else right_pile
	var from_pile: Control = right_pile if step > 0 else left_pile
	var outgoing := center_card
	var from_count: int = (_ahead() if step > 0 else _behind()).size()  # before the flip
	index = next
	_update_count()
	var to_count: int = (_behind() if step > 0 else _ahead()).size()  # after it, with the card landed

	# The incoming card starts exactly where the top of its pile was, at pile size.
	var incoming := new_card(deck[index], true, fly_layer)
	incoming.rest_position = _rest_position(incoming)
	incoming.scale = Vector2.ONE * PILE_SCALE
	incoming.global_position = _position_for(incoming, from_pile.global_position + _pile_top(from_count),
		PILE_SCALE)
	_fill_pile(from_pile, _ahead() if step > 0 else _behind())  # its top card has risen out of it
	_move_to(outgoing, fly_layer)

	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(outgoing, "global_position",
		_position_for(outgoing, to_pile.global_position + _pile_top(to_count), PILE_SCALE), FLY_TIME)
	tween.tween_property(outgoing, "scale", Vector2.ONE * PILE_SCALE, FLY_TIME)
	tween.tween_property(outgoing, "rotation", 0.0, FLY_TIME)
	tween.tween_property(incoming, "global_position",
		stage.global_position + incoming.rest_position, FLY_TIME)
	tween.tween_property(incoming, "scale", Vector2.ONE, FLY_TIME)
	tween.chain().tween_callback(_finish_flip.bind(outgoing, incoming, to_pile, step))


## The slide is over: the old middle card joins its pile and the new one settles on the stage.
func _finish_flip(outgoing: Control, incoming: Control, to_pile: Control, step: int) -> void:
	outgoing.queue_free()
	_fill_pile(to_pile, _behind() if step > 0 else _ahead())
	_move_to(incoming, stage)
	incoming.position = incoming.rest_position
	center_card = incoming
	animating = false


## The middle card was pulled up: it fades where it was, and a small copy follows your finger.
func start_drag(card: Control) -> void:
	dragged_card = card
	var holder := Control.new()  # the preview is drawn with its top-left at the finger, so offset it
	var ghost := new_card(card.unit, false, holder)
	ghost.scale = Vector2.ONE * 0.5
	ghost.position = -ghost.custom_minimum_size * 0.25  # half of half size: centered on the finger
	card.force_drag({"unit": card.unit}, holder)
	card.modulate.a = 0.25


func _notification(what: int) -> void:
	# A drag that didn't land on a spot: the middle card comes back.
	if what == NOTIFICATION_DRAG_END and dragged_card != null:
		if is_instance_valid(dragged_card) and not get_viewport().gui_is_drag_successful():
			create_tween().tween_property(dragged_card, "modulate:a", 1.0, 0.15)
		dragged_card = null


## A card was dropped on a deck spot: the troop moves to that flight (element 1), or out of flights.
## A small copy shrinks into the spot, which bumps, and the next card takes the middle.
func card_dropped(number: int, unit: Node2D, spot_center: Vector2) -> void:
	var ghost := new_card(unit, false, fly_layer)
	ghost.scale = Vector2.ONE * 0.5
	ghost.global_position = get_global_mouse_position() - ghost.custom_minimum_size * 0.25
	var tween := create_tween().set_parallel()
	tween.tween_property(ghost, "global_position", spot_center, DROP_TIME)
	tween.tween_property(ghost, "scale", Vector2.ONE * 0.05, DROP_TIME)
	tween.tween_property(ghost, "modulate:a", 0.0, DROP_TIME)
	tween.chain().tween_callback(ghost.queue_free)
	unit.set_flight(number, 1)
	_rebuild()  # it left this deck
	var spot := _spot_for(number)
	if spot != null:
		spot.pulse()


## The game keeps running while the roster is open, so the top bar says when the next raid comes.
func _update_raid_label() -> void:
	if raids == null:
		raid_label.text = ""
		return
	if raids.active:
		raid_label.text = "RAID IN PROGRESS"
		raid_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		return
	var seconds := maxi(ceili(raids.countdown), 0)
	raid_label.text = "Next raid in %d:%02d" % [seconds / 60, seconds % 60]
	var warn: bool = raids.countdown <= RAID_WARNING
	raid_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4) if warn else Color(0.9, 0.85, 0.75))


## The arrows on a card: moves the troop one element up or down within its flight.
func change_element(unit: Node2D, step: int) -> void:
	unit.set_flight(unit.flight, clampi(unit.element + step, 1, ELEMENTS_PER_FLIGHT))
	_rebuild(unit)


func _process(delta: float) -> void:
	if not visible:
		return
	# The candle wavers a little; noise, not a sine wave, so it never looks like it's on a loop.
	flicker_time += delta * FLICKER_SPEED
	candle_light.modulate.a = 1.0 - FLICKER * (0.5 + 0.5 * flicker_noise.get_noise_1d(flicker_time * 40.0))
	_update_raid_label()
	# Refresh the cards' text (status, history...) without rebuilding, so nothing in motion is disturbed.
	refresh_left -= delta
	if refresh_left <= 0.0:
		refresh_left = REFRESH_TIME
		if center_card != null and not animating:
			center_card.refresh()
		for pile in [left_pile, right_pile]:
			for card in pile.get_children():
				if card.has_method("refresh"):
					card.refresh()
