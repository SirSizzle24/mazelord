extends Node
## Splits the dungeon into rooms at doors, works out each room's type from its finished furnishings,
## and shows a room's name in the corner when it's the only room fully in view.

@export var grid: Node2D
@export var dungeon: Node
@export var camera: Camera2D
@export var room_label: Label

var rooms: Array = []  # each room: {"tiles": tile -> true, "type": room type id or "", "bounds": Rect2}
var rooms_dirty := true  # re-check rooms on the next frame


func _ready() -> void:
	grid.layout_changed.connect(func(): rooms_dirty = true)
	room_label.visible = false


func _process(_delta: float) -> void:
	if rooms_dirty:
		rooms_dirty = false
		_find_rooms()
	_update_label()


## Groups floor tiles into rooms. Two floor tiles are in the same room if you can walk between them
## through shared sides without crossing a finished door. Door tiles belong to no room.
func _find_rooms() -> void:
	rooms.clear()
	var seen: Dictionary = {}
	for x in grid.GRID_WIDTH:
		for y in grid.GRID_HEIGHT:
			var start := Vector2i(x, y)
			if seen.has(start) or not grid.is_floor(start) or grid.is_door(start):
				continue
			var room_tiles := _flood_fill(start, seen)
			rooms.append({"tiles": room_tiles, "type": _room_type(room_tiles), "bounds": _bounds(room_tiles)})


## Every tile reachable from start without crossing rock or a door: a "flood fill", like a paint bucket tool.
func _flood_fill(start: Vector2i, seen: Dictionary) -> Dictionary:
	var room_tiles: Dictionary = {}
	var to_visit: Array[Vector2i] = [start]
	seen[start] = true
	while not to_visit.is_empty():
		var tile: Vector2i = to_visit.pop_back()
		room_tiles[tile] = true
		for offset in grid.NEIGHBORS:
			var next: Vector2i = tile + offset
			if seen.has(next) or not grid.is_floor(next) or grid.is_door(next):
				continue
			seen[next] = true
			to_visit.append(next)
	return room_tiles


## The room type whose minimum set this room meets with the most matching items, or "" for none.
func _room_type(room_tiles: Dictionary) -> String:
	# Count the finished furnishings in the room, by kind.
	var counts: Dictionary = {}
	for furnishing in grid.furnishings:
		if furnishing["built"] and room_tiles.has(furnishing["origin"]):
			counts[furnishing["id"]] = counts.get(furnishing["id"], 0) + 1

	var best := ""
	var best_matching := 0
	for type_id in dungeon.ROOM_TYPES:
		var needs: Array = dungeon.ROOM_TYPES[type_id]["needs"]
		var matching := 0
		var has_all := true
		for item_id in needs:
			if not counts.has(item_id):
				has_all = false
				break
			matching += counts[item_id]
		if has_all and matching > best_matching:  # strictly more, so ties keep the earlier type
			best = type_id
			best_matching = matching
	return best


## The screen-space rectangle a room's diamonds fit inside.
func _bounds(room_tiles: Dictionary) -> Rect2:
	var box := Rect2()
	var first := true
	for tile in room_tiles:
		var tile_box := Rect2(grid.tile_to_screen(tile) - Vector2(grid.TILE_WIDTH, grid.TILE_HEIGHT) / 2.0,
			Vector2(grid.TILE_WIDTH, grid.TILE_HEIGHT))
		box = tile_box if first else box.merge(tile_box)
		first = false
	return box


## Shows the room's name only when exactly one room is fully in view and it has a type.
func _update_label() -> void:
	var view_size: Vector2 = get_viewport().get_visible_rect().size / camera.zoom
	var view := Rect2(camera.get_screen_center_position() - view_size / 2.0, view_size)

	var fully_visible: Array = []
	for room in rooms:
		if view.encloses(room["bounds"]):
			fully_visible.append(room)

	if fully_visible.size() == 1 and fully_visible[0]["type"] != "":
		room_label.text = dungeon.ROOM_TYPES[fully_visible[0]["type"]]["name"]
		room_label.visible = true
	else:
		room_label.visible = false
