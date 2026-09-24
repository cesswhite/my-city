extends SceneTree
## Integration geometry and native-pixel scale. No save loading, network or generated art.
const Crops = preload("res://scripts/crop_sprites.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Art = preload("res://scripts/pixel_art.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const HOMES = ["cesar", "lupita", "mateo", "ines", "alma", "player"]
const DIRECTIONS = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
var checks: int = 0
var failures: Array[String] = []
var images: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func png(path: String) -> Image:
	if images.has(path): return images[path]
	var result := Image.new()
	if result.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK: return result
	images[path] = result
	return result

func safe_route(origin: Vector2, destination: Vector2, room: String) -> bool:
	var route: Array[Vector2] = Navigation.route(origin, destination, room)
	if route.is_empty() or route[-1].distance_to(destination) > 0.01: return false
	var previous: Vector2 = origin
	for point in route:
		var steps: int = maxi(1, ceili(previous.distance_to(point)))
		for index in range(steps + 1):
			if not Navigation.is_walkable(previous.lerp(point, float(index) / steps), room): return false
		previous = point
	return true

func body_bounds(manifest: Dictionary, direction: Vector2) -> Rect2i:
	var result := Rect2i()
	for layer in manifest.characters.layers:
		if not layer.has("asset"): continue
		var id: String = str(layer.asset)
		var info: Dictionary = Sprites.frame_info(id, false, 0, direction)
		if info.is_empty(): continue
		var used: Rect2i = png(str(manifest.assets[id].path)).get_region(Rect2i(info.source)).get_used_rect()
		if used.has_area(): result = result.merge(used) if result.has_area() else used
	return result

func native_objects(room: String, state: Dictionary) -> bool:
	for item in Sprites.scenery_objects(room, state):
		if item.get("tile", false): continue
		if item.get("crop_row", false):
			var plants: Array[Dictionary] = Crops.plant_specs(item)
			if plants.size() != 8 or item.rect != item.slot: return false
			for plant in plants:
				var frame: Dictionary = Sprites.frame_info(str(plant.asset))
				if frame.is_empty() or plant.rect.size != plant.source.size or not item.rect.encloses(plant.rect): return false
			continue
		var info: Dictionary = Sprites.frame_info(str(item.id))
		if info.is_empty() or item.rect.size != info.source.size: return false
		if item.rect.position != item.rect.position.round(): return false
	return true

func run() -> void:
	var geometry: Dictionary = Layout.data()
	expect(not geometry.is_empty() and geometry.get("version") == 1, "shared world layout exists")
	if geometry.is_empty(): finish(); return
	var colony = Colony.new()
	colony.setup(false, true)
	var entry: Vector2 = Layout.point(geometry.entry)
	var exit_point: Vector2 = Layout.point(geometry.exit)
	expect(colony.residents.size() == 6, "isolated default world loads without reading a save")
	expect(Layout.door_positions() == Navigation.door_positions(), "navigation uses the declared six portals")
	expect(Colony.HOME_DOORS == geometry.doors and Colony.PLACES == geometry.places, "simulation shares doors and destinations with the layout")
	expect(Layout.point(Colony.ROOM_ENTRY) == entry and Layout.point(Colony.ROOM_EXIT) == exit_point and Layout.point(Colony.HOME_REST) == Layout.point(geometry.home_rest), "entry, exit and home rest use the shared geometry")
	for id in HOMES:
		var door: Vector2 = Layout.door_positions().get(id, Vector2.INF)
		expect(Layout.bounds("street").has_point(door) and Navigation.is_walkable(door), "door feet are inside the walkable street: " + id)
		expect(safe_route(entry, door, "street"), "street entry reaches the exact door: " + id)
		expect(Navigation.home_spawns().get(id) == entry and safe_route(entry, exit_point, id), "home entry and exit are connected: " + id)
		var interactions_accessible := true
		for item in Art.interior_items(id):
			var destination: Vector2 = item.stand_at
			interactions_accessible = interactions_accessible and Layout.bounds(id).has_point(destination) and Navigation.is_walkable(destination, id) and safe_route(entry, destination, id)
		expect(interactions_accessible, "every visible interior interaction can be approached: " + id)
	for id in geometry.places:
		var point: Vector2 = Layout.point(geometry.places[id])
		expect(safe_route(entry, point, "street") and safe_route(Layout.door_positions().player, point, "street"), "entry and player doorway reach the landmark: " + str(id))
	for item in Art.street_items():
		expect(Layout.bounds("street").has_point(item.stand_at) and safe_route(entry, item.stand_at, "street"), "street interaction has an accessible service point: " + str(item.id))
	for apprenticeship in colony._progression.catalog.apprenticeships:
		var station: Dictionary = apprenticeship.practice_station
		expect(Layout.point(station.pos) == Layout.stand_at(str(station.id), str(station.room)) and safe_route(entry, Layout.point(station.pos), str(station.room)), "practice uses the same reachable stand point: " + str(station.id))
	var imported: Error = Sprites.reload_manifest()
	expect(imported == OK and Sprites.validation_errors().is_empty(), "current native sprite resources load")
	if imported != OK or not Sprites.validation_errors().is_empty(): finish(); return
	var manifest: Dictionary = Sprites.manifest_data()
	var dimension_errors: Array[String] = []
	for id in manifest.assets:
		var image: Image = png(str(manifest.assets[id].path))
		if image.is_empty() or Vector2(image.get_size()) != Layout.point(manifest.assets[id].size): dimension_errors.append(str(id))
	expect(dimension_errors.is_empty(), "PNG dimensions match the manifest: " + ", ".join(dimension_errors))
	var size_errors: Array[String] = []
	for id in geometry.sprite_sizes:
		var info: Dictionary = Sprites.frame_info(str(id))
		if info.is_empty() or info.source.size != Layout.point(geometry.sprite_sizes[id]): size_errors.append(str(id))
	expect(size_errors.is_empty(), "the imported size policy is applied to PNG frames: " + ", ".join(size_errors))
	expect(native_objects("street", {}), "street scenery preserves one texture pixel per world pixel")
	for room in HOMES:
		var all_states_native := true
		for mask in range(16):
			var state := {"garden_planted": bool(mask & 1), "tea_ready": bool(mask & 2), "bicycle_repaired": bool(mask & 4), "bicycle_away": bool(mask & 8)}
			all_states_native = all_states_native and native_objects(room, state)
		expect(all_states_native, "all 16 interior progress states render at native dimensions: " + room)
	var body: Rect2i = body_bounds(manifest, Vector2.DOWN)
	var reference: int = int(geometry.reference.character_visible_height)
	expect(body.has_area() and absi(body.size.y - reference) <= 2, "visible body height matches the measured scale reference")
	for direction in DIRECTIONS:
		var bounds: Rect2i = body_bounds(manifest, direction)
		expect(absi(bounds.size.y - reference) <= 2 and bounds.end.y <= int(manifest.characters.anchor[1]) + 1, "directional body keeps a consistent foot anchor and scale: " + str(direction))
	var openings: Dictionary = geometry.get("door_openings", {})
	expect(openings.size() == HOMES.size(), "all six visual door openings have measured rectangles")
	for id in HOMES:
		if not openings.has(id): continue
		var opening: Dictionary = openings[id]
		var local_rect: Rect2 = Layout.rect(opening.rect)
		var building: Dictionary = {}
		for item in Sprites.scenery_objects():
			if item.id == opening.building: building = item; break
		var measured_in_png := false
		var portal_aligned := false
		if not building.is_empty():
			var frame: Dictionary = Sprites.frame_info(str(opening.building))
			measured_in_png = Rect2(Vector2.ZERO, frame.source.size).encloses(local_rect)
			var world_rect := Rect2(building.rect.position + local_rect.position, local_rect.size)
			var doorway: Vector2 = Layout.door_positions()[id]
			portal_aligned = absf(doorway.x - world_rect.get_center().x) <= 1 and absf(doorway.y - world_rect.end.y) <= 6
		expect(measured_in_png and local_rect.size.y >= body.size.y + 2 and local_rect.size.y <= int(geometry.reference.door_height_max) and local_rect.size.x >= body.size.x + 1, "measured door opening fits the base body with lateral and height clearance: " + id)
		expect(portal_aligned, "walkable portal meets the visible doorway: " + id)
	var bed: Vector2 = Sprites.frame_info("bed").source.size
	var cup: Vector2 = Sprites.frame_info("tea_ready").source.size
	expect(bed.y >= body.size.y * 1.25 and bed.y <= body.size.y * 2.25 and bed.x >= body.size.x * 1.5, "bed length and width fit the character rather than dwarfing it")
	expect(cup.y <= body.size.y * 0.5 and cup.x <= body.size.x, "prepared cup is smaller than a character")
	for row in Sprites.scenery_objects("street"):
		if not row.get("crop_row", false): continue
		var plants: Array[Dictionary] = Crops.plant_specs(row)
		var crop_scale_ok: bool = plants.size() == 8
		for plant in plants:
			crop_scale_ok = crop_scale_ok and plant.rect.size.y <= body.size.y * 0.6 and plant.rect.size.x <= body.size.x * 1.5 and plant.rect.size == plant.source.size
		expect(crop_scale_ok, "individual plants keep their native small scale within a long row: " + str(row.key))
	print("MEASURED: body=%s bed=%s cup=%s" % [body.size, bed, cup])
	finish()

func finish() -> void:
	print("SCALE: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
