extends RefCounted
## Hover effect only. Source sprites stay untouched; silhouettes are cached in memory.
const Sprites = preload("res://scripts/sprite_art.gd")
const Activities = preload("res://scripts/activity_visuals.gd")
const RADIUS := 2
const MAX_CHARACTER_MASKS := 128
const MAX_SOURCE_IMAGES := 128
const CHARACTER_ANCHOR := Vector2(12, 30)
const COLOR := Color("fff3bc")
const ALPHA_THRESHOLD := 0.5
# Pixel steps stay crisp. The second ring is deliberately faint, not a blurred box.
const NEIGHBORS := [
	Vector3(-1, 0, 0.62), Vector3(1, 0, 0.62), Vector3(0, -1, 0.62), Vector3(0, 1, 0.62),
	Vector3(-1, -1, 0.36), Vector3(1, -1, 0.36), Vector3(-1, 1, 0.36), Vector3(1, 1, 0.36),
	Vector3(-2, 0, 0.14), Vector3(2, 0, 0.14), Vector3(0, -2, 0.14), Vector3(0, 2, 0.14)
]
static var _images: Dictionary = {}
static var _frames: Dictionary = {}
static var _characters: Dictionary = {}
static var _character_order: Array[String] = []
static var _image_order: Array[int] = []
static var _image_reads := 0
static var _mask_builds := 0

static func cache_stats() -> Dictionary:
	return {"images": _images.size(), "frames": _frames.size(), "characters": _characters.size(), "image_reads": _image_reads, "mask_builds": _mask_builds}

static func clear_cache() -> void:
	_frames.clear()
	_images.clear()
	_characters.clear()
	_character_order.clear()
	_image_order.clear()
	_image_reads = 0
	_mask_builds = 0

static func _image(texture: Texture2D) -> Image:
	var identity: int = texture.get_rid().get_id()
	if not _images.has(identity):
		if _images.size() >= MAX_SOURCE_IMAGES: _images.erase(_image_order.pop_front())
		_image_reads += 1
		var bitmap: Image = texture.get_image()
		if bitmap != null and bitmap.is_compressed() and bitmap.decompress() != OK: bitmap = null
		# Keep the source resource alive so a recycled RID cannot reuse a stale mask.
		_images[identity] = {"texture": texture, "image": bitmap}
		_image_order.append(identity)
	else:
		_image_order.erase(identity)
		_image_order.append(identity)
	return _images[identity].image

