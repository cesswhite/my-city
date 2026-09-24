extends SceneTree
## Generated sprite contract, atlas frames, customization and scene composition.
const Layout = preload("res://scripts/world_layout.gd")
const Crops = preload("res://scripts/crop_sprites.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Navigation = preload("res://scripts/navigation.gd")
const APPEARANCE := {"skin": 0, "hair": 0, "eyes": 0, "shirt": 0, "pants": 0, "hair_style": 0, "beard": 0, "hat": 0}

var checks: int = 0
var failures: Array[String] = []

class DrawProbe extends Node2D:
	var room: String = "street"
	var drew: bool = false
	func _draw() -> void:
		var art = preload("res://scripts/sprite_art.gd")
		if Layout.is_outdoor(room):
			art.draw_world(self, null, false, room)
		else:
			art.draw_interior(self, null, room, {"garden_planted": true, "tea_ready": true, "bicycle_repaired": true}, false)
		for object in art.scenery_objects(room, {"garden_planted": true, "tea_ready": true, "bicycle_repaired": true}):
			art.draw_object(self, object)
		for index in range(4):
			art.draw_person(self, Vector2(200 + index * 24, 180), {"hat": index, "hair_style": index}, 1, true, index, [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP][index])
		art.draw_person(self, Vector2(650, 180), {}, 3)
		art.draw_bicycle(self, Vector2(280, 180), {}, true, 3, Vector2.LEFT)
		drew = true

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func signature(layers: Array[Dictionary]) -> String:
	var entries: Array[String] = []
	for layer in layers:
		entries.append("%s:%s:%s" % [layer.id, layer.source, layer.tint])
	return "|".join(entries)

func object_ids(objects: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for object in objects:
		ids.append(str(object.id))
	return ids

func read_png(path: String) -> Image:
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return image

func run() -> void:
	expect(Sprites.reload_manifest("res://assets/sprites/__missing_fixture__.json") == ERR_FILE_NOT_FOUND, "missing manifest is reported explicitly")
	expect("manifest" in Sprites.missing_assets() and not Sprites.last_error.is_empty(), "missing art leaves a diagnostic instead of procedural substitutes")
	var loaded: Error = Sprites.reload_manifest()
	expect(loaded == OK, "generated sprite manifest exists and parses")
	if loaded != OK:
		push_error(Sprites.last_error + " — import the generated assets before running sprite_smoke.")
		finish()
		return
	var errors: PackedStringArray = Sprites.validation_errors()
	expect(errors.is_empty(), "all scenery and character PNGs/atlas regions load: " + "; ".join(errors))
	if not errors.is_empty():
		finish()
		return
	expect(Sprites.is_ready() and Sprites.missing_assets().is_empty(), "renderer reports ready only with complete declared art")
	var data: Dictionary = Sprites.manifest_data()
	var frame_size := Vector2(float(data.characters.size[0]), float(data.characters.size[1]))
	var foot_anchor := Vector2(float(data.characters.anchor[0]), float(data.characters.anchor[1]))
	expect(frame_size == Vector2(24, 32) and foot_anchor == Vector2(12, 30), "character frame and foot anchor use the agreed pixel dimensions")
	var texture: Texture2D = Sprites.frame_info("cafe").texture
	expect(texture == Sprites.frame_info("cafe").texture, "repeated draws reuse the same decoded PNG texture")
	expect(texture.get_size() == Vector2(float(data.assets.cafe.size[0]), float(data.assets.cafe.size[1])), "cached texture preserves the imported native pixel dimensions")
	if FileAccess.file_exists(str(data.assets.cafe.path) + ".import"):
		expect(texture.resource_path == str(data.assets.cafe.path), "an imported sprite loads as its exportable Texture2D resource")
	var configuration_is_layered := true
	var controls: Array[String] = []
	for layer in data.characters.get("layers", []):
		for property in ["select", "tint"]:
			var key: String = str(layer.get(property, ""))
			if not key.is_empty():
				controls.append(key)
	for key in APPEARANCE:
		configuration_is_layered = configuration_is_layered and key in controls
	expect(configuration_is_layered, "manifest exposes all eight appearance controls as generated layers or tints")
	var base: Array[Dictionary] = Sprites.character_layers(APPEARANCE)
	expect(base.size() >= 5, "a character contains separate skin, clothing, eyes and hair artwork")
	for key in APPEARANCE:
		var changed: Dictionary = APPEARANCE.duplicate()
		changed[key] = 1
		expect(signature(Sprites.character_layers(changed)) != signature(base), "appearance control changes the rendered sprite layers: " + key)
	for selector in ["hair_style", "beard", "hat"]:
		var found := false
		var distinct_images: Dictionary = {}
		var expected_variants: int = 0
		for layer in data.characters.get("layers", []):
			if layer.get("select", "") != selector:
				continue
			found = true
			for id in layer.get("variants", []):
				if str(id).is_empty():
					continue
				expected_variants += 1
				var image: Image = read_png(str(data.assets[str(id)].path))
				distinct_images[hash(image.get_data())] = true
		expect(found and expected_variants > 0 and distinct_images.size() == expected_variants, selector + " variants contain distinct generated PNG pixels")
	var animated_id := ""
	for layer in data.characters.get("layers", []):
		var id: String = str(layer.get("asset", ""))
		if int(data.assets.get(id, {}).get("frames", 1)) >= 4:
			animated_id = id
			break
	expect(not animated_id.is_empty(), "body artwork declares four real animation frames")
	if not animated_id.is_empty():
		var idle: Dictionary = Sprites.frame_info(animated_id, false, 3, Vector2.DOWN)
		var step: Dictionary = Sprites.frame_info(animated_id, true, 3, Vector2.DOWN)
		var upward: Dictionary = Sprites.frame_info(animated_id, true, 3, Vector2.UP)
		expect(step.source.position.x - idle.source.position.x == 72 and step.source.size == Vector2(24, 32), "walking selects an actual fourth frame while idle selects the first")
		expect(upward.source.position.y - step.source.position.y == 96, "upward facing selects the fourth directional row")
		expect(Sprites.frame_info(animated_id, true, 7).source == step.source, "walking frame indices wrap over the imported sheet")
		var animation_changes_pixels := false
		for layer in data.characters.get("layers", []):
			var id: String = str(layer.get("asset", ""))
			if int(data.assets.get(id, {}).get("frames", 1)) < 4:
				continue
			var atlas: Image = read_png(str(data.assets[id].path))
			var first: Rect2 = Sprites.frame_info(id).source
			var stride: Rect2 = Sprites.frame_info(id, true, 3).source
			animation_changes_pixels = animation_changes_pixels or hash(atlas.get_region(Rect2i(first)).get_data()) != hash(atlas.get_region(Rect2i(stride)).get_data())
		expect(animation_changes_pixels, "walking frames contain different generated pixels rather than repeating the idle pose")
	expect(Sprites.direction_name(Vector2.LEFT) == "left" and Sprites.direction_name(Vector2(1, -2)) == "up" and Sprites.direction_name(Vector2(NAN, 0)) == "down", "direction selection is deterministic and rejects nonfinite headings")
	var outdoor: Dictionary = {}
	var all_objects: Array[Dictionary] = []
	for room: String in Layout.outdoor_ids():
		outdoor[room] = Sprites.scenery_objects(room)
		all_objects.append_array(outdoor[room])
	var homes := {"ines":["street","cafe"],"cesar":["gardens","homes"],"lupita":["homes","homes"],"mateo":["workshops","workshop"],"alma":["atelier","alma_home"],"player":["homes","player_home"]}
	for owner: String in homes:
		var area: String = homes[owner][0]
		var matches: Array = outdoor.get(area,[]).filter(func(object): return str(object.get("key","")) == str(Layout.data().door_openings[owner].prop_key))
		expect(Layout.home_area(owner) == area and matches.size() == 1 and str(matches[0].id) == homes[owner][1], "exactly one home facade is composed in its own outdoor area: " + owner)
	var shop_areas: Array[String] = []
	for room: String in outdoor:
		for object: Dictionary in outdoor[room]:
			if object.id == "shop": shop_areas.append(room)
	expect(shop_areas == ["street"], "the neighborhood contains exactly one shop, in the central street")
	var geometry_valid := true
	var native_pixels := true
	var signs_fit := true
	var font: Font = load("res://assets/fonts/PixelifySans.ttf")
	var garden_aisle := Rect2()
	for ground in Layout.section("gardens").ground:
		if ground.key == "garden_path": garden_aisle = Layout.rect(ground.rect)
	var garden_rows: int = 0
	var row_keys: Array[String] = []
	var foliage_only := true
	var garden_matches_navigation := true
	for object in all_objects:
		geometry_valid = geometry_valid and object.rect.has_area() and is_finite(float(object.y))
		if object.get("crop_row", false) or object.has("settlement_plot"):
			garden_rows += 1
			row_keys.append(str(object.key))
			var plants: Array[Dictionary] = Crops.plant_specs(object)
			var expected_rows := {"garden_row_north":Rect2(344,232,112,16),"garden_row_south":Rect2(344,260,112,18)}
			garden_matches_navigation = garden_matches_navigation and object in outdoor.gardens and plants.size() == 8 and object.rect == expected_rows.get(str(object.key),Rect2()) and object.rect == object.slot and not object.rect.intersects(garden_aisle)
			for plant in plants:
				var frame: Dictionary = Sprites.frame_info(plant.asset)
				var source: Rect2 = plant.source
				source.position += frame.source.position
				native_pixels = native_pixels and plant.rect.size == source.size and frame.source.encloses(source) and object.rect.encloses(plant.rect)
				var runs: Array[Rect2] = Crops._foliage_runs(frame.texture, source)
				foliage_only = foliage_only and not runs.is_empty()
				var bitmap: Image = frame.texture.get_image()
				if bitmap.is_compressed(): bitmap.decompress()
				for run in runs:
					foliage_only = foliage_only and source.encloses(run) and run.size.y == 1
					for x in range(int(run.position.x), int(run.end.x)):
						var pixel: Color = bitmap.get_pixel(x, int(run.position.y))
						foliage_only = foliage_only and pixel.a >= 0.5 and pixel.g > pixel.r and pixel.g > pixel.b
		elif not object.get("tile", false):
			# The two independent homes intentionally use half of the duplex atlas.
			native_pixels = native_pixels and object.rect.size == Sprites.object_frame(object).source.size
		var sign: Dictionary = Sprites.sign_info(object)
		if not sign.is_empty():
			signs_fit = signs_fit and object.rect.encloses(sign.rect) and font.get_string_size(sign.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sign.size).x <= sign.rect.size.x
	expect(geometry_valid, "scenery exports finite pixel rectangles and a depth anchor for every prop")
	expect(native_pixels, "props across all outdoor areas draw one texture pixel per world pixel instead of resampling")
	expect(signs_fit, "building labels fit the inspected blank boards and their sprite boundaries")
	row_keys.sort()
	expect(garden_matches_navigation and garden_rows == 2 and row_keys == ["garden_row_north","garden_row_south"] and garden_aisle == Rect2(344,248,112,12), "the two exact crop rows in gardens preserve native plant size and the 112 by 12 shared aisle")
	var aisle_walkable := true
	for y in range(int(garden_aisle.position.y),int(garden_aisle.end.y),Navigation.CELL):
		for x in range(int(garden_aisle.position.x),int(garden_aisle.end.x),Navigation.CELL):
			aisle_walkable = aisle_walkable and Navigation.is_walkable(Vector2(x,y),"gardens")
	expect(aisle_walkable and garden_aisle.has_area(), "every navigation cell in the crop aisle remains physically walkable")
	var aisle_route: Array = Navigation.route(Vector2(344,254),Vector2(455,254),"gardens")
	expect(not aisle_route.is_empty() and aisle_route.back().distance_to(Vector2(455,254)) < 0.01, "the garden aisle has an exact route from one end to the other")
	expect(foliage_only, "crop draw runs contain existing opaque foliage without rectangular soil backgrounds")
	for owner: String in Navigation.door_positions():
		var door: Vector2 = Navigation.door_positions()[owner]
		expect(Navigation.is_walkable(door,Layout.home_area(owner)), "sprite composition preserves accessible doorway in its own area: " + owner)
	var unfinished: Array[String] = object_ids(Sprites.scenery_objects("player"))
	var finished: Array[String] = object_ids(Sprites.scenery_objects("player", {"garden_planted": true, "tea_ready": true, "bicycle_repaired": true}))
	expect("bicycle_broken" in unfinished and "planter" in unfinished and "tea_set" in unfinished, "unfinished projects display their original generated sprite state")
	expect("bicycle_fixed" in finished and "planter_seeded" in finished and "tea_ready" in finished and "bicycle_broken" not in finished, "verified projects swap to distinct repaired, seeded and prepared sprites")
	var away: Array[String] = object_ids(Sprites.scenery_objects("player", {"bicycle_away": true}))
	expect("bicycle_broken" not in away and "bicycle_fixed" not in away, "taking the bicycle leaves no duplicate bicycle at home")
	for room in ["cesar", "lupita", "mateo", "ines", "alma", "player"]:
		var ids: Array[String] = object_ids(Sprites.scenery_objects(room))
		expect("bed" in ids and "table" in ids and "rug" not in ids and "exit_mat" not in ids, room + " exposes solid props separately from walkable floor decorations")
	var probe := DrawProbe.new()
	root.add_child(probe)
	await process_frame
	await process_frame
	expect(probe.drew, "street sprites and all directional actors execute in a CanvasItem draw pass")
	for room: String in Layout.outdoor_ids():
		if room == "street": continue
		probe.room = room
		probe.drew = false
		probe.queue_redraw()
		await process_frame
		await process_frame
		expect(probe.drew and Sprites.missing_assets().is_empty(), "outdoor sprites execute without missing assets: " + room)
	probe.room = "player"
	probe.drew = false
	probe.queue_redraw()
	await process_frame
	await process_frame
	expect(probe.drew and Sprites.missing_assets().is_empty(), "interior and completed projects draw without a fallback or missing asset")
	probe.free()
	finish()

func finish() -> void:
	print("SPRITES: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
