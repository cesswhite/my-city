extends SceneTree
## Native composite silhouettes only; no player save, providers, or asset writes.
const Glow = preload("res://scripts/interaction_glow.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Activities = preload("res://scripts/activity_visuals.gd")
const FONT = preload("res://assets/fonts/PixelOperator.ttf")
var checks := 0
var failures := 0

class Preview extends Node2D:
	var moving_offset := Vector2.ZERO
	var strength := 1.0
	var draws := 0
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 264, 142), Color("566b58"))
		for index in 4:
			var appearance := {"skin": index, "hair": index, "hair_style": index, "hat": index, "beard": index % 3, "eyes": index, "shirt": index, "pants": index}
			var direction: Vector2 = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP][index]
			var at := Vector2(35 + index * 64, 46) + moving_offset
			Glow.draw_character(self, appearance, at, true, 1, direction, strength)
			Sprites.draw_person(self, at, appearance, 1, true, 1, direction)
			at.y += 47
			Glow.draw_character(self, appearance, at, true, 3, direction, strength)
			Sprites.draw_person(self, at, appearance, 1, true, 3, direction)
		# The actual bed and sleeping renderer cover the lower head halo correctly.
		var person := {"room": "player", "home_id": "player", "appearance": {"hat": 2, "hair_style": 3, "beard": 1}}
		var geometry: Dictionary = Activities.sleep_layout("player")
		var room_origin: Vector2 = Vector2(218, 98) - geometry.bed.position
		draw_set_transform(room_origin)
		Sprites.draw_asset(self, "bed", geometry.bed)
		Glow.draw_sleeping_head(self, person.appearance, geometry.head.position, strength)
		Activities.draw_sleeping(self, person, {"kind": "sleeping"}, "player")
		draw_set_transform(Vector2.ZERO)
		draw_string(FONT, Vector2(14, 125), "Dos pasos · cuatro vistas · sueño", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f4edda"))
		draws += 1
		Glow.draw_character(self, {}, Vector2.ZERO, false, 0, Vector2.DOWN, 0.0)
		Glow.draw_character(self, {}, Vector2(INF, 0))
		Glow.draw_sleeping_head(self, {}, Vector2.ZERO, NAN)

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func alpha_at(effect: Dictionary, at: Vector2) -> float:
	var pixel: Vector2i = Vector2i(at - effect.offset)
	return effect.texture.get_image().get_pixelv(pixel).a

func layer_for(image: Image, offset := Vector2.ZERO, flipped := false, opacity := 1.0) -> Dictionary:
	return {"texture": ImageTexture.create_from_image(image), "source": Rect2(Vector2.ZERO, image.get_size()), "offset": offset, "flip_h": flipped, "tint": Color(1, 1, 1, opacity)}

func run() -> void:
	Glow.clear_cache()
	var body := Image.create(24, 32, false, Image.FORMAT_RGBA8)
	body.fill(Color.TRANSPARENT)
	body.fill_rect(Rect2i(8, 10, 8, 19), Color.WHITE)
	var shirt := Image.create(24, 32, false, Image.FORMAT_RGBA8)
	shirt.fill(Color.TRANSPARENT)
	shirt.fill_rect(Rect2i(6, 16, 12, 8), Color.WHITE)
	var layers: Array[Dictionary] = [layer_for(body), layer_for(shirt)]
	var effect: Dictionary = Glow._mask_for_layers(layers)
	expect(effect.source_size == Vector2(24, 32) and effect.texture.get_size() == Vector2(28, 36), "composite keeps one native frame with the same two-pixel ring as objects")
	expect(alpha_at(effect, Vector2(8, 15)) == 0.0 and alpha_at(effect, Vector2(8, 24)) == 0.0, "shirt edges inside the body never produce internal outlines")
	expect(is_equal_approx(alpha_at(effect, Vector2(6, 16)), 0.0) and absf(alpha_at(effect, Vector2(5, 17)) - 0.62) < 0.01, "sleeve extends the one outer silhouette without painting its pixels")
	expect(alpha_at(effect, Vector2(0, 0)) == 0.0 and alpha_at(effect, Vector2(21, 17)) == 0.0, "transparent frame corners and distant padding have no rectangular halo")
	var initial: Dictionary = Glow.cache_stats()
	var recolored: Array[Dictionary] = layers.duplicate(true)
	recolored[0].tint = Color(0.1, 0.4, 0.8, 1.0)
	recolored[1].tint = Color(0.9, 0.5, 0.2, 1.0)
	expect(Glow._mask_for_layers(recolored).texture == effect.texture and Glow.cache_stats() == initial, "RGB customization reuses the exact mask without a source read")
	var sparse := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	sparse.fill(Color.TRANSPARENT)
	sparse.set_pixel(0, 1, Color.WHITE)
	var mirrored: Dictionary = layer_for(sparse, Vector2(4, -2), true)
	var flipped: Dictionary = Glow._mask_for_layers([mirrored])
	expect(flipped.offset == Vector2(2, -4) and alpha_at(flipped, Vector2(6, -1)) == 0.0 and alpha_at(flipped, Vector2(7, -1)) > 0.6, "horizontal flip and negative layer offset move the silhouette with the real pixels")
	var translucent := mirrored.duplicate()
	translucent.tint = Color(1, 1, 1, 0.4)
	var faint: Dictionary = Glow._mask_for_layers([translucent])
	var combined: Dictionary = Glow._mask_for_layers([translucent, translucent])
	expect(alpha_at(faint, Vector2(7, -1)) == 0.0 and alpha_at(combined, Vector2(7, -1)) > 0.39, "opacity contributes to the union and overlapping translucent layers compose correctly")
	translucent.tint.a = 0.0
	expect(Glow._mask_for_layers([translucent]).is_empty(), "fully transparent character layers create no effect")
	var invalid: Dictionary = mirrored.duplicate()
	invalid.offset.x = 0.5
	expect(Glow._mask_for_layers([invalid]).is_empty(), "fractional source placement cannot blur native pixels")
	invalid = mirrored.duplicate()
	invalid.source.position.x = 2
	expect(Glow._mask_for_layers([invalid]).is_empty(), "an invalid source crop cannot sample neighboring frames")
	Glow.clear_cache()
	var appearance := {"skin": 2, "hair": 1, "hair_style": 3, "hat": 2, "beard": 1, "eyes": 2, "shirt": 1, "pants": 1}
	var painted_pixels := 0
	var actual_images := 0
	var unique_sources: Dictionary = {}
	for direction: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		for phase in 4:
			var actual: Array[Dictionary] = Sprites.character_layers(appearance, true, phase, direction)
			var mask: Dictionary = Glow._mask_for_layers(actual)
			var bitmap: Image = mask.texture.get_image()
			var interior_clear := true
			for layer: Dictionary in actual:
				unique_sources[layer.texture.get_rid().get_id()] = true
				var source: Image = Glow._image(layer.texture)
				for y in 32:
					for x in 24:
						var sx: int = 23 - x if layer.flip_h else x
						if source.get_pixel(int(layer.source.position.x) + sx, int(layer.source.position.y) + y).a < 0.5: continue
						painted_pixels += 1
						var pixel: Vector2i = Vector2i(Vector2(x, y) + layer.offset - mask.offset)
						if bitmap.get_pixelv(pixel).a > 0.0: interior_clear = false
			expect(interior_clear and not mask.is_empty(), "all layers stay clear inside the composite for %s phase%d" % [Sprites.direction_name(direction), phase])
		actual_images = Glow.cache_stats().image_reads
	expect(actual_images == unique_sources.size() and actual_images == 8 and painted_pixels > 1000, "sixteen directional poses read their eight shared source images exactly once")
	var original_appearance: Dictionary = appearance.duplicate(true)
	var head_layers: Array[Dictionary] = Glow._sleeping_head_layers(appearance)
	var head: Dictionary = Glow._mask_for_layers(head_layers)
	expect(head.source_size == Activities.HEAD_SOURCE.size and head_layers.all(func(layer): return layer.source.size == Activities.HEAD_SOURCE.size and layer.key != "hat" and layer.id not in ["char_eyes", "char_shirt", "char_pants"]), "sleep halo includes only the actual uncovered head layers")
	appearance.hat = 0
	expect(Glow._mask_for_layers(Glow._sleeping_head_layers(appearance)).texture == head.texture and original_appearance.hat == 2, "hats removed in bed do not alter the halo or saved appearance")
	for action: String in ["repair", "drink"]:
		var feet := Vector2(100, 80)
		var resident := {"appearance": appearance, "target": [100, 80]}
		var state := {"kind": "working" if action == "repair" else "eating", "action": action}
		var pose: Dictionary = Activities.active_pose(resident, state, feet, 1)
		var active: Array[Dictionary] = Activities.active_layers(appearance, pose)
		var active_mask: Dictionary = Glow._mask_for_layers(active)
		var fits := not active_mask.is_empty()
		for layer: Dictionary in active:
			var bounds := Rect2(active_mask.offset + Vector2(2, 2), active_mask.source_size)
			fits = fits and bounds.encloses(Rect2(layer.offset, layer.source.size))
		expect(fits and active[0].source.size.y == 19 and active[1].offset.y == 19, "composite contains exact idle-leg and gesturing-arm crops for " + action)
		if action == "drink": expect(active[-1].id == "tea_ready" and Rect2(active_mask.offset, active_mask.texture.get_size()).encloses(Rect2(active[-1].offset, active[-1].source.size)), "drinking halo also follows the cup actually held by the character")
	Glow.clear_cache()
	var cache_source: Dictionary = layer_for(sparse)
	var first: Dictionary = Glow._mask_for_layers([cache_source])
	for index in range(1, Glow.MAX_CHARACTER_MASKS + 25):
		var shifted: Dictionary = cache_source.duplicate()
		shifted.offset = Vector2(index, 0)
		Glow._mask_for_layers([shifted])
		Glow._mask_for_layers([cache_source])
	expect(Glow.cache_stats().characters == Glow.MAX_CHARACTER_MASKS and Glow._mask_for_layers([cache_source]).texture == first.texture, "LRU bounds the composite cache while retaining the actively hovered mask")
	expect(Glow.cache_stats().image_reads == 1, "evicting mask variants never rereads their common source image")
	for index in Glow.MAX_SOURCE_IMAGES + 3:
		Glow._mask_for_layers([layer_for(sparse)])
	expect(Glow.cache_stats().images == Glow.MAX_SOURCE_IMAGES and Glow.cache_stats().characters == Glow.MAX_CHARACTER_MASKS, "source bitmap and composite caches both remain bounded under new resources")
	Glow.clear_cache()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1056, 568)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := Preview.new()
	preview.scale = Vector2(4, 4)
	viewport.add_child(preview)
	for _frame in 4: await process_frame
	var rendered: Dictionary = Glow.cache_stats()
	for frame in 8:
		preview.moving_offset = Vector2(frame, frame % 2)
		preview.strength = 0.3 + frame * 0.1
		preview.queue_redraw()
		await process_frame
		await process_frame
	expect(preview.draws >= 8 and Glow.cache_stats() == rendered, "changing position and hover opacity every frame performs no image reads or mask builds")
	expect(Sprites.missing_assets().is_empty(), "all directions, clothing and sleep use existing available sprite layers")
	if "--capture-npc-glow" in OS.get_cmdline_user_args():
		preview.moving_offset = Vector2.ZERO
		preview.strength = 1.0
		preview.queue_redraw()
		for _frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://../artifacts/npc-glow/characters.png")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		expect(viewport.get_texture().get_image().save_png(path) == OK, "real renderer exports the awake and sleeping hover preview")
	viewport.free()
	print("NPC GLOW: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