static func _outline(alpha: PackedFloat32Array, width: int, height: int) -> ImageTexture:
	var mask := Image.create(width + RADIUS * 2, height + RADIUS * 2, false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	for y in range(-RADIUS, height + RADIUS):
		for x in range(-RADIUS, width + RADIUS):
			if x >= 0 and x < width and y >= 0 and y < height and alpha[y * width + x] >= ALPHA_THRESHOLD: continue
			var opacity := 0.0
			for neighbor: Vector3 in NEIGHBORS:
				var nx: int = x + int(neighbor.x)
				var ny: int = y + int(neighbor.y)
				if nx >= 0 and nx < width and ny >= 0 and ny < height:
					var coverage: float = alpha[ny * width + nx]
					if coverage >= ALPHA_THRESHOLD: opacity = maxf(opacity, coverage * neighbor.z)
			if opacity > 0.0: mask.set_pixel(x + RADIUS, y + RADIUS, Color(1, 1, 1, opacity))
	_mask_builds += 1
	return ImageTexture.create_from_image(mask)

static func _mask_for_frame(frame: Dictionary) -> Dictionary:
	var texture = frame.get("texture")
	var source = frame.get("source")
	if not texture is Texture2D or not source is Rect2: return {}
	if not source.position.is_finite() or not source.size.is_finite() or not source.has_area(): return {}
	if source.position != source.position.round() or source.size != source.size.round(): return {}
	var key: String = "%d:%d,%d,%d,%d" % [texture.get_rid().get_id(), int(source.position.x), int(source.position.y), int(source.size.x), int(source.size.y)]
	if _frames.has(key): return _frames[key]
	var result: Dictionary = {}
	var bitmap: Image = _image(texture)
	if bitmap != null and not bitmap.is_empty() and Rect2(Vector2.ZERO, bitmap.get_size()).encloses(source):
		var width: int = int(source.size.x)
		var height: int = int(source.size.y)
		var alpha := PackedFloat32Array()
		alpha.resize(width * height)
		for y in range(height):
			for x in range(width): alpha[y * width + x] = bitmap.get_pixel(int(source.position.x) + x, int(source.position.y) + y).a
		result = {"texture": _outline(alpha, width, height), "source_size": source.size, "offset": Vector2(-RADIUS, -RADIUS), "resource": texture}
	if not result.is_empty(): _frames[key] = result
	return result

static func draw(canvas: CanvasItem, object: Dictionary, strength: float = 1.0) -> void:
	if canvas == null or not is_finite(strength) or strength <= 0.0: return
	# These are compositions/terrain, not the silhouette of the declared PNG.
	if object.get("tile", false) or object.get("crop_row", false): return
	var destination = object.get("glow_rect", object.get("rect"))
	if not destination is Rect2 or not destination.position.is_finite() or not destination.size.is_finite() or not destination.has_area(): return
	var tint = object.get("tint", Color.WHITE)
	var opacity: float = clampf(strength, 0.0, 1.0) * (clampf(tint.a, 0.0, 1.0) if tint is Color else 1.0)
	if not is_finite(opacity) or opacity <= 0.0: return
	var id: String = str(object.get("id", ""))
	if id.is_empty(): return
	var frame: Dictionary = Sprites.frame_info(id)
	if frame.is_empty(): return
	# Door selection may target a measured region of its parent building sprite.
	if object.has("source_rect"):
		var source = object.source_rect
		if not source is Rect2 or not frame.source.encloses(source): return
		frame.source = source
	var effect: Dictionary = _mask_for_frame(frame)
	if effect.is_empty(): return
	var scale: Vector2 = destination.size / effect.source_size
	var bounds := Rect2(destination.position.round() + effect.offset * scale, (effect.source_size + Vector2(RADIUS * 2, RADIUS * 2)) * scale)
	if frame.get("flip_h", false):
		bounds.position.x += bounds.size.x
		bounds.size.x = -bounds.size.x
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_texture_rect(effect.texture, bounds, false, Color(COLOR, opacity))

static func _mask_for_layers(layers: Array) -> Dictionary:
	if layers.is_empty() or layers.size() > 32: return {}
	var descriptors := PackedStringArray()
	var bounds := Rect2()
	var has_bounds := false
	for layer in layers:
		if not layer is Dictionary: return {}
		var texture = layer.get("texture")
		var source = layer.get("source")
		var offset = layer.get("offset", Vector2.ZERO)
		var tint = layer.get("tint", Color.WHITE)
		if not texture is Texture2D or not source is Rect2 or not offset is Vector2 or not tint is Color: return {}
		if not source.position.is_finite() or not source.size.is_finite() or not source.has_area() or not offset.is_finite() or not is_finite(tint.a): return {}
		if source.position != source.position.round() or source.size != source.size.round() or offset != offset.round(): return {}
		if not Rect2(Vector2.ZERO, texture.get_size()).encloses(source): return {}
		var opacity: float = clampf(tint.a, 0.0, 1.0)
		if opacity <= 0.0: continue
		var region := Rect2(offset, source.size)
		bounds = bounds.merge(region) if has_bounds else region
		has_bounds = true
		descriptors.append("%d:%d,%d,%d,%d:%d,%d:%s:%s" % [texture.get_rid().get_id(), int(source.position.x), int(source.position.y), int(source.size.x), int(source.size.y), int(offset.x), int(offset.y), str(bool(layer.get("flip_h", false))), str(opacity)])
	if not has_bounds or bounds.size.x > 128 or bounds.size.y > 128: return {}
	# Appearance color and world position never enter the key. Keep references to
	# original textures in cached results, preventing RID reuse after image eviction.
	var key: String = "|".join(descriptors)
	if _characters.has(key):
		_character_order.erase(key)
		_character_order.append(key)
		return _characters[key]
	var width := int(bounds.size.x)
	var height := int(bounds.size.y)
	var alpha := PackedFloat32Array()
	alpha.resize(width * height)
	var resources: Array[Texture2D] = []
	for layer: Dictionary in layers:
		var opacity: float = clampf(layer.get("tint", Color.WHITE).a, 0.0, 1.0)
		if opacity <= 0.0: continue
		var bitmap: Image = _image(layer.texture)
		if bitmap == null or bitmap.is_empty(): return {}
		resources.append(layer.texture)
		var source: Rect2 = layer.source
		var offset: Vector2 = layer.get("offset", Vector2.ZERO) - bounds.position
		for y in int(source.size.y):
			for x in int(source.size.x):
				var sx: int = int(source.size.x) - 1 - x if layer.get("flip_h", false) else x
				var coverage: float = bitmap.get_pixel(int(source.position.x) + sx, int(source.position.y) + y).a * opacity
				var index: int = (int(offset.y) + y) * width + int(offset.x) + x
				alpha[index] = 1.0 - (1.0 - alpha[index]) * (1.0 - coverage)
	var result := {"texture": _outline(alpha, width, height), "source_size": bounds.size, "offset": bounds.position - Vector2(RADIUS, RADIUS), "resources": resources}
	if _characters.size() >= MAX_CHARACTER_MASKS: _characters.erase(_character_order.pop_front())
	_characters[key] = result
	_character_order.append(key)
	return result

static func _draw_layers(canvas: CanvasItem, layers: Array, origin: Vector2, strength: float) -> void:
	if canvas == null or not origin.is_finite() or not is_finite(strength) or strength <= 0.0: return
	var effect: Dictionary = _mask_for_layers(layers)
	if effect.is_empty(): return
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_texture(effect.texture, origin.round() + effect.offset, Color(COLOR, clampf(strength, 0.0, 1.0)))

static func draw_character(canvas: CanvasItem, appearance: Dictionary, at: Vector2, walking: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN, strength: float = 1.0) -> void:
	if canvas == null or not at.is_finite() or not is_finite(strength) or strength <= 0.0: return
	draw_character_layers(canvas, Sprites.character_layers(appearance, walking, phase, direction), at, strength)

static func draw_character_layers(canvas: CanvasItem, layers: Array, at: Vector2, strength: float = 1.0) -> void:
	# Caller-provided source crops and offsets may reproduce a composed work pose.
	_draw_layers(canvas, layers, at - CHARACTER_ANCHOR, strength)

static func _sleeping_head_layers(appearance: Dictionary) -> Array[Dictionary]:
	var asleep: Dictionary = appearance.duplicate()
	asleep.hat = 0
	var layers: Array[Dictionary] = []
	for layer: Dictionary in Sprites.character_layers(asleep, false, 0, Vector2.DOWN):
		if layer.id in ["char_shirt", "char_pants", "char_eyes"] or layer.key == "hat": continue
		layer.source = Rect2(layer.source.position + Activities.HEAD_SOURCE.position, Activities.HEAD_SOURCE.size)
		layers.append(layer)
	return layers

static func draw_sleeping_head(canvas: CanvasItem, appearance: Dictionary, head_at: Vector2, strength: float = 1.0) -> void:
	if canvas == null or not head_at.is_finite() or not is_finite(strength) or strength <= 0.0: return
	_draw_layers(canvas, _sleeping_head_layers(appearance), head_at, strength)
