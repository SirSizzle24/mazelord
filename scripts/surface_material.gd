extends RefCounted
## Makes the material that textures ground, fog and walls (see surface.gdshader). Until there are painted
## textures, the textures are generated noise: seamless, so they repeat without visible edges. To use
## your own, put the files in res://Assets/ and load them in _texture() instead of generating noise.

const Surface = preload("res://scripts/surface.gdshader")

static var _textures: Dictionary = {}  # made once and shared by every layer


## A material for a layer. Walls pass their mask; ground and fog pass null (everything is top).
static func make(mask: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Surface
	material.set_shader_parameter("use_mask", mask != null)
	if mask != null:
		material.set_shader_parameter("mask_tex", mask)
	material.set_shader_parameter("top_tex", _texture("top", 0.02))
	material.set_shader_parameter("face_tex", _texture("face", 0.03))
	material.set_shader_parameter("macro_tex", _texture("macro", 0.006))
	return material


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
		_textures[texture_name] = texture
	return _textures[texture_name]
