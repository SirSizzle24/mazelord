extends RefCounted
## A troop's looks: the cap, body and spot colors and face it was summoned with, plus the materials
## that paint them onto its sprite and card portrait (troop_recolor.gdshader). Each new troop rolls one
## look; the palettes below are placeholders to tune freely: add, remove or change colors, and the
## rolls follow.
##
## Also loads the baked sprite sheets (packed by tools/pack_troop.py): each clip is a <clip>_color.png,
## a <clip>_mask.png and a <clip>.json saying how the frames are laid out. Sheets are loaded once and
## shared by every troop that uses them.

const RecolorShader := preload("res://scripts/troop_recolor.gdshader")

const CAP_COLORS := [
	Color(0.78, 0.24, 0.20),  # scarlet
	Color(0.85, 0.45, 0.18),  # ember
	Color(0.88, 0.70, 0.25),  # saffron
	Color(0.52, 0.32, 0.20),  # chestnut
	Color(0.50, 0.30, 0.65),  # violet
	Color(0.28, 0.32, 0.66),  # indigo
	Color(0.20, 0.55, 0.55),  # teal
	Color(0.40, 0.55, 0.25),  # moss
	Color(0.85, 0.48, 0.58),  # rose
	Color(0.88, 0.84, 0.74),  # ivory
]
const BODY_COLORS := [
	Color(0.43, 0.40, 0.31),  # tan (the original)
	Color(0.62, 0.58, 0.48),  # cream
	Color(0.66, 0.52, 0.44),  # peach
	Color(0.48, 0.47, 0.45),  # ash
	Color(0.55, 0.45, 0.25),  # ochre
	Color(0.42, 0.43, 0.28),  # olive
	Color(0.38, 0.28, 0.20),  # umber
	Color(0.40, 0.44, 0.50),  # slate
	Color(0.50, 0.44, 0.52),  # lilac
	Color(0.70, 0.67, 0.60),  # bone
]
## Spot styles: what the cap's spots become. "color" null means a darker shade of the cap.
## weight is how often it's rolled, against the others.
const SPOT_STYLES := {
	"white": {"color": Color(0.95, 0.93, 0.88), "amount": 1.0, "glow": 0.0, "weight": 35},
	"cream": {"color": Color(0.90, 0.82, 0.62), "amount": 1.0, "glow": 0.0, "weight": 20},
	"dark": {"color": null, "amount": 1.0, "glow": 0.0, "weight": 20},
	"none": {"color": Color.WHITE, "amount": 0.0, "glow": 0.0, "weight": 15},
	"glowing": {"color": Color(0.70, 1.0, 0.85), "amount": 1.0, "glow": 0.6, "weight": 10},
}
const DARK_SPOTS := 0.45  # how dark "dark" spots are, against the cap

static var _sheets: Dictionary = {}  # path -> {"color", "mask", "info"}


## A fresh random look. faces: the face folders this troop type has baked ("face1", ...).
static func roll(faces: Array) -> Dictionary:
	var styles: Array = SPOT_STYLES.keys()
	var total := 0
	for style in styles:
		total += SPOT_STYLES[style]["weight"]
	var pick := randi_range(1, total)
	var spots: String = styles[0]
	for style in styles:
		pick -= SPOT_STYLES[style]["weight"]
		if pick <= 0:
			spots = style
			break
	return {"cap": CAP_COLORS.pick_random(), "body": BODY_COLORS.pick_random(), "spots": spots,
		"face": faces.pick_random(), "phase": randf()}


## A new material wearing this look. Give each sprite or portrait its own (they hold their mask).
static func material_for(look: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RecolorShader
	var style: Dictionary = SPOT_STYLES[look["spots"]]
	var spot: Variant = style["color"]
	if spot == null:
		spot = (look["cap"] as Color).darkened(1.0 - DARK_SPOTS)
	material.set_shader_parameter("cap_color", look["cap"])
	material.set_shader_parameter("body_color", look["body"])
	material.set_shader_parameter("spot_color", spot)
	material.set_shader_parameter("spot_amount", style["amount"])
	material.set_shader_parameter("spot_glow", style["glow"])
	material.set_shader_parameter("glow_phase", look["phase"])
	return material


## One clip's sheets and layout, loaded once: {"color": Texture2D, "mask": Texture2D, "info": {...}}.
## info has frame_width, frame_height, frames, columns, rows_per_direction, directions, fps and (map
## sprites) anchor: where the feet are in a frame. Returns {} if the clip isn't there.
## keep: hold on to it for good (map sprites, used all the time). Portraits pass false, so they're
## freed once no card shows them.
static func sheet(folder: String, clip: String, keep := true) -> Dictionary:
	var path := folder.path_join(clip)
	if _sheets.has(path):
		return _sheets[path]
	var text := FileAccess.get_file_as_string(path + ".json")
	if text.is_empty():
		push_warning("No sprite sheet at %s" % path)
		return {}
	var loaded := {"color": load(path + "_color.png"), "mask": load(path + "_mask.png"),
		"info": JSON.parse_string(text)}
	if keep:
		_sheets[path] = loaded
	return loaded
