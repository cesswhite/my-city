extends SceneTree
## Read-only native-pixel contracts; no Colony, saves, simulation or providers.
const Sprites = preload("res://scripts/sprite_art.gd")
const Lighting = preload("res://scripts/world_lighting.gd")
const Ambient = preload("res://scripts/ambient_environment.gd")
const Activities = preload("res://scripts/activity_visuals.gd")
const Crops = preload("res://scripts/crop_sprites.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Seats = preload("res://scripts/seating.gd")
const Interactions = preload("res://scripts/world_interactions.gd")
var checks := 0
var failures: Array[String] = []
var manifest: String = Sprites.MANIFEST_PATH

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
	else: print("PASS: " + label)

func contains(regions: Array, at: Vector2) -> bool:
	for region in regions:
		var rect: Rect2 = region if region is Rect2 else Layout.rect(region)
		if rect.has_point(at): return true
	return false

func bitmap_for(id: String) -> Image:
	var image: Image = Sprites.frame_info(id).texture.get_image()
	if image.is_compressed(): image.decompress()
	return image

func legacy_profile() -> Error:
	var result: Error = Sprites.reload_manifest(manifest)
	if result == OK:
		# A metadata-only legacy fixture keeps this test independent of optional
		# art audit backups. It never writes PNGs, a manifest or player saves.
		for entry: Dictionary in Sprites._manifest.assets.values(): entry.erase("art_direction")
	return result

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): manifest = arg.trim_prefix("--manifest=")
	var layout_before := JSON.stringify(Layout.data())
	expect(legacy_profile() == OK, "legacy metadata loads without rewriting or activating assets")
	expect(not Sprites.uses_revised_art("lamp") and Lighting.lamp_core() == Rect2(4,5,2,4), "legacy lantern retains its original measured glass")
	var old_emitters: Array[Dictionary] = Lighting.emitters("street")
	var old_bed: Dictionary = Activities.sleep_layout("player")
	var old_seat: Dictionary = Seats.get_seat("fountain_north")
	expect(old_bed.head.position - old_bed.bed.position == Vector2(7,5), "legacy sleeping pose remains unchanged")
	var wind = Ambient.new()
	wind.advance(0.01, 720, "street", false)
	wind._prepared("bunting")
	var before_reads: int = wind.cache_stats().image_reads
	var old_chimneys: Array[Dictionary] = wind._chimney_positions().duplicate(true)
	expect(Sprites.reload_manifest(manifest) == OK, "requested replacement manifest loads")
	if not Sprites.uses_revised_art("lamp"):
		expect(false, "replacement fixture requires per-asset art_direction provenance")
		finish()
		return
	expect(not Sprites.uses_revised_art("char_body"), "unchanged character assets do not opt into scenery recalibration")
	expect(Lighting.lamp_core() == Rect2(4,11,2,4), "replacement lantern targets the glass below its metal cap")
	var lamp_regions: Array[Rect2] = Lighting.object_light_regions("lamp")
	expect(contains(lamp_regions,Vector2(5,12)) and not contains(lamp_regions,Vector2(4,5)), "light reaches the flame and excludes the old metal-tip location")
	var lamp_image := bitmap_for("lamp")
	var warm := true
	for x in range(4,6):
		for y in range(11,15):
			var pixel := lamp_image.get_pixel(x,y)
			warm = warm and pixel.a > 0.99 and pixel.r >= pixel.b and pixel.g >= pixel.b and pixel.r > 0.75
	expect(warm, "every replacement glow pixel belongs to the visible warm lantern glass")
	var street_lamp := Vector2.ZERO
	for object in Layout.props("street"):
		if object.id == "lamp": street_lamp = object.rect.position; break
	var lamp_found := false
	for emitter in Lighting.emitters("street"):
		if emitter.kind == "lamp" and emitter.at == street_lamp + Vector2(5,13): lamp_found = true
	expect(lamp_found and Lighting.emitters("street") != old_emitters, "cached light centers follow the replacement glass after a manifest switch")
	var excluded := {"cafe":[Vector2(25,61),Vector2(28,64),Vector2(80,65),Vector2(74,72)],"homes":[Vector2(47,46),Vector2(44,49),Vector2(45,54)],"alma_home":[Vector2(47,48),Vector2(46,51),Vector2(48,56)],"workshop":[Vector2(82,41),Vector2(89,46),Vector2(84,43),Vector2(85,49),Vector2(91,54)],"player_home":[Vector2(14,42),Vector2(16,44),Vector2(54,42),Vector2(56,49)]}
	for id in excluded:
		var regions: Array[Rect2] = Lighting.object_light_regions(id)
		var frame: Dictionary = Sprites.frame_info(id)
		var image := bitmap_for(id)
		var valid := not regions.is_empty()
		for region: Rect2 in regions:
			valid = valid and Rect2(Vector2.ZERO,frame.source.size).encloses(region)
			for x in range(int(region.position.x),int(region.end.x)):
				for y in range(int(region.position.y),int(region.end.y)): valid = valid and image.get_pixel(x,y).a > 0.99
		expect(valid, "opaque native glass crops fit " + id)
		var safe := true
		for point in excluded[id]: safe = safe and not contains(regions,point)
		expect(safe, "night glow excludes actual mullions, sill and plants on " + id)
	expect(Lighting.window_panes("cafe")[0].size() == 4 and Lighting.window_panes("workshop")[0].size() == 9, "light follows the replacement two-column café and three-column workshop")
	var indoor: Array = Lighting.indoor_panes()
	var cloth_safe := true
	for point in [Vector2(13,8),Vector2(14,18),Vector2(10,14),Vector2(18,10),Vector2(10,13),Vector2(9,17),Vector2(11,20)]: cloth_safe = cloth_safe and not contains(indoor,point)
	expect(cloth_safe and contains(indoor,Vector2(10,8)) and contains(indoor,Vector2(16,16)), "the indoor night mask darkens the outside view without darkening curtain folds or wooden dividers")
	var bed: Dictionary = Activities.sleep_layout("player")
	var pillow := Rect2(bed.bed.position + Vector2(9,10),Vector2(12,5))
	expect(pillow.has_point(bed.head.get_center()), "the native head rests at the replacement pillow center")
	expect(bed.head.size == Activities.HEAD_SOURCE.size and bed.quilt.size == bed.quilt_source.size, "head and quilt retain their native pixel scale")
	expect(bed.quilt_source.position.y == 19 and bed.quilt.position.y == bed.head.end.y and bed.bed.encloses(bed.head) and bed.bed.encloses(bed.quilt), "quilt meets the lower head edge and both stay inside the real bed")
	var plants: Array[Dictionary] = Crops.plant_specs({"rect":Rect2(344,232,112,16)},true)
	expect(plants.size() == 8, "each physical crop row still renders eight separate native plants")
	var no_soil := true
	var leafy := true
	for plant in plants:
		var frame: Dictionary = Sprites.frame_info(plant.asset)
		var source: Rect2 = plant.source
		var image := bitmap_for(plant.asset)
		var amount := 0
		for run: Rect2 in Crops._foliage_runs(frame.texture,source):
			amount += int(run.get_area())
			for x in range(int(run.position.x),int(run.end.x)):
				var pixel := image.get_pixel(x,int(run.position.y))
				no_soil = no_soil and pixel.a > 0.99 and pixel.g > pixel.r and pixel.g > pixel.b
		leafy = leafy and amount >= 20
	expect(leafy and no_soil, "each shoot keeps a visible leaf silhouette without copying rectangular brown soil")
	for pair in [[Rect2(1,4,10,9),Vector2(10,6)]]:
		expect(contains(Crops._foliage_runs(Sprites.frame_info("garden_right").texture,pair[0]),pair[1]), "replacement right-hand leaf tip is not clipped: " + str(pair[1]))
	var runs: Array[Dictionary] = wind._prepared("bunting")
	expect(wind.cache_stats().image_reads == before_reads+1, "the existing wind controller invalidates old image slices on manifest replacement")
	wind._prepared("bunting")
	expect(wind.cache_stats().image_reads == before_reads+1, "repeated wind frames reuse source pixels instead of reading the texture again")
	var parts := {}
	for run in runs: parts[int(run.layer)] = true
	expect(parts.size() == 7, "the replacement banner has six independent flag portions and a fixed cord")
	var cord_fixed := true
	for point in [Vector2i(19,0),Vector2i(74,0),Vector2i(42,10),Vector2i(52,10)]: cord_fixed = cord_fixed and wind._layer("bunting",point) == 0
	expect(cord_fixed, "rope endpoints and central catenary never sway with the flag cloth")
	var moving := true
	for point in [Vector2i(24,15),Vector2i(34,16),Vector2i(44,18),Vector2i(52,18),Vector2i(60,16),Vector2i(70,14)]: moving = moving and wind._layer("bunting",point) > 0
	expect(moving, "all six visible flag bodies belong to their animated portions")
	wind.elapsed = 8.25
	var gentle := wind.gust_strength() > 0.8
	for seed in range(6): gentle = gentle and absi(wind._sway(seed)) <= 1
	expect(gentle, "replacement cloth still moves by at most one native pixel during a gust")
	expect(wind._chimney_positions() != old_chimneys and Ambient.chimney_at("cafe") == Vector2(83,1), "smoke uses the replacement chimney opening after a cache refresh")
	var seat: Dictionary = Seats.get_seat("fountain_north")
	expect(seat.source_rect == Rect2(18,9,5,3) and seat.anchor == old_seat.anchor and seat.stand_at == old_seat.stand_at, "northern rim crop excludes the new stream without moving the seated person or logical feet")
	var fountain: Dictionary = {}
	for prop in Sprites.scenery_objects("street"):
		if prop.id == "fountain": fountain = prop; break
	expect(Interactions.pick(fountain.rect.position+Vector2(20,9),"street").get("seat_id","") == "fountain_north", "the remaining northern stone rim is still a usable seat")
	expect(Interactions.pick(fountain.rect.position+Vector2(23,10),"street").get("kind","") != "seat", "clicking the replacement water jet no longer selects the northern seat")
	expect(JSON.stringify(Layout.data()) == layout_before, "recalibration changes no world geometry, footsteps, doors or gameplay anchors")
	expect(legacy_profile() == OK and Lighting.object_light_regions("lamp")[0] == Rect2(4,5,2,4) and Ambient.flag_sections() == Ambient.FLAG_SECTIONS, "switching back restores all legacy profiles")
	expect(Seats.get_seat("fountain_north").source_rect == Rect2(18,9,6,3), "seat cache also restores the original rim when switching back")
	finish()

func finish() -> void:
	print("ART RECALIBRATION %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
