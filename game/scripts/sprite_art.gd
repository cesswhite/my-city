extends RefCounted
## Generated PNG sprites only. Rendering and collision geometry share WorldLayout.

const MANIFEST_PATH := "res://assets/sprites/manifest.json"
const Layout = preload("res://scripts/world_layout.gd")
const SettlementWorld = preload("res://scripts/settlement_world.gd")
const Crops = preload("res://scripts/crop_sprites.gd")
const BicycleRider = preload("res://scripts/bicycle_rider.gd")
const GroundTransitions = preload("res://scripts/ground_transitions.gd")
const EnvironmentArt = preload("res://scripts/environment_art.gd")
const WORLD_RECT := Rect2(12, 48, 468, 244)
const SKIN_COLORS = [Color("f6d4b3"), Color("e8b78c"), Color("c78c65"), Color("a96846"), Color("80513c"), Color("51392e")]
const HAIR_COLORS = [Color("302b2d"), Color("624337"), Color("a66540"), Color("ddb76c"), Color("b4b2a6"), Color("eee5d0")]
const EYE_COLORS = [Color("342d29"), Color("796443"), Color("648278"), Color("58819a"), Color("999597")]
const SHIRT_COLORS = [Color("b45f49"), Color("5f8277"), Color("cbac65"), Color("6c8591"), Color("b68b9d"), Color("eee3c9")]
const PANTS_COLORS = [Color("435664"), Color("605b4c"), Color("4a5146"), Color("8b7056"), Color("d0bda0")]
const REQUIRED_SCENERY = ["tile_grass", "tile_sand", "tile_plaza", "tile_wood", "tile_wall", "tile_timber", "fence", "cafe", "homes", "alma_home", "workshop", "player_home", "shop", "tree", "tree_small", "cafe_table", "fountain", "bench", "lamp", "flowerpot", "garden_left", "garden_right", "bunting", "window", "photo", "bed", "rug", "table", "chair", "cabinet", "bookshelf", "planter", "planter_seeded", "tea_set", "tea_ready", "plant", "bicycle_broken", "bicycle_fixed", "project_seeds", "project_basket", "project_tools", "project_painting", "exit_mat"]

static var last_error: String = ""
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _missing: Dictionary = {}
static var _loaded: bool = false
static var _manifest_revision: int = 0

static func reload_manifest(path: String = MANIFEST_PATH) -> Error:
	_manifest_revision += 1
	_manifest.clear()
	_textures.clear()
	_missing.clear()
	last_error = ""
	_loaded = true
	if not FileAccess.file_exists(path):
		last_error = "Sprite manifest is missing: " + path
		_missing["manifest"] = last_error
		return ERR_FILE_NOT_FOUND
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("assets") is Dictionary:
		last_error = "Sprite manifest must contain an assets dictionary."
		_missing["manifest"] = last_error
		return ERR_PARSE_ERROR
	_manifest = parsed
	return OK

static func _ensure_loaded() -> void:
	if not _loaded:
		reload_manifest()

static func missing_assets() -> PackedStringArray:
	_ensure_loaded()
	return PackedStringArray(_missing.keys())

static func manifest_data() -> Dictionary:
	_ensure_loaded()
	return _manifest.duplicate(true)

static func uses_revised_art(id: String) -> bool:
	# Per-asset provenance survives publication from staging to the normal paths.
	return _asset(id).has("art_direction")

static func manifest_revision() -> int:
	_ensure_loaded()
	return _manifest_revision

static func _missing_asset(id: String, reason: String) -> void:
	_missing[id] = reason
	last_error = reason

static func _asset(id: String) -> Dictionary:
	_ensure_loaded()
	var entry = _manifest.get("assets", {}).get(id, {})
	if not entry is Dictionary or entry.is_empty():
		_missing_asset(id, "Generated sprite is not declared: " + id)
		return {}
	return entry

