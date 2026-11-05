extends RefCounted
## Builds placeholder tile textures in code, so the grid can use Godot's TileMapLayer before there's any
## art: one diamond per kind of ground, filled with its color and outlined, side by side in one image
## (an "atlas"). Your Blender renders will replace these.

const SIZE := 128  # pixels per tile, matching the grid's TILE_WIDTH and TILE_HEIGHT


## A TileSet with one tile per color, in order: tile i of the atlas is colors[i].
static func build(colors: Array) -> TileSet:
	var image := Image.create(SIZE * colors.size(), SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for i in colors.size():
		var fill: Color = colors[i]
		var edge: Color = fill.darkened(0.35)
		for px in SIZE:
			for py in SIZE:
				# Distance from the center in "diamond" terms: inside the diamond when it's at most half.
				var d := absf(px + 0.5 - half) + absf(py + 0.5 - half)
				if d <= half:
					image.set_pixel(i * SIZE + px, py, edge if d > half - 1.5 else fill)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(SIZE, SIZE)
	for i in colors.size():
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC  # diamonds
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN  # the same layout as grid.tile_to_screen()
	tile_set.tile_size = Vector2i(SIZE, SIZE)
	tile_set.add_source(source, 0)
	return tile_set
