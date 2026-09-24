extends RefCounted
## Native foliage from the existing garden PNGs, without painting their soil tiles.

const VARIANTS = [
	{"asset": "garden_left", "source": Rect2(6, 4, 7, 9)},
	{"asset": "garden_left", "source": Rect2(15, 3, 8, 10)},
	{"asset": "garden_right", "source": Rect2(1, 4, 9, 9)},
	{"asset": "garden_right", "source": Rect2(11, 3, 9, 10)},
]
const REVISED_VARIANTS = [
	{"asset": "garden_left", "source": Rect2(6, 4, 7, 9)},
	{"asset": "garden_left", "source": Rect2(15, 3, 8, 10)},
	{"asset": "garden_right", "source": Rect2(1, 4, 10, 9)},
	{"asset": "garden_right", "source": Rect2(11, 3, 9, 10)},
]

static var _images: Dictionary = {}
static var _runs: Dictionary = {}

static func variants(revised: bool = false) -> Array:
	return REVISED_VARIANTS if revised else VARIANTS

static func plant_specs(row: Dictionary, revised: bool = false) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var bounds = row.get("rect")
	if not bounds is Rect2 or not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area():
		return specs
	var sources: Array = variants(revised)
	for index in range(8):
		var variant: Dictionary = sources[index % sources.size()]
		var source: Rect2 = variant.source
		var destination := Rect2(bounds.position.round() + Vector2(4 + index * 14, 4), source.size)
		if bounds.encloses(destination):
			specs.append({"asset": variant.asset, "source": source, "rect": destination})
	return specs

static func _image(texture: Texture2D) -> Image:
	var identity: int = texture.get_rid().get_id()
	if not _images.has(identity):
		# Reading a CPU copy does not alter the original texture or write an asset.
		var bitmap: Image = texture.get_image()
		if bitmap != null and bitmap.is_compressed() and bitmap.decompress() != OK:
			bitmap = null
		_images[identity] = bitmap
	return _images[identity]

static func _foliage_runs(texture: Texture2D, source: Rect2) -> Array[Rect2]:
	var identity: String = "%d:%d,%d,%d,%d" % [texture.get_rid().get_id(), int(source.position.x), int(source.position.y), int(source.size.x), int(source.size.y)]
	if _runs.has(identity):
		return _runs[identity]
	var result: Array[Rect2] = []
	var bitmap: Image = _image(texture)
	if bitmap != null and not bitmap.is_empty() and Rect2(Vector2.ZERO, bitmap.get_size()).encloses(source):
		for y in range(int(source.position.y), int(source.end.y)):
			var run_start: int = -1
			for x in range(int(source.position.x), int(source.end.x) + 1):
				var foliage: bool = false
				if x < int(source.end.x):
					var pixel: Color = bitmap.get_pixel(x, y)
					foliage = pixel.a >= 0.5 and pixel.g > pixel.r and pixel.g > pixel.b
				if foliage and run_start < 0:
					run_start = x
				elif not foliage and run_start >= 0:
					result.append(Rect2(run_start, y, x - run_start, 1))
					run_start = -1
	_runs[identity] = result
	return result

static func draw_row(canvas: CanvasItem, row: Dictionary, frames: Dictionary, revised: bool = false) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for plant: Dictionary in plant_specs(row, revised):
		var frame: Dictionary = frames.get(plant.asset, {})
		var texture = frame.get("texture")
		var frame_source = frame.get("source")
		if not texture is Texture2D or not frame_source is Rect2:
			continue
		var source: Rect2 = plant.source
		source.position += frame_source.position
		if not frame_source.encloses(source):
			continue
		for run: Rect2 in _foliage_runs(texture, source):
			var destination := Rect2(plant.rect.position + run.position - source.position, run.size)
			canvas.draw_texture_rect_region(texture, destination, run)
