extends Control
## One troop's card. Its layout lives in Scenes/card.tscn: move, restyle or swap its parts in the editor
## freely. The code finds them by their unique names (%NameLabel and so on), so the names are the only
## thing that must stay. The portrait can be a ColorRect (placeholder: it gets the troop's color) or a
## TextureRect once there's art. The frame is a picture laid over everything but the text, and its
## shader (card_frame.gdshader) shows the troop's rank: bronze unnamed, gold named, glowing gold for a
## hero. Its colors are settings on %Frame's material. The name's color follows the rank too.
##
## The middle card of the roster is "large": it shows element arrows in a flight, follows your finger
## sideways and flips when you let go past SWIPE_DISTANCE, lifts when held still, and starts a drag onto
## the deck spots when pulled upward. Cards in the piles are plain and ignore input.

const HOLD_TIME := 0.25  # seconds held still before the card lifts
const MOVE_SLOP := 10.0  # pixels a finger may wander and still count as held still
const SWIPE_DISTANCE := 80.0  # pixels sideways to flip instead of springing back
const DRAG_DISTANCE := 50.0  # pixels upward to start dragging onto a deck spot
const LIFT_SCALE := 1.06
const TILT := 0.0006  # radians of tilt per pixel of sideways swipe
enum Tier { BRONZE, GOLD, HERO }  # unnamed, named, hero
const HERO_GLOW := Color(1.0, 0.82, 0.45)  # the hero name's glow; match glow_color on the frame
const HERO_GLOW_SIZE := 10  # pixels of glow around the hero name's letters
const BREATH_SECONDS := 3.5  # match breath_seconds and breath_depth on the frame, so they pulse together
const BREATH_DEPTH := 0.8
const NAME_COLORS := [Color(0.80, 0.62, 0.48), Color(0.95, 0.78, 0.35), Color(1.0, 0.90, 0.60)]

var roster: Node  # set before the card enters the scene
var unit: Node2D
var large := false
var rest_position := Vector2.ZERO  # where the middle card sits when nothing is moving it
var mini := false  # a tiny card lying in a tray: no text, only the frame, portrait and rank
var compact := false  # a large card shown like a pile card, while it flies between the middle and a pile
var tier_override := -1  # debug: show this rank instead of the troop's own (-1 for its own)

var pressing := false
var press_at := Vector2.ZERO  # global position where the press started
var held := 0.0
var lifted := false

@onready var shadow: Control = %Shadow  # shown under the card while it's lifted
@onready var frame: CanvasItem = %Frame
@onready var name_label: Label = %NameLabel
@onready var portrait: Control = %Portrait
@onready var type_label: Label = %TypeLabel
@onready var status_label: Label = %StatusLabel
@onready var prev_button: Button = %PrevButton
@onready var element_label: Label = %ElementLabel
@onready var next_button: Button = %NextButton
@onready var fame_bar: ProgressBar = %FameBar
@onready var fame_label: Label = %FameLabel
@onready var history_label: Label = %HistoryLabel


func _ready() -> void:
	# Large cards lift and tilt around their middle; pile cards scale from their corner, which makes
	# stacking them by hand simple.
	pivot_offset = custom_minimum_size / 2.0 if large else Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP if large else Control.MOUSE_FILTER_IGNORE
	var arrows: bool = large and unit.flight > 0
	prev_button.visible = arrows
	next_button.visible = arrows
	if mini:
		for part in [name_label, type_label, status_label.get_parent(), fame_bar.get_parent()]:
			part.visible = false
	prev_button.pressed.connect(func(): roster.change_element(unit, -1))
	next_button.pressed.connect(func(): roster.change_element(unit, 1))
	refresh()


## Shows a large card like a pile card (short history, no arrows) or as itself again. Used while it
## flies, so a card landing on a pile already looks like the pile card that replaces it.
func set_compact(on: bool) -> void:
	compact = on
	var arrows: bool = large and not compact and unit.flight > 0
	prev_button.visible = arrows
	next_button.visible = arrows
	refresh()


