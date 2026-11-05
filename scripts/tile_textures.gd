extends RefCounted
## Builds placeholder tile textures in code, so the grid can use Godot's TileMapLayer before there's any
## art: one diamond per kind of ground, filled with its color and outlined, side by side in one image
## (an "atlas"). Your Blender renders will replace these.



## A TileSet with one tile per color, in order: tile i of the atlas is colors[i]. size is the tile's
## width and height in pixels, matching the grid's TILE_WIDTH and TILE_HEIGHT.
static func build(colors: Array, size: int) -> TileSet:
	var image := Image.create(size * colors.size(), size, false, Image.FORMAT_RGBA8)
	var half := size / 2.0
	for i in colors.size():
		var fill: Color = colors[i]
		var edge: Color = fill.darkened(0.35)
		for px in size:
			for py in size:
				# Distance from the center in "diamond" terms: inside the diamond when it's at most half.
				var d := absf(px + 0.5 - half) + absf(py + 0.5 - half)
				if d <= half:
					image.set_pixel(i * size + px, py, edge if d > half - 1.5 else fill)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(size, size)
	for i in colors.size():
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC  # diamonds
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN  # the same layout as grid.tile_to_screen()
	tile_set.tile_size = Vector2i(size, size)
	tile_set.add_source(source, 0)
	return tile_set


## A TileSet of walls, drawn entirely inside their own cells so they never cover their neighbors.
## Each color gets eight drawings, one per atlas row; the row number is a bit flag of what shows:
##   1 = lower-left face, 2 = lower-right face, 4 = inside-corner piece (0 = a plain diamond).
## The inside-corner piece is for a wall whose diagonal neighbor straight below it is floor: it carries
## the two neighboring walls' faces up into this cell's bottom corner, so they meet in a clean edge.
## A face is a band face_height pixels tall along the cell's lower edge on that side. Every cell's band has
## the same height, so a row of walls forms one continuous face, and its top edge one straight ridge.
## There are no outlines on cell edges, so walls side by side blend into one surface; the only line
## drawn is the ridge where the top meets a face.
static func build_walls(colors: Array, size: int, face_height: float) -> TileSet:
	var image := Image.create(size * colors.size(), size * 8, false, Image.FORMAT_RGBA8)
	var half := size / 2.0
	for i in colors.size():
		var top: Color = colors[i]
		var ridge: Color = top.lightened(0.15)
		for faces in 8:
			var left_open: bool = (faces & 1) != 0
			var right_open: bool = (faces & 2) != 0
			var corner_open: bool = (faces & 4) != 0
			for px in size:
				for py in size:
					var x := px + 0.5
					var y := py + 0.5
					if absf(x - half) + absf(y - half) > half:
						continue  # outside the cell's diamond
					# How far above the cell's lower edge this pixel is, on each side. The lower-left edge
					# runs along y = half + x, the lower-right along y = half + (size - x).
					var above_left := (half + x) - y
					var above_right := (half + size - x) - y
					var color: Color = top
					if corner_open:
						# Continue the neighbors' faces into the bottom corner. Left of the corner sits the up-left
						# wall's lower-right face, measured from the line through the corner going down-left;
						# right of it, the up-right wall's lower-left face, from the line going down-right.
						if x < half:
							var above_corner := (size + half - x) - y
							if above_corner < face_height:
								color = top.darkened(0.45) if above_corner < face_height - 1.5 else ridge
						else:
							var above_corner := (size + x - half) - y
							if above_corner < face_height:
								color = top.darkened(0.25) if above_corner < face_height - 1.5 else ridge
					var in_left := left_open and above_left < face_height
					var in_right := right_open and above_right < face_height
					if in_left and in_right:
						# Both faces reach here: split them at the vertical line through the bottom corner,
						# so an outside corner shows a clean vertical edge.
						in_left = x < half
						in_right = not in_left
					if in_left:
						color = top.darkened(0.25) if above_left < face_height - 1.5 else ridge
					elif in_right:
						color = top.darkened(0.45) if above_right < face_height - 1.5 else ridge
					image.set_pixel(i * size + px, faces * size + py, color)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(size, size)
	for i in colors.size():
		for faces in 8:
			source.create_tile(Vector2i(i, faces))

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = Vector2i(size, size)
	tile_set.add_source(source, 0)
	return tile_set