static func _texture(id: String) -> Texture2D:
	var entry: Dictionary = _asset(id)
	if entry.is_empty():
		return null
	var path: String = str(entry.get("path", ""))
	if _textures.has(path):
		return _textures[path]
	if not path.begins_with("res://assets/sprites/"):
		_missing_asset(id, "Generated sprite PNG is missing or outside the sprite directory: " + id)
		return null
	# Imported resources also work in exports where the original PNG is omitted.
	var has_original: bool = FileAccess.file_exists(path)
	var imported: bool = FileAccess.file_exists(path + ".import") or ResourceLoader.has_cached(path) or not has_original
	if imported and ResourceLoader.exists(path, "Texture2D"):
		var resource = ResourceLoader.load(path, "Texture2D")
		if resource is Texture2D:
			_textures[path] = resource
			return resource
	if not has_original:
		_missing_asset(id, "Generated sprite resource could not be loaded: " + id)
		return null
	# Before editor import, decode the source bytes without the imported-Image warning.
	var source := Image.new()
	var decoded: Error = source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	if decoded != OK or source.is_empty():
		_missing_asset(id, "Generated sprite PNG could not be decoded: " + id)
		return null
	var texture: ImageTexture = ImageTexture.create_from_image(source)
	_textures[path] = texture
	return texture

