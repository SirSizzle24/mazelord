extends Node2D
## The dungeon grid: stores which tiles are rock or floor, and draws them as isometric diamonds.

const GRID_WIDTH := 20
const GRID_HEIGHT := 20
const TILE_WIDTH := 128   # diamond width in pixels
const TILE_HEIGHT := 128  # same as the width: squares turned 45°, no squash

enum Tile { ROCK, FLOOR }

const ROCK_COLOR := Color(0.35, 0.33, 0.30)
const FLOOR_COLOR := Color(0.75, 0.72, 0.65)
const LINE_COLOR := Color(0.2, 0.2, 0.2)

var tiles: Array = []  # tiles[x][y] holds a Tile value


func _ready() -> void:
	for x in GRID_WIDTH:
		var column: Array = []
		for y in GRID_HEIGHT:
			column.append(Tile.ROCK)
		tiles.append(column)

## True if the tile is inside the grid.
func is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < GRID_WIDTH and tile.y >= 0 and tile.y < GRID_HEIGHT


## Turns a rock tile into floor. Does nothing for floor or out-of-bounds tiles.
func dig(tile: Vector2i) -> void:
	if is_in_bounds(tile) and tiles[tile.x][tile.y] == Tile.ROCK:
		tiles[tile.x][tile.y] = Tile.FLOOR
		queue_redraw()  # the data changed, so the picture must update

func _draw() -> void:
	for x in GRID_WIDTH:
		for y in GRID_HEIGHT:
			var center := tile_to_screen(Vector2i(x, y))
			var diamond := PackedVector2Array([
				center + Vector2(0, -TILE_HEIGHT / 2.0),  # top corner
				center + Vector2(TILE_WIDTH / 2.0, 0),    # right corner
				center + Vector2(0, TILE_HEIGHT / 2.0),   # bottom corner
				center + Vector2(-TILE_WIDTH / 2.0, 0),   # left corner
			])
			var color: Color = ROCK_COLOR if tiles[x][y] == Tile.ROCK else FLOOR_COLOR
			draw_colored_polygon(diamond, color)

			var outline := diamond.duplicate()
			outline.append(diamond[0])  # back to the first corner to close the shape
			draw_polyline(outline, LINE_COLOR, 1.0)


## Tile coordinates -> the screen position of that tile's center.
func tile_to_screen(tile: Vector2i) -> Vector2:
	return Vector2(
		(tile.x - tile.y) * TILE_WIDTH / 2.0,
		(tile.x + tile.y) * TILE_HEIGHT / 2.0
	)


## A screen position -> the tile it falls inside. The reverse of tile_to_screen.
func screen_to_tile(point: Vector2) -> Vector2i:
	var a := point.x / (TILE_WIDTH / 2.0)
	var b := point.y / (TILE_HEIGHT / 2.0)
	return Vector2i(roundi((a + b) / 2.0), roundi((b - a) / 2.0))


## The rectangle on screen that the whole diamond-shaped grid fits inside.
func get_world_rect() -> Rect2:
	var left := -GRID_HEIGHT * TILE_WIDTH / 2.0
	var right := GRID_WIDTH * TILE_WIDTH / 2.0
	var top := -TILE_HEIGHT / 2.0
	var bottom := (GRID_WIDTH + GRID_HEIGHT - 1) * TILE_HEIGHT / 2.0
	return Rect2(left, top, right - left, bottom - top)
