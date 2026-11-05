extends RefCounted
## Makes the material that textures ground, fog and walls (see surface.gdshader). Until there are painted
## textures, the textures are generated noise: seamless, so they repeat without visible edges. To use
## your own, put the files in res://Assets/ and load them in _texture() instead of generating noise.

const Surface = preload("res://scripts/surface.gdshader")

static var _textures: Dictionary = {}  # made once and shared by every layer


## A material for a layer. Walls pass their mask; ground and fog pass null (everything is top).
## top is which texture the top surfaces use: "floor" for the ground, "wall_top" for walls.
static func make(mask: Texture2D, top: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Surface
	material.set_shader_parameter("use_mask", mask != null)
	if mask != null:
		material.set_shader_parameter("mask_tex", mask)
	material.set_shader_parameter("top_tex", _texture(top, 0.02))
	material.set_shader_parameter("face_tex", _texture("wall_face", 0.03))
	material.set_shader_parameter("macro_tex", _texture("macro", 0.006))
	return material


## Placeholder colors for each texture, darkest to lightest, until your paintings replace them.
## The variation texture stays gray: the shader only reads its brightness.
const PLACEHOLDER_COLORS := {
	"floor": [Color(0.60, 0.55, 0.46), Color(0.80, 0.75, 0.64)],
	"wall_top": [Color(0.36, 0.34, 0.31), Color(0.52, 0.50, 0.46)],
	"wall_face": [Color(0.26, 0.23, 0.20), Color(0.44, 0.39, 0.34)],
	"macro": [Color.BLACK, Color.WHITE],
}


## A seamless noise texture, made once per name. Higher frequency means finer grain.
static func _texture(texture_name: String, frequency: float) -> Texture2D:
	if not _textures.has(texture_name):
		var noise := FastNoiseLite.new()
		noise.frequency = frequency
		noise.fractal_octaves = 4
		noise.seed = texture_name.hash()
		var texture := NoiseTexture2D.new()
		texture.width = 512
		texture.height = 512
		texture.seamless = true  # its edges match, so it repeats invisibly
		texture.generate_mipmaps = true
		texture.noise = noise
		var ramp := Gradient.new()  # turns the noise's gray into the placeholder colors
		ramp.colors = PackedColorArray(PLACEHOLDER_COLORS[texture_name])
		texture.color_ramp = ramp
		_textures[texture_name] = texture
	return _textures[texture_name]
