extends RefCounted
## Local presentation only. No simulation writes, timers, random global state or assets.
const Sprites = preload("res://scripts/sprite_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
const SettlementWorld = preload("res://scripts/settlement_world.gd")
const Crops = preload("res://scripts/crop_sprites.gd")
const WORLD := Rect2(12, 48, 468, 244)
const FLAG_SECTIONS := [Rect2(17, 10, 10, 8), Rect2(27, 14, 10, 8), Rect2(38, 16, 9, 7), Rect2(48, 16, 9, 7), Rect2(59, 14, 10, 8), Rect2(70, 10, 9, 8)]
const CROWN_LIMITS := {"tree": 42, "tree_small": 31, "flowerpot": 8, "plant": 15}
const CHIMNEYS := {"cafe": Vector2(86, 1), "alma_home": Vector2(52, 1), "player_home": Vector2(57, 2)}
# Leave the replacement cord and each flag's sewn top fixed during a gust.
const REVISED_FLAG_SECTIONS := [Rect2(20, 10, 10, 9), Rect2(30, 12, 9, 10), Rect2(39, 13, 9, 10), Rect2(48, 13, 9, 10), Rect2(57, 11, 9, 11), Rect2(66, 9, 11, 10)]
const REVISED_CHIMNEYS := {"cafe": Vector2(83, 1), "alma_home": Vector2(48, 1), "player_home": Vector2(54, 2)}
const MAX_FOREGROUND := 12

static func flag_sections() -> Array:
	return REVISED_FLAG_SECTIONS if Sprites.uses_revised_art("bunting") else FLAG_SECTIONS

static func chimney_at(id: String) -> Vector2:
	return REVISED_CHIMNEYS.get(id, Vector2.ZERO) if Sprites.uses_revised_art(id) else CHIMNEYS.get(id, Vector2.ZERO)

var elapsed: float = 0.0
var _minute: int = 720
var _room: String = "street"
var _settlement_state: Dictionary = {}
var _frames: Dictionary = {}
var _parts: Dictionary = {}
var _images: Dictionary = {}
var _water_pixels: Dictionary = {}
var _image_reads: int = 0
var _part_builds: int = 0
var _chimneys: Dictionary = {}
var _manifest_revision: int = -1

func _ensure_profile() -> void:
	var revision: int = Sprites.manifest_revision()
	if _manifest_revision == revision: return
	_manifest_revision = revision
	_frames.clear()
	_parts.clear()
	_images.clear()
	_water_pixels.clear()
	_chimneys.clear()

func advance(real_delta: float, minute: int, room: String, paused: bool, state: Dictionary = {}) -> void:
	_room = room
	_settlement_state = state
	if paused: return
	_minute = maxi(0, minute)
	if not is_finite(real_delta) or real_delta <= 0.0: return
	# Avoid a teleporting effect after a suspended window or a stalled frame.
	elapsed += minf(real_delta, 0.1)

func _gust_phase() -> float:
	var day: int = _minute / 1440
	return fposmod(elapsed + posmod(day * 3, 7), 22.0) - 6.0

func gust_strength() -> float:
	var phase: float = _gust_phase()
	return sin(phase / 5.0 * PI) if phase >= 0.0 and phase <= 5.0 else 0.0

func motion_state() -> Dictionary:
	return {"time": elapsed, "gust": gust_strength(), "water_frame": int(floor(elapsed * 8.0)) % 12, "room": _room}

func cache_stats() -> Dictionary:
	return {"image_reads": _image_reads, "part_builds": _part_builds, "frames": _frames.size(), "parts": _parts.size()}

func _frame(id: String) -> Dictionary:
	_ensure_profile()
	if not _frames.has(id): _frames[id] = Sprites.frame_info(id)
	return _frames[id]

func _image(frame: Dictionary) -> Image:
	var texture: Texture2D = frame.texture
	var identity: int = texture.get_rid().get_id()
	if not _images.has(identity):
		var bitmap: Image = texture.get_image()
		_image_reads += 1
		if bitmap != null and bitmap.is_compressed() and bitmap.decompress() != OK: bitmap = null
		_images[identity] = bitmap
	return _images[identity]

func _layer(id: String, local: Vector2i) -> int:
	if id == "bunting":
		var sections: Array = flag_sections()
		for index in sections.size():
			if sections[index].has_point(local): return index + 1
	elif CROWN_LIMITS.has(id):
		# Move the intact crown, including its highlights and tiny twigs. Shifting
		# only green pixels would tear holes in its silhouette. The lower trunk,
		# roots and container stay below these measured cuts and never move.
		if local.y < int(CROWN_LIMITS[id]): return 1
	return 0

func _prepared(id: String) -> Array[Dictionary]:
	_ensure_profile()
	if _parts.has(id): return _parts[id]
	var runs: Array[Dictionary] = []
	var frame: Dictionary = _frame(id)
	if frame.is_empty(): return runs
	var bitmap: Image = _image(frame)
	if bitmap == null or bitmap.is_empty(): return runs
	var source: Rect2 = frame.source
	for y in range(int(source.size.y)):
		var start := -1
		var previous := -1
		for x in range(int(source.size.x) + 1):
			var layer := -1
			if x < int(source.size.x):
				var pixel: Color = bitmap.get_pixel(int(source.position.x) + x, int(source.position.y) + y)
				if pixel.a > 0.0: layer = _layer(id, Vector2i(x, y))
			if layer != previous:
				if start >= 0: runs.append({"source": Rect2(source.position + Vector2(start, y), Vector2(x - start, 1)), "layer": previous})
				start = x if layer >= 0 else -1
				previous = layer
	_parts[id] = runs
	_part_builds += 1
	return runs

func _sway(seed: float = 0.0) -> int:
	if gust_strength() < 0.22: return 0
	var wave: float = sin(elapsed * 4.2 + seed)
	return 1 if wave > 0.3 else (-1 if wave < -0.3 else 0)

func _paint(canvas: CanvasItem, frame: Dictionary, source: Rect2, destination: Rect2, tint: Color = Color.WHITE) -> void:
	var visible: Rect2 = destination.intersection(WORLD)
	if not visible.has_area(): return
	var clipped := Rect2(source.position + visible.position - destination.position, visible.size)
	canvas.draw_texture_rect_region(frame.texture, visible, clipped, tint)

func _draw_foliage(canvas: CanvasItem, object: Dictionary) -> void:
	var id: String = object.id
	var frame: Dictionary = _frame(id)
	var origin: Vector2 = object.rect.position.round()
	var tint: Color = object.get("tint", Color.WHITE)
	for run: Dictionary in _prepared(id):
		var offset := Vector2.ZERO
		if int(run.layer) > 0:
			offset.x = _sway(origin.x * 0.02 + int(run.layer) * 0.7)
		var destination := Rect2(origin + run.source.position - frame.source.position + offset, run.source.size)
		_paint(canvas, frame, run.source, destination, tint)

func _draw_crops(canvas: CanvasItem, row: Dictionary) -> void:
	for plant: Dictionary in Crops.plant_specs(row, Sprites.uses_revised_art("garden_right")):
		var frame: Dictionary = _frame(plant.asset)
		if frame.is_empty(): continue
		var source: Rect2 = plant.source
		source.position += frame.source.position
		for run: Rect2 in Crops._foliage_runs(frame.texture, source):
			var offset := Vector2.ZERO
			# Bottom two source rows remain the root; only the leaves bend.
			if run.position.y < source.end.y - 2: offset.x = _sway(plant.rect.position.x * 0.08)
			_paint(canvas, frame, run, Rect2(plant.rect.position + run.position - source.position + offset, run.size), row.get("tint", Color.WHITE))

func _water_mask() -> Dictionary:
	_ensure_profile()
	if not _water_pixels.is_empty(): return _water_pixels
	var frame: Dictionary = _frame("fountain")
	if frame.is_empty(): return _water_pixels
	var bitmap: Image = _image(frame)
	if bitmap == null: return _water_pixels
	for y in range(7, 32):
		for x in range(9, 53):
			var pixel: Color = bitmap.get_pixelv(Vector2i(frame.source.position) + Vector2i(x, y))
			if pixel.a > 0.5 and pixel.g > pixel.r * 1.2 and pixel.b > pixel.r * 1.15: _water_pixels[Vector2i(x, y)] = true
	return _water_pixels

func water_specs(object: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mask: Dictionary = _water_mask()
	var phase: int = int(floor(elapsed * 8.0)) % 12
	var candidates: Array[Vector2i] = []
	# Moving highlights remain on inspected cyan pixels, never on the stone rim.
	for index in range(6): candidates.append(Vector2i(12 + index * 6 + phase % 3, 19 + posmod(index * 3 + phase / 3, 10)))
	for side in [25, 36]: candidates.append(Vector2i(side, 9 + phase % 8))
	for point: Vector2i in candidates:
		if mask.has(point):
			result.append({"rect": Rect2(object.rect.position.round() + Vector2(point), Vector2.ONE), "color": Color(0.74, 0.94, 0.89, 0.64)})
	return result

func draw_object(canvas: CanvasItem, object: Dictionary, font: Font) -> bool:
	if not Layout.is_outdoor(_room) or not object.get("rect") is Rect2: return false
	if object.get("environment_object",false): return false
	if object.has("construction_stage") or object.has("crop_stage") or object.has("settlement_node") or object.has("settlement_gate"): return false
	var rect: Rect2 = object.rect
	if not rect.position.is_finite() or not rect.size.is_finite() or not rect.has_area(): return false
	var id: String = str(object.get("id", ""))
	var crops: bool = bool(object.get("crop_row", false))
	if not crops and id != "fountain" and id != "bunting" and not CROWN_LIMITS.has(id): return false
	var frame: Dictionary = _frame(id)
	if frame.is_empty() or (not crops and rect.size != frame.source.size): return false
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if id == "fountain":
		Sprites.draw_object(canvas, object, font)
		for highlight: Dictionary in water_specs(object):
			if WORLD.encloses(highlight.rect): canvas.draw_rect(highlight.rect, highlight.color)
	elif gust_strength() < 0.22:
		Sprites.draw_object(canvas, object, font)
	elif crops:
		_draw_crops(canvas, object)
	else:
		_draw_foliage(canvas, object)
	return true

func _chimney_positions() -> Array[Dictionary]:
	_ensure_profile()
	if not _chimneys.has(_room):
		var positions: Array[Dictionary] = []
		for object: Dictionary in Layout.props(_room):
			if CHIMNEYS.has(object.id): positions.append({"at": (object.rect.position + chimney_at(str(object.id))).round(), "id": str(object.id), "building":str(object.get("settlement_building",""))})
		_chimneys[_room] = positions
	return _chimneys[_room]

func foreground_specs(room: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Layout.is_outdoor(room) or room != _room: return result
	var local: int = posmod(_minute, 1440)
	# Café daytime; the other two small chimneys only in the cool evening.
	var chimneys: Array[Dictionary] = _chimney_positions()
	for chimney_index in chimneys.size():
		if not SettlementWorld.building_ready(str(chimneys[chimney_index].get("building","")),_settlement_state): continue
		var is_cafe: bool = chimneys[chimney_index].id == "cafe"
		if is_cafe and (local < 420 or local >= 1140): continue
		if not is_cafe and local >= 540 and local < 1080: continue
		for index in range(2):
			var age: float = fposmod(elapsed + index * 2.1 + chimney_index * 0.6, 4.2)
			var position: Vector2 = (chimneys[chimney_index].at + Vector2(floor(age * 0.7) + _sway() * floor(age / 2), -2 - floor(age * 3))).round()
			var rectangle := Rect2(position, Vector2(2, 2))
			if WORLD.encloses(rectangle): result.append({"kind": "smoke", "rect": rectangle, "color": Color(0.88, 0.87, 0.78, 0.18 * (1.0 - age / 4.2))})
	if gust_strength() > 0.3:
		var phase: float = _gust_phase()
		for index in range(2):
			var rectangle := Rect2(Vector2(306 + index * -264 + floor(phase * 4), 261 + index * 5 + floor(phase * 2)), Vector2(2, 1))
			if WORLD.encloses(rectangle): result.append({"kind": "leaf", "rect": rectangle, "source": Rect2(17, 11, 2, 1)})
		for index in range(3):
			var rectangle := Rect2(Vector2(119 + index * 69 + floor(phase * 5), 185 + index * 3 + _sway(index)), Vector2(2, 1))
			if WORLD.encloses(rectangle): result.append({"kind": "dust", "rect": rectangle, "color": Color(0.94, 0.85, 0.65, 0.14 * gust_strength())})
	return result.slice(0, MAX_FOREGROUND)

func draw_foreground(canvas: CanvasItem, room: String) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for effect: Dictionary in foreground_specs(room):
		if effect.kind == "leaf":
			var frame: Dictionary = _frame("tree")
			if not frame.is_empty():
				var source: Rect2 = effect.source
				source.position += frame.source.position
				_paint(canvas, frame, source, effect.rect)
		else:
			canvas.draw_rect(effect.rect, effect.color)
