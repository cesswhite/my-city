extends SceneTree
## Local rendering fixture: no saved world, providers, or scene lifecycle.
const Ambient = preload("res://scripts/ambient_environment.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const FontAsset = preload("res://assets/fonts/PixelOperator.ttf")
var checks := 0
var failures: Array[String] = []

class Preview extends Node2D:
	var room: String = "street"
	var ambient = Ambient.new()
	var handled: Array[String] = []
	var delegated: Array[String] = []
	var objects: Array[Dictionary] = Sprites.scenery_objects("street")
	func _draw() -> void:
		handled.clear()
		delegated.clear()
		Sprites.draw_world(self, FontAsset, false, room)
		objects.sort_custom(func(a: Dictionary, b: Dictionary): return a.y < b.y)
		for object: Dictionary in objects:
			if ambient.draw_object(self, object, FontAsset): handled.append(object.key)
			else:
				delegated.append(object.key)
				Sprites.draw_object(self, object, FontAsset)
		ambient.draw_foreground(self, room)

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: " + message)
	else:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _frame in range(4): await process_frame

func tick(ambient, count: int, minute: int = 720) -> void:
	for _frame in range(count): ambient.advance(0.1, minute, "street", false)

func run() -> void:
	var ambient = Ambient.new()
	var replica = Ambient.new()
	tick(ambient, 83)
	tick(replica, 83)
	expect(ambient.motion_state() == replica.motion_state(), "identical local inputs produce identical ambient phases")
	expect(ambient.gust_strength() > 0.8, "a short gust occurs inside the calm deterministic cycle")
	var frozen: Dictionary = ambient.motion_state().duplicate(true)
	var foreground: Array[Dictionary] = ambient.foreground_specs("street")
	ambient.advance(0.1, 2200, "street", true)
	expect(ambient.motion_state() == frozen and ambient.foreground_specs("street") == foreground, "pause freezes wind, particles and weather-derived phase")
	for invalid in [-1.0, NAN, INF, 0.0]: ambient.advance(invalid, 720, "street", false)
	expect(ambient.elapsed == frozen.time, "invalid and nonpositive deltas cannot advance animation")
	ambient.advance(1000.0, 720, "street", false)
	expect(is_equal_approx(ambient.elapsed - float(frozen.time), 0.1), "a frame stall advances at most one tenth of a second")
	ambient.advance(0.0, 720, "player", false)
	expect(ambient.foreground_specs("player").is_empty() and ambient.foreground_specs("street").is_empty(), "no exterior effect leaks into interiors")
	ambient.advance(0.0, 720, "street", false)
	var objects: Dictionary = {}
	for object: Dictionary in Sprites.scenery_objects("street"): objects[object.key] = object
	var water_a: Array[Dictionary] = ambient.water_specs(objects.fountain)
	tick(ambient, 2)
	var water_b: Array[Dictionary] = ambient.water_specs(objects.fountain)
	expect(not water_a.is_empty() and water_a != water_b, "fountain water keeps moving independently of sprite position")
	var water_valid := true
	for piece: Dictionary in water_a + water_b:
		water_valid = water_valid and objects.fountain.rect.encloses(piece.rect) and piece.rect.size == Vector2.ONE and ambient._water_mask().has(Vector2i(piece.rect.position - objects.fountain.rect.position))
	expect(water_valid, "all fountain highlights stay on the inspected water pixels, outside stone and pavement")
	var anchors_fixed := true
	var roots_fixed := true
	var originals: Dictionary = {}
	var flag_parts: Dictionary = {}
	var cord_points: Array = [Vector2(19,0),Vector2(74,0),Vector2(42,10),Vector2(52,10)] if Sprites.uses_revised_art("bunting") else [Vector2(15,0),Vector2(79,0),Vector2(42,9),Vector2(52,9)]
	for id: String in ["bunting", "tree", "tree_small", "flowerpot"]:
		var frame: Dictionary = Sprites.frame_info(id)
		originals[id] = hash(frame.texture.get_image().get_data())
		var moving := 0
		for run: Dictionary in ambient._prepared(id):
			if int(run.layer) == 0: continue
			moving += 1
			var local: Rect2 = run.source
			local.position -= frame.source.position
			if id == "bunting":
				flag_parts[int(run.layer)] = true
				anchors_fixed = anchors_fixed and local.position.y >= (9 if Sprites.uses_revised_art(id) else 10)
				for point: Vector2 in cord_points: anchors_fixed = anchors_fixed and not local.has_point(point)
			else: roots_fixed = roots_fixed and local.end.y <= Ambient.CROWN_LIMITS[id]
		expect(moving > 0, id + " has actual existing sprite pixels assigned to its movable section")
	expect(anchors_fixed, "both rope anchors and upper cord pixels remain fixed during wind")
	expect(flag_parts.size() == 6, "all six native flags retain separate animated cloth portions")
	expect(roots_fixed, "tree roots, lower branches and terracotta pots remain fixed")
	var before_cache: Dictionary = ambient.cache_stats().duplicate()
	for _frame in range(100):
		for id: String in ["bunting", "tree", "tree_small", "flowerpot"]: ambient._prepared(id)
		ambient.water_specs(objects.fountain)
	expect(ambient.cache_stats() == before_cache, "one hundred draw preparations reuse native pixels without new image reads or mask allocations")
	var untouched := true
	for id in originals: untouched = untouched and hash(Sprites.frame_info(id).texture.get_image().get_data()) == originals[id]
	expect(untouched, "source textures are never modified by the effect cache")
	var bounded := true
	var smoke_seen := false
	var leaves_seen := false
	var calm_seen := false
	var moving_seen := false
	for step in range(440):
		tick(replica, 1, 1130)
		var effects: Array[Dictionary] = replica.foreground_specs("street")
		bounded = bounded and effects.size() <= Ambient.MAX_FOREGROUND
		calm_seen = calm_seen or replica.gust_strength() == 0.0
		moving_seen = moving_seen or replica._sway() != 0
		for effect: Dictionary in effects:
			bounded = bounded and Ambient.WORLD.encloses(effect.rect) and effect.rect.position == effect.rect.position.round() and effect.rect.size.x <= 2 and effect.rect.size.y <= 2
			smoke_seen = smoke_seen or effect.kind == "smoke"
			leaves_seen = leaves_seen or effect.kind == "leaf"
	expect(bounded and smoke_seen and leaves_seen, "foreground stays within a fixed tiny-particle budget and world limits")
	expect(calm_seen and moving_seen, "wind visibly alternates brief movement and quiet periods")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(936,488)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := Preview.new()
	preview.scale = Vector2(2,2)
	preview.position = Vector2(-24,-96)
	preview.ambient = ambient
	viewport.add_child(preview)
	await settle()
	expect(preview.handled.has("fountain") and preview.handled.has("bunting") and preview.handled.has("tree_east"), "actual drawing handles plaza water, flags and canopies")
	expect(preview.delegated.has("cafe") and preview.delegated.has("bench_south"), "plaza buildings and solid furniture retain the original renderer")
	var capture: String = OS.get_environment("MY_CITY_AMBIENT_CAPTURE")
	if "--capture-ambient" in OS.get_cmdline_user_args() and not capture.is_empty():
		await RenderingServer.frame_post_draw
		expect(viewport.get_texture().get_image().save_png(capture.path_join("gust.png")) == OK, "wind frame exported")
		tick(ambient, 5)
		preview.queue_redraw()
		await settle()
		await RenderingServer.frame_post_draw
		expect(viewport.get_texture().get_image().save_png(capture.path_join("gust-next.png")) == OK, "next animation frame exported")
	preview.room = "gardens"
	preview.objects = Sprites.scenery_objects("gardens")
	ambient.advance(0,720,"gardens",false)
	preview.queue_redraw()
	await settle()
	var productive_rows := 0
	for object in preview.objects:
		if object.key in ["garden_row_north","garden_row_south"] and object.has("crop_stage") and preview.delegated.has(object.key): productive_rows += 1
	expect(productive_rows == 2, "both productive garden rows delegate to their authoritative growth renderer")
	expect(preview.delegated.has("garden_fence") and preview.delegated.has("garden_edge_right"), "garden fences and solid borders stay fixed in their actual area")
	ambient.advance(0,720,"player",false)
	preview.queue_redraw()
	await settle()
	expect(preview.handled.is_empty(), "draw_object also delegates every exterior object when the current room is indoors")
	viewport.queue_free()
	await process_frame
	print("Ambient environment: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
