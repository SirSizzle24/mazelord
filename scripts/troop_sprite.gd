extends Sprite2D
## A troop's baked sprite on the map: plays one clip at a time (Idle, Walk, Attack_L...) in one of
## eight directions, recolored with the troop's look (troop_look.gd, troop_recolor.gdshader). The
## node's position is the troop's feet. unit.gd decides what to play; this only plays it.
##
## Directions, as baked: 0 faces down the screen (toward you), then clockwise seen from above:
## 1 down-left, 2 left, 3 up-left, 4 up (away from you), 5 up-right, 6 right, 7 down-right.

signal finished(clip: String)  # a clip that doesn't loop reached its end

const TroopLook := preload("res://scripts/troop_look.gd")

var folder := ""  # the face's folder of packed sheets, e.g. res://Assets/Troops/worker/face1
var clip := ""
var info: Dictionary = {}
var looping := true
var backwards := false
var speed := 1.0  # playback rate
var direction := 0
var time := 0.0
var done := false


func setup(new_folder: String, look: Dictionary) -> void:
	folder = new_folder
	centered = false
	material = TroopLook.material_for(look)


## Starts a clip, unless it's already the one playing and looping (so calling this every frame with
## the same looping clip just keeps it going).
func play(new_clip: String, loop := true, reverse := false, rate := 1.0) -> void:
	speed = rate
	if new_clip == clip and loop and looping and not done:
		return
	var sheet := TroopLook.sheet(folder, new_clip)
	if sheet.is_empty():
		return
	clip = new_clip
	info = sheet["info"]
	looping = loop
	backwards = reverse
	time = 0.0
	done = false
	texture = sheet["color"]
	material.set_shader_parameter("mask", sheet["mask"])
	hframes = int(info["columns"])
	vframes = int(info["rows_per_direction"]) * int(info["directions"])
	var anchor: Array = info["anchor"]
	offset = -Vector2(anchor[0], anchor[1])  # the feet land on this node's position
	_show_frame()


## Turns to face along a vector on screen (does nothing for a tiny one).
func face(along: Vector2) -> void:
	if along.length() < 0.5:
		return
	var turned := posmod(roundi(-atan2(along.x, along.y) / (PI / 4.0)), 8)
	if turned != direction:
		direction = turned
		_show_frame()


func _process(delta: float) -> void:
	if info.is_empty() or done:
		return
	time += delta * speed
	_show_frame()


func _show_frame() -> void:
	if info.is_empty():
		return
	var count: int = info["frames"]
	var index := int(time * float(info["fps"]))
	if looping:
		index %= count
	elif index >= count:
		index = count - 1
		if not done:
			done = true
			finished.emit.call_deferred(clip)
	if backwards:
		index = count - 1 - index
	var dir: int = direction % int(info["directions"])
	frame = dir * int(info["rows_per_direction"]) * hframes + index