static func _vector(value, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		var result := Vector2(float(value[0]), float(value[1]))
		if result.is_finite():
			return result
	return fallback

static func _region(value, fallback: Rect2) -> Rect2:
	if value is Array and value.size() == 4:
		var result := Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		if result.position.is_finite() and result.size.is_finite() and result.size.x > 0 and result.size.y > 0:
			return result
	return fallback

static func direction_name(direction: Vector2) -> String:
	if not direction.is_finite() or direction.is_zero_approx():
		return "down"
	if absf(direction.x) > absf(direction.y):
		return "left" if direction.x < 0 else "right"
	return "up" if direction.y < 0 else "down"

static func frame_info(id: String, walking: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN) -> Dictionary:
	var texture: Texture2D = _texture(id)
	if texture == null:
		return {}
	var entry: Dictionary = _asset(id)
	var source: Rect2 = _region(entry.get("region"), Rect2(Vector2.ZERO, texture.get_size()))
	var sheet: Rect2 = source
	var flip_h := false
	if entry.has("frame_size"):
		var frame_size: Vector2 = _vector(entry.frame_size, Vector2.ZERO)
		var frames: int = maxi(1, int(entry.get("frames", 1)))
		var directions: Array = entry.get("directions", ["down"])
		if frame_size.x <= 0 or frame_size.y <= 0 or directions.is_empty():
			_missing_asset(id, "Sprite animation dimensions are invalid: " + id)
			return {}
		var facing: String = direction_name(direction)
		var row: int = directions.find(facing)
		if row < 0 and facing in ["left", "right"]:
			row = directions.find("right" if facing == "left" else "left")
			flip_h = row >= 0
		if row < 0:
			row = maxi(0, directions.find("down"))
		var frame: int = posmod(phase, frames) if walking else 0
		source = Rect2(sheet.position + Vector2(frame * frame_size.x, row * frame_size.y), frame_size)
	if not Rect2(Vector2.ZERO, texture.get_size()).encloses(source) or not sheet.encloses(source):
		_missing_asset(id, "Sprite atlas region exceeds its PNG: " + id)
		return {}
	return {"texture": texture, "source": source, "flip_h": flip_h, "id": id}

static func _paint(canvas: CanvasItem, info: Dictionary, rect: Rect2, tint: Color, clip: Rect2 = Rect2()) -> void:
	if info.is_empty() or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var destination := Rect2(rect.position.round(), rect.size.round())
	var source: Rect2 = info.source
	if clip.has_area():
		var visible: Rect2 = destination.intersection(clip)
		if not visible.has_area():
			return
		var ratio: Vector2 = source.size / destination.size
		source = Rect2(source.position + (visible.position - destination.position) * ratio, visible.size * ratio)
		destination = visible
	if bool(info.get("flip_h", false)):
		destination.size.x = -destination.size.x
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_texture_rect_region(info.texture, destination, source, tint)

static func draw_asset(canvas: CanvasItem, id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	_paint(canvas, frame_info(id), rect, tint)

static func _tile(canvas: CanvasItem, id: String, rect: Rect2, tint: Color = Color.WHITE, world_aligned: bool = false) -> void:
	var visible: Rect2 = rect.intersection(WORLD_RECT)
	if not rect.has_area() or not visible.has_area():
		return
	var info: Dictionary = frame_info(id)
	if info.is_empty():
		return
	# Preserve native pixel scale; tile edges are clipped, never stretched.
	var size: Vector2 = info.source.size
	var start: Vector2 = rect.position
	if world_aligned:
		# Adjacent pieces of the same terrain must continue the same texture grid.
		# Props such as fences still start their modules at their own local anchor.
		start = WORLD_RECT.position + ((rect.position - WORLD_RECT.position) / size).floor() * size
	for y in range(int(start.y), int(ceil(rect.end.y)), maxi(1, int(size.y))):
		for x in range(int(start.x), int(ceil(rect.end.x)), maxi(1, int(size.x))):
			_paint(canvas, info, Rect2(Vector2(x, y), size), tint, visible)

static func _object(id: String, rect: Rect2, y: float = -1.0, tint: Color = Color.WHITE) -> Dictionary:
	return {"id": id, "rect": rect, "y": rect.end.y if y < 0 else y, "tint": tint}

static func object_frame(object: Dictionary) -> Dictionary:
	var info: Dictionary = frame_info(str(object.get("id", "")))
	if info.is_empty() or not object.has("source_rect"): return info
	var crop: Rect2 = object.source_rect if object.source_rect is Rect2 else Layout.rect(object.source_rect)
	var local_bounds := Rect2(Vector2.ZERO, info.source.size)
	if not crop.has_area() or not local_bounds.encloses(crop): return {}
	info.source = Rect2(info.source.position + crop.position, crop.size)
	return info

static func _native_object(item: Dictionary) -> Dictionary:
	var object: Dictionary = item.duplicate(true)
	object.slot = object.rect
	if not object.get("fixed_size", false) and not object.get("tile", false) and not object.get("crop_row", false):
		var info: Dictionary = object_frame(object)
		if not info.is_empty():
			var size: Vector2 = info.source.size
			var position: Vector2 = (object.slot.position + (object.slot.size - size) / 2.0).floor()
			if object.has("support_point"): position = (object.support_point - Vector2(size.x / 2.0, size.y)).floor()
			object.rect = Rect2(position, size)
	return object

static func _accent(room: String) -> Color:
	return {"cesar": Color("a7b891"), "lupita": Color("dbb4a8"), "mateo": Color("a5bac2"), "ines": Color("dec59d"), "alma": Color("ccb5d0"), "player": Color("adc9bf")}.get(room, Color.WHITE)

static func scenery_objects(room: String = "street", state: Dictionary = {}) -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	for item in EnvironmentArt.objects(room, SettlementWorld.objects(room, Layout.props(room), state), state):
		if not Layout.is_outdoor(room):
			if room == "player":
				if item.key == "storage": item.id = "planter_seeded" if state.get("garden_planted", false) else "planter"
				if item.key == "project":
					if state.get("bicycle_away", false): continue
					item.id = "bicycle_fixed" if state.get("bicycle_repaired", false) else "bicycle_broken"
				if item.key == "tea" and state.get("tea_ready", false): item.id = "tea_ready"
		objects.append(_native_object(item))
	return objects

static func _draw_objects(canvas: CanvasItem, room: String, state: Dictionary, font: Font = null) -> void:
	var objects: Array[Dictionary] = scenery_objects(room, state)
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
	for object in objects:
		draw_object(canvas, object, font)

static func sign_info(object: Dictionary) -> Dictionary:
	# Coordinates are relative to the inspected, imported building PNGs.
	var signs: Dictionary = {
		"cafe": ["CAFÉ", Rect2(35, 36, 33, 7), 6],
		"workshop": ["TALLER", Rect2(51, 30, 20, 6), 5],
		"shop": ["TIENDA", Rect2(16, 5, 24, 6), 5],
		"alma_home": ["ALMA", Rect2(18, 34, 24, 6), 5],
		"player_home": ["TU CASA", Rect2(20, 31, 30, 7), 5],
	}
	if object.has("construction_stage"):
		return {"text":"En obra" if object.construction_stage == "scaffold" else "Solar", "rect":Rect2(object.rect.position + Vector2(2,object.rect.size.y-14),Vector2(object.rect.size.x-4,10)), "size":8, "color":Color("fff2d5")}
	if object.has("label_override") and signs.has(object.id):
		var sign: Array = signs[object.id].duplicate()
		sign[0] = str(object.label_override)
		signs[object.id] = sign
	if object.has("label"):
		return {"text": str(object.label), "rect": object.rect.grow(-1), "size": 6, "color": Color("fae1ad")}
	if not signs.has(object.get("id", "")):
		return {}
	var sign: Array = signs[object.id]
	var rect: Rect2 = sign[1]
	rect.position += object.rect.position
	return {"text": sign[0], "rect": rect, "size": sign[2], "color": Color("4a3228")}

static func _draw_finished_crop(canvas: CanvasItem, object: Dictionary) -> void:
	# Reuse the native outer wall/roof trim to close the formerly shared duplex
	# edge. No resampling or bitmap generation; the door remains unchanged.
	var info: Dictionary = object_frame(object)
	var finish: Dictionary = object.edge_finish
	var base: Rect2 = object.rect
	var cap: Rect2 = object.rect
	var width: float = float(finish.width)
	base.size.x -= width
	cap.size.x = width
	if str(finish.side) == "left": base.position.x += width
	else: cap.position.x = object.rect.end.x - width
	_paint(canvas, info, object.rect, object.get("tint", Color.WHITE), base.intersection(WORLD_RECT))
	var end: Dictionary = frame_info(str(object.id))
	var source: Rect2 = Layout.rect(finish.source)
	end.source = Rect2(end.source.position + source.position, source.size)
	end.flip_h = true
	_paint(canvas, end, cap, object.get("tint", Color.WHITE), WORLD_RECT)

static func _draw_construction(canvas: CanvasItem, object: Dictionary) -> void:
	var box: Rect2 = object.rect
	# The reserved facade footprint is a fenced *yard*, never a tall earthen
	# wall. A low foundation and materials in its near half establish ground.
	_tile(canvas,"tile_sand",box,Color("e5dac0"),true)
	var depth: float = minf(26, floorf(box.size.y * 0.43))
	var foundation := Rect2(box.position.x+5,box.end.y-depth-5,maxf(8,box.size.x-10),depth)
	_tile(canvas,"tile_stone",foundation,Color("d7d1b6"),true)
	var inset: Rect2 = foundation.grow(-2)
	if inset.has_area(): _tile(canvas,"tile_soil",inset,Color("c7b994"),true)
	# Back fence and narrow side posts preserve the same closed plot boundary.
	_tile(canvas,"fence",Rect2(box.position,Vector2(box.size.x,minf(17,box.size.y/2))))
	for x in [box.position.x,box.end.x-3]:
		_tile(canvas,"tile_timber",Rect2(x,box.position.y+12,2,maxf(2,box.size.y-16)))
		for y in range(int(box.position.y+17),int(box.end.y-4),12):
			_tile(canvas,"tile_timber",Rect2(x,y-5,3,7))
	if object.construction_stage == "scaffold":
		var top: float = maxf(box.position.y+15,foundation.position.y-15)
		for x in [foundation.position.x+1,foundation.end.x-5]:
			_tile(canvas,"tile_timber",Rect2(x,top,4,box.end.y-top-4))
		_tile(canvas,"tile_timber",Rect2(foundation.position.x+1,top,maxf(4,foundation.size.x-2),3))
	_tile(canvas,"tile_timber",Rect2(box.get_center().x-minf(17,box.size.x/2-2),box.end.y-14,minf(34,box.size.x-4),10))
	# A small stack lies across the ground rather than up the full facade.
	for i in range(2):
		_tile(canvas,"tile_timber",Rect2(foundation.position+Vector2(3,i*4+3),Vector2(minf(16,foundation.size.x-6),3)))
	if box.size.x>=60 and box.size.y>=40:
		var tools: Dictionary = frame_info("project_tools")
		var at := Vector2(foundation.end.x-tools.source.size.x-4,foundation.end.y-tools.source.size.y)
		_paint(canvas,tools,Rect2(at,tools.source.size),Color.WHITE,WORLD_RECT)

static func _draw_resource(canvas: CanvasItem, object: Dictionary) -> void:
	var box: Rect2 = object.rect
	var tint := Color.WHITE if int(object.get("resource_remaining",1))>0 else Color(0.6,0.6,0.6,0.45)
	match str(object.resource):
		"madera":
			for index in range(3): _tile(canvas,"tile_timber",Rect2(box.position+Vector2(posmod(index,2)*2,index*5),Vector2(box.size.x-2,4)),tint)
		"piedra":
			for part: Rect2 in [Rect2(1,7,9,7),Rect2(8,2,9,8),Rect2(16,8,8,6)]:
				_tile(canvas,"tile_stone",Rect2(box.position+part.position,part.size),tint)
		"fibra":
			_draw_foliage_group(canvas,{"rect":box},0,tint)
		_:
			var frame: Dictionary = frame_info(str(object.id))
			_paint(canvas,frame,Rect2(box.get_center()-frame.source.size/2.0,frame.source.size),tint,WORLD_RECT)

static func _draw_foliage_group(canvas: CanvasItem, object: Dictionary, visible_rows: int = 0, tint: Color = Color.WHITE) -> void:
	# Cacheable source masks, native pixels only. Source clipping makes gradual
	# growth legible without inventing plants or rescaling their pixel grid.
	for plant: Dictionary in Crops.plant_specs(object, uses_revised_art("garden_right")):
		var frame: Dictionary = frame_info(plant.asset)
		var source: Rect2 = plant.source
		source.position += frame.source.position
		for run: Rect2 in Crops._foliage_runs(frame.texture,source):
			if visible_rows > 0 and run.position.y < source.end.y-visible_rows: continue
			_paint(canvas,frame.merged({"source":run},true),Rect2(plant.rect.position+run.position-source.position,run.size),tint,WORLD_RECT)

static func _draw_plot(canvas: CanvasItem, object: Dictionary) -> void:
	_tile(canvas,"tile_soil",object.rect,Color("a8a08d") if object.crop_stage=="unprepared" else Color.WHITE,true)
	match str(object.crop_stage):
		"seeded": _draw_foliage_group(canvas,object,4)
		"growing": _draw_foliage_group(canvas,object,7)
		"ready": _draw_foliage_group(canvas,object,0,Color("f3f2c9"))

static func _draw_board(canvas: CanvasItem, object: Dictionary) -> void:
	var box: Rect2 = object.rect
	_tile(canvas,"tile_timber",Rect2(box.position,Vector2(box.size.x,17)))
	for x in [3,box.size.x-6]: _tile(canvas,"tile_timber",Rect2(box.position+Vector2(x,17),Vector2(3,6)))
	var paper: Dictionary = frame_info("photo")
	paper.source=Rect2(paper.source.position+Vector2(3,3),Vector2(11,8))
	_paint(canvas,paper,Rect2(box.position+Vector2(3,3),Vector2(11,8)),Color.WHITE,WORLD_RECT)
	_paint(canvas,paper,Rect2(box.position+Vector2(16,5),Vector2(11,8)),Color("e1d4ae"),WORLD_RECT)

static func _draw_gate(canvas: CanvasItem, object: Dictionary) -> void:
	var frame: Dictionary=frame_info("fence")
	if object.gate_axis=="vertical":
		canvas.draw_texture_rect_region(frame.texture,object.rect,Rect2(frame.source.position,Vector2(object.rect.size.y,object.rect.size.x)),Color.WHITE,true)
	else: _tile(canvas,"fence",object.rect)

static func draw_object(canvas: CanvasItem, object: Dictionary, font: Font = null) -> void:
	if EnvironmentArt.draw_object(canvas,object,frame_info,uses_revised_art("garden_right")): return
	if object.has("settlement_gate"):
		_draw_gate(canvas,object)
	elif object.has("construction_stage"):
		_draw_construction(canvas,object)
	elif object.get("settlement_board",false):
		_draw_board(canvas,object)
	elif object.has("settlement_node"):
		_draw_resource(canvas,object)
	elif object.has("crop_stage"):
		_draw_plot(canvas,object)
	elif object.get("crop_row", false):
		Crops.draw_row(canvas, object, {"garden_left": frame_info("garden_left"), "garden_right": frame_info("garden_right")}, uses_revised_art("garden_right"))
	elif object.get("tile", false):
		_tile(canvas, str(object.id), object.rect, object.get("tint", Color.WHITE))
	elif object.has("edge_finish"):
		_draw_finished_crop(canvas, object)
	else:
		_paint(canvas, object_frame(object), object.get("rect", Rect2()), object.get("tint", Color.WHITE), WORLD_RECT)
	if font == null:
		return
	# Legible game labels sit on the intentionally blank boards in generated art.
	var sign: Dictionary = sign_info(object)
	if sign.is_empty():
		return
	var width: float = font.get_string_size(sign.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sign.size).x
	var bounds: Rect2 = sign.rect
	var baseline := Vector2(bounds.get_center().x - width / 2.0, bounds.position.y + (bounds.size.y - font.get_height(sign.size)) / 2.0 + font.get_ascent(sign.size)).round()
	canvas.draw_string(font, baseline, sign.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sign.size, sign.color)

static func draw_world(canvas: CanvasItem, font: Font, include_objects: bool = true, room: String = "street", state: Dictionary = {}) -> void:
	var layout: Dictionary = Layout.section(room)
	_tile(canvas, "tile_grass", WORLD_RECT, Color(str(layout.get("grass_tint", "ffffff"))), true)
	for background: Dictionary in layout.get("background_props", []):
		_tile(canvas, str(background.id), Layout.rect(background.rect))
	var transitions: Dictionary = GroundTransitions.plan(layout.get("ground", []), WORLD_RECT)
	for pass_name: String in ["fringes", "base", "shore"]:
		for piece: Dictionary in transitions[pass_name]:
			_tile(canvas, str(piece.id), piece.rect, piece.tint, true)
	EnvironmentArt.draw_ground(canvas,room,state,frame_info)
	if include_objects:
		_draw_objects(canvas, room, state, font)
	_draw_exit_labels(canvas, font, room, state)

static func _draw_exit_labels(canvas: CanvasItem, font: Font, room: String, state: Dictionary = {}) -> void:
	if font == null: return
	var names: Dictionary = {"street": "Plaza", "homes": "Casas", "gardens": "Huerto", "workshops": "Taller", "atelier": "Alma", "forest":"Arboleda"}
	for edge: Dictionary in Layout.exits(room):
		var title: String = str(names.get(edge.to, edge.to))
		if not SettlementWorld.area_open(str(edge.to),state): title += " · cerrado"
		var at := Vector2.ZERO
		match str(edge.side):
			"west":
				title = "← " + title
				at = Vector2(80, 202)
			"east":
				title += " →"
				at = Vector2(462 - font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, 172)
			"north":
				title += " ↑"
				at = Vector2(268, 83)
			"south":
				title += " ↓"
				at = Vector2(268, 286)
		var text_size: Vector2 = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		var plate := Rect2(at.round() - Vector2(3, ceilf(font.get_ascent(8)) + 2), Vector2(ceilf(text_size.x) + 6, ceilf(font.get_height(8)) + 4))
		canvas.draw_rect(Rect2(plate.position + Vector2(0,1), plate.size), Color(0.12,0.17,0.13,0.20))
		canvas.draw_rect(plate, Color(0.19,0.26,0.20,0.88))
		canvas.draw_string(font, at.round(), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("f4edda"))

static func draw_interior(canvas: CanvasItem, _font: Font, home_id: String, interior_state: Dictionary = {}, include_objects: bool = true) -> void:
	var layout: Dictionary = Layout.section(home_id)
	var accent: Color = _accent(home_id)
	_tile(canvas, "tile_wall", WORLD_RECT, Color("65736b"))
	_tile(canvas, "tile_wood", Layout.rect(layout.floor))
	_tile(canvas, str(layout.get("wall_asset", "tile_wall")), Layout.rect(layout.wall))
	# Bedroom and dining textiles define zones without creating invisible walls.
	for zone in layout.get("zones", []):
		_tile(canvas, str(zone.id), Layout.rect(zone.rect), Color(str(zone.get("tint", "ffffff"))))
	draw_object(canvas, _native_object(_object("rug", Layout.rect(layout.rug), 109, Color(str(layout.get("rug_tint", "ffffff"))))))
	draw_object(canvas, _native_object(_object("exit_mat", Layout.rect(layout.exit_mat), 108, accent)))
	if include_objects:
		_draw_objects(canvas, home_id, interior_state)

static func _tint(key: String, appearance: Dictionary) -> Color:
	var palettes: Dictionary = {"skin": SKIN_COLORS, "hair": HAIR_COLORS, "eyes": EYE_COLORS, "shirt": SHIRT_COLORS, "pants": PANTS_COLORS}
	if not palettes.has(key):
		return Color.WHITE
	var palette: Array = palettes[key]
	return palette[clampi(int(appearance.get(key, 0)), 0, palette.size() - 1)]

static func character_layers(appearance: Dictionary, walking: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN) -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	var config: Dictionary = _manifest.get("characters", {})
	var layers: Array = config.get("layers", [])
	if layers.is_empty():
		_missing_asset("characters", "Generated character layers are not configured.")
	for layer in layers:
		if not layer is Dictionary:
			continue
		var id: String = str(layer.get("asset", ""))
		if layer.has("variants") and layer.variants is Array and not layer.variants.is_empty():
			var index: int = clampi(int(appearance.get(str(layer.get("select", "")), 0)), 0, layer.variants.size() - 1)
			id = str(layer.variants[index])
		if id.is_empty():
			continue
		var info: Dictionary = frame_info(id, walking, phase, direction)
		if info.is_empty():
			continue
		info.tint = _tint(str(layer.get("tint", "")), appearance)
		info.offset = _vector(layer.get("offset"), Vector2.ZERO)
		info.key = str(layer.get("select", layer.get("tint", "body")))
		result.append(info)
	return result

static func draw_person(canvas: CanvasItem, at: Vector2, appearance: Dictionary, scale_px: int = 1, walking: bool = false, frame: int = 0, direction: Vector2 = Vector2.DOWN) -> void:
	_ensure_loaded()
	if not at.is_finite():
		return
	var config: Dictionary = _manifest.get("characters", {})
	var size: Vector2 = _vector(config.get("size"), Vector2(24, 32))
	var anchor: Vector2 = _vector(config.get("anchor"), Vector2(12, 30))
	var scale: int = clampi(scale_px, 1, 8)
	for layer in character_layers(appearance, walking, frame, direction):
		_paint(canvas, layer, Rect2(at.round() + (layer.offset - anchor) * scale, size * scale), layer.tint)

static func bicycle_pose(direction: Vector2) -> Dictionary:
	return Layout.data().riding_bicycle.get("poses", {}).get(direction_name(direction), {})

static func bicycle_rect(at: Vector2) -> Rect2:
	if not at.is_finite(): return Rect2()
	var geometry: Dictionary = Layout.data().riding_bicycle
	return Rect2(at.round() + Layout.point(geometry.offset), Layout.point(geometry.size))

static func bicycle_actor_rect(at: Vector2, direction: Vector2 = Vector2.DOWN) -> Rect2:
	if not at.is_finite(): return Rect2()
	var frame: Rect2 = bicycle_rect(at)
	# Precomputed alpha bounds cover all pedal phases without making transparent
	# atlas padding intercept clicks on nearby floor, objects or residents.
	var bounds: Rect2 = _region(_asset("bicycle_riding").get("opaque_bounds", {}).get(direction_name(direction)), Rect2(Vector2.ZERO, frame.size))
	bounds.position += frame.position
	return bounds.merge(BicycleRider.actor_rect(at, direction, bicycle_pose(direction)))

static func draw_bicycle(canvas: CanvasItem, at: Vector2, appearance: Dictionary, walking: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN) -> void:
	if not at.is_finite(): return
	var bike: Dictionary = frame_info("bicycle_riding", walking, phase, direction)
	_paint(canvas, bike, bicycle_rect(at), Color.WHITE)
	# The rider keeps their customized upper body, with seated legs and hands
	# aligned to the saddle, pedals and handlebars of each directional frame.
	BicycleRider.draw(canvas, at, character_layers(appearance, false, 0, direction), walking, phase, direction, bicycle_pose(direction))

static func validation_errors() -> PackedStringArray:
	_ensure_loaded()
	for id in REQUIRED_SCENERY:
		frame_info(id)
	for direction in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		frame_info("bicycle_riding", true, 3, direction)
	var config: Dictionary = _manifest.get("characters", {})
	if not config.get("layers") is Array or config.layers.is_empty():
		_missing_asset("characters", "Generated character layers are not configured.")
	else:
		for layer in config.layers:
			if not layer is Dictionary:
				_missing_asset("characters", "Generated character layer is malformed.")
				continue
			var ids: Array = layer.get("variants", [layer.get("asset", "")])
			for id in ids:
				if str(id).is_empty():
					continue
				for direction in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
					frame_info(str(id), true, 3, direction)
	return PackedStringArray(_missing.values())

static func is_ready() -> bool:
	return validation_errors().is_empty()
