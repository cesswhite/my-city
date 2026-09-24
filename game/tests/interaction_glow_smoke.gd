extends SceneTree
## Effect geometry and cache checks. No scene, user save, provider or asset writes.
const Glow = preload("res://scripts/interaction_glow.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures := 0

class DrawProbe extends Node2D:
	var objects: Array[Dictionary] = []
	var strength := 1.0
	var draws := 0
	func _draw():
		for object in objects:
			Sprites.draw_object(self, object)
			Glow.draw(self, object, strength)
		Glow.draw(self, {"id": "__must_not_load__", "rect": Rect2(12, 48, 10, 10)}, 0.0)
		Glow.draw(self, {"id": "__must_not_load__", "rect": Rect2(12, 48, 10, 10)}, NAN)
		Glow.draw(self, {"id": "__must_not_load__", "rect": Rect2(INF, 48, 10, 10)})
		Glow.draw(self, {"id": "__must_not_load__", "rect": Rect2(12, 48, 10, 10), "tile": true})
		Glow.draw(self, {"id": "__must_not_load__", "rect": Rect2(12, 48, 10, 10), "crop_row": true})
		draws += 1

func _initialize():
	call_deferred("run")

func expect(value: bool, description: String):
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + description)

func alpha_at(image: Image, x: int, y: int) -> float:
	return image.get_pixel(x + Glow.RADIUS, y + Glow.RADIUS).a

func run():
	Glow.clear_cache()
	# An isolated pixel makes it possible to test the actual generated alpha ring.
	var original := Image.create(13, 13, false, Image.FORMAT_RGBA8)
	original.fill(Color.TRANSPARENT)
	original.set_pixel(6, 6, Color.WHITE)
	var source_texture := ImageTexture.create_from_image(original)
	var frame := {"texture": source_texture, "source": Rect2(0, 0, 13, 13)}
	var effect: Dictionary = Glow._mask_for_frame(frame)
	var mask: Image = effect.texture.get_image()
	expect(mask.get_size() == Vector2i(17, 17) and effect.offset == Vector2(-2, -2), "native mask expands precisely two pixels in every direction")
	expect(alpha_at(mask, 6, 6) == 0.0, "source silhouette interior stays transparent in the effect")
	expect(absf(alpha_at(mask, 7, 6) - 0.62) < 0.01, "nearest exterior pixel has the soft inner-ring opacity")
	expect(absf(alpha_at(mask, 7, 7) - 0.36) < 0.01, "diagonal corner has a softer pixel step")
	expect(absf(alpha_at(mask, 8, 6) - 0.14) < 0.01, "second exterior pixel fades out")
	expect(alpha_at(mask, 9, 6) == 0.0 and alpha_at(mask, 8, 8) == 0.0, "halo never reaches beyond two pixels or fills square corners")
	expect(mask.get_pixel(0, 0).a == 0.0 and alpha_at(mask, 0, 0) == 0.0 and alpha_at(mask, 12, 12) == 0.0, "transparent sprite padding does not become a rectangular border")
	var first_stats: Dictionary = Glow.cache_stats()
	var reused := true
	for iteration in range(100):
		reused = reused and Glow._mask_for_frame(frame).texture == effect.texture
	expect(reused, "one hundred cached lookups return the same effect resource")
	expect(Glow.cache_stats() == first_stats and first_stats.image_reads == 1 and first_stats.mask_builds == 1, "repeated lookup performs no new source reads or mask allocations")
	expect(source_texture.get_image().get_data() == original.get_data(), "effect generation leaves source sprite bytes unchanged")

	# A neighboring frame is opaque, but must not contribute to this crop's halo.
	var atlas := Image.create(12, 6, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	atlas.set_pixel(1, 3, Color.WHITE)
	for y in range(6):
		for x in range(6, 12): atlas.set_pixel(x, y, Color.WHITE)
	var atlas_texture := ImageTexture.create_from_image(atlas)
	var left: Dictionary = Glow._mask_for_frame({"texture": atlas_texture, "source": Rect2(0, 0, 6, 6)})
	var left_mask: Image = left.texture.get_image()
	expect(alpha_at(left_mask, 5, 3) == 0.0 and alpha_at(left_mask, 6, 3) == 0.0, "a cropped atlas frame cannot collect halo from a neighboring object")
	var right: Dictionary = Glow._mask_for_frame({"texture": atlas_texture, "source": Rect2(6, 0, 6, 6)})
	expect(right.texture != left.texture and Glow.cache_stats().image_reads == 2, "regions receive separate masks while sharing one source read per atlas")
	expect(Glow._mask_for_frame({"texture": atlas_texture, "source": Rect2(11, 0, 6, 6)}).is_empty(), "out-of-atlas source region is rejected")
	expect(Glow._mask_for_frame({"texture": atlas_texture, "source": Rect2(0.5, 0, 6, 6)}).is_empty(), "fractional source crops cannot resample the pixel mask")

	# Existing art exercises irregular furniture/foliage silhouettes and shared atlas data.
	Glow.clear_cache()
	for id in ["bicycle_broken", "bed", "table", "plant", "exit_mat"]:
		var asset: Dictionary = Sprites.frame_info(id)
		var actual: Dictionary = Glow._mask_for_frame(asset)
		expect(not actual.is_empty(), "real sprite has a generated silhouette effect: " + id)
		var bitmap: Image = Glow._image(asset.texture)
		var result: Image = actual.texture.get_image()
		var interior_clear := true
		var has_outline := false
		for y in range(int(asset.source.size.y)):
			for x in range(int(asset.source.size.x)):
				var input_alpha: float = bitmap.get_pixel(int(asset.source.position.x) + x, int(asset.source.position.y) + y).a
				if input_alpha >= 0.5 and alpha_at(result, x, y) > 0.0: interior_clear = false
		for pixel in range(result.get_width() * result.get_height()):
			if result.get_pixel(pixel % result.get_width(), int(pixel / result.get_width())).a > 0.0: has_outline = true
		expect(interior_clear and has_outline, "real effect outlines the alpha instead of repainting its interior: " + id)
	var probe := DrawProbe.new()
	for object in Sprites.scenery_objects("player"):
		if object.key in ["bed", "table", "project"]: probe.objects.append(object)
	for object in Sprites.scenery_objects("street"):
		if object.key == "cafe":
			var opening: Dictionary = Layout.data().door_openings.ines
			var local_rect: Rect2 = Layout.rect(opening.rect)
			var door: Dictionary = object.duplicate(true)
			door.source_rect = Rect2(Sprites.frame_info(object.id).source.position + local_rect.position, local_rect.size)
			door.glow_rect = Rect2(object.rect.position + local_rect.position, local_rect.size)
			probe.objects.append(door)
	expect(probe.objects.size() == 4 and probe.objects[-1].has("source_rect"), "draw fixture includes three props and the actual cropped café door")
	root.add_child(probe)
	await process_frame
	await process_frame
	expect(probe.draws > 0 and Sprites.missing_assets().is_empty(), "normal props and cropped doors draw without missing resources")
	var rendered_stats: Dictionary = Glow.cache_stats()
	for iteration in range(8):
		probe.strength = 0.15 + float(iteration) * 0.1
		probe.queue_redraw()
		await process_frame
		await process_frame
	expect(probe.draws >= 8 and Glow.cache_stats() == rendered_stats, "animated hover strength redraws without per-frame images or masks")
	probe.free()
	print("INTERACTION GLOW: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