func refresh() -> void:
	if not is_instance_valid(unit):
		name_label.text = "(gone)"
		return
	var tier := tier_for()
	if frame.material is ShaderMaterial:
		frame.material.set_shader_parameter("tier", tier)
	name_label.add_theme_color_override("font_color", NAME_COLORS[tier])
	if portrait is ColorRect:
		portrait.color = unit.color  # placeholder until there's art
	name_label.text = unit.roster_label
	type_label.text = "%s  ·  %s" % [unit.type_id.capitalize(), unit.size.capitalize()]
	status_label.text = unit.status_text()
	element_label.text = "Element %d" % unit.element if unit.flight > 0 \
		else ("Worker" if unit.can_dig else "No flight")
	if unit.is_named:
		fame_bar.max_value = 1.0
		fame_bar.value = 1.0
		fame_label.text = "Fame %d · Named" % int(unit.fame)
	else:
		fame_bar.max_value = unit.dungeon.name_threshold()
		fame_bar.value = unit.fame
		fame_label.text = "Fame %d / %d" % [int(unit.fame), int(unit.dungeon.name_threshold())]
	history_label.text = _history_text()


## Only the history that fits the troop's job: fighters fight raids and get injured, workers dig,
## build, haul and rescue. The large card adds the details; the pile cards show the highlights.
func _history_text() -> String:
	var h: Dictionary = unit.history
	# Cinzel is all capitals and wide, so lines are kept short enough for the parchment.
	if unit.can_dig:
		if large and not compact:
			return "Dug %d · Built %d · Hauled %d\nRescues %d" % [h["cells_dug"], h["builds"], h["hauls"],
				h["rescues"]]
		return "Dug %d · Built %d · Hauled %d" % [h["cells_dug"], h["builds"], h["hauls"]]
	if large and not compact:
		return "Raids survived %d · Downed %d\nInjured %d · Recovered %d" % [h["raids_survived"],
			h["raiders_downed"], h["times_injured"], h["injuries_survived"]]
	return "Raids %d · Downed %d · Injured %d" % [h["raids_survived"], h["raiders_downed"], h["times_injured"]]


## The troop's rank, for the frame: hero, else named, else unnamed.
func tier_for() -> int:
	if tier_override >= 0:
		return tier_override
	if unit.is_hero:
		return Tier.HERO
	return Tier.GOLD if unit.is_named else Tier.BRONZE


func _gui_input(event: InputEvent) -> void:
	if not large or roster.animating or not is_instance_valid(unit):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pressing = true
			press_at = event.global_position
			held = 0.0
		elif pressing:
			pressing = false
			_set_lifted(false)
			var moved: Vector2 = event.global_position - press_at
			if absf(moved.x) > SWIPE_DISTANCE and absf(moved.x) > absf(moved.y):
				roster.flip(1 if moved.x < 0.0 else -1)  # swipe left for the next card
			else:
				spring_back()
	elif event is InputEventMouseMotion and pressing:
		var moved: Vector2 = event.global_position - press_at
		if moved.y < -DRAG_DISTANCE and absf(moved.y) > absf(moved.x) and not unit.can_dig:
			pressing = false
			_set_lifted(false)
			position = rest_position
			rotation = 0.0
			roster.start_drag(self)
		elif absf(moved.x) > absf(moved.y):
			# Follow the finger sideways, tilting a little the way it's going.
			position.x = rest_position.x + moved.x
			rotation = moved.x * TILT


func _process(delta: float) -> void:
	if is_instance_valid(unit) and tier_for() == Tier.HERO:
		_glow_name()
	if not pressing or lifted:
		return
	held += delta
	if held >= HOLD_TIME and get_global_mouse_position().distance_to(press_at) < MOVE_SLOP:
		_set_lifted(true)


## A hero's name glows like its frame: a soft outline of light around the letters, breathing on the
## same clock as the frame's shader (both count seconds since the game started).
func _glow_name() -> void:
	var seconds := Time.get_ticks_msec() / 1000.0
	var breath := 1.0 - BREATH_DEPTH * (0.5 + 0.5 * cos(seconds * TAU / BREATH_SECONDS))
	var glow := HERO_GLOW
	glow.a = 0.75 * breath
	name_label.add_theme_color_override("font_outline_color", glow)
	name_label.add_theme_constant_override("outline_size", HERO_GLOW_SIZE)


## Slides back to rest after a swipe that didn't go far enough.
func spring_back() -> void:
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", rest_position, 0.18)
	tween.tween_property(self, "rotation", 0.0, 0.18)


## Held still: the card rises a little, with a shadow under it.
func _set_lifted(on: bool) -> void:
	if on == lifted:
		return
	lifted = on
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ONE * (LIFT_SCALE if on else 1.0), 0.1)
	tween.tween_property(shadow, "modulate:a", 1.0 if on else 0.0, 0.1)
