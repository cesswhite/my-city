extends SceneTree
## Emissive source pixels share their object's depth; only soft light is global.
const Lighting = preload("res://scripts/world_lighting.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const IDS := ["cafe", "homes", "alma_home", "workshop", "player_home", "lamp"]
const ACTOR_COLOR := Color(0.17,0.56,0.72)
var checks := 0
var failures: Array[String] = []

class Surface:
	extends Node2D
	var object: Dictionary
	var local_light := true
	var covered := false
	func _draw() -> void:
		Sprites.draw_object(self,object)
		if local_light: Lighting.draw_object_lights(self,object,"street",1320)
		if covered:
			for region: Rect2 in Lighting.object_light_regions(object.id):
				draw_rect(Rect2(object.rect.position+region.position,region.size),ACTOR_COLOR)

class LegacyEmission:
	extends Node2D
	var object: Dictionary
	func _draw() -> void:
		var tint := Color(1.0,0.66,0.24,0.72) if object.id == "lamp" else Color(1.0,0.59,0.20,0.33)
		for region: Rect2 in Lighting.object_light_regions(object.id):
			draw_rect(Rect2(object.rect.position+region.position,region.size),tint)

class GlobalLight:
	extends Node2D
	func _draw() -> void: Lighting.draw(self,"street",1320)

func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func difference(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func render(id: String, legacy: bool, covered: bool) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160,180)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source: Dictionary = Sprites.frame_info(id)
	var object := {"id":id,"rect":Rect2(Vector2(24,64),source.source.size)}
	var surface := Surface.new()
	surface.object = object
	surface.local_light = not legacy
	surface.covered = covered
	surface.modulate = Lighting.ambient_for(1320,"street")
	viewport.add_child(surface)
	if legacy:
		var emission := LegacyEmission.new()
		emission.object = object
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		emission.material = material
		viewport.add_child(emission)
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var bitmap := viewport.get_texture().get_image()
	viewport.free()
	return bitmap

func render_checks() -> void:
	var maximum_difference := 0.0
	var covered_difference := 0.0
	for id: String in IDS:
		var reference: Image = await render(id,true,false)
		var replacement: Image = await render(id,false,false)
		var covered: Image = await render(id,false,true)
		var worst: Dictionary = {"delta":0.0}
		for region: Rect2 in Lighting.object_light_regions(id):
			for y in range(int(region.position.y),int(region.end.y)):
				for x in range(int(region.position.x),int(region.end.x)):
					var sample := Vector2i(24+x,64+y)
					var delta: float = difference(reference.get_pixelv(sample),replacement.get_pixelv(sample))
					if delta > float(worst.delta): worst = {"delta":delta,"point":str(sample),"old":str(reference.get_pixelv(sample)),"new":str(replacement.get_pixelv(sample))}
					maximum_difference = maxf(maximum_difference,difference(reference.get_pixelv(sample),replacement.get_pixelv(sample)))
					covered_difference = maxf(covered_difference,difference(covered.get_pixelv(sample),ACTOR_COLOR*Lighting.ambient_for(1320,"street")))
		print("BRIGHTNESS " + id + " " + JSON.stringify(worst))
	print("RENDER difference from additive reference=%.6f covered actor error=%.6f" % [maximum_difference,covered_difference])
	expect(maximum_difference <= 0.015,"nighttime windows and lamp cores preserve their previous rendered brightness")
	expect(covered_difference <= 0.015,"an actor drawn in front fully occludes every hard light source")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480,300)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var global := GlobalLight.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	global.material = material
	viewport.add_child(global)
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var bitmap := viewport.get_texture().get_image()
	var largest_edge := 0.0
	for object: Dictionary in Sprites.scenery_objects():
		for region: Rect2 in Lighting.object_light_regions(str(object.id)):
			for y in range(int(region.position.y),int(region.end.y)):
				for edge in [region.position.x,region.end.x]:
					var point := Vector2i(object.rect.position+Vector2(edge,y))
					largest_edge = maxf(largest_edge,difference(bitmap.get_pixelv(point),bitmap.get_pixelv(point-Vector2i(1,0))))
	print("GLOBAL maximum source-boundary edge=%.6f" % largest_edge)
	expect(largest_edge < 0.10,"global illumination has no hard window or bulb rectangles above actors")
	viewport.free()
	await capture_world()

func capture_world() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152,648)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene = preload("res://scenes/main.tscn").instantiate()
	viewport.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.paused = true
	scene.colony.minute = 1320
	scene.elapsed = 0.0
	var person: Dictionary = scene.colony.get_resident("player")
	person.room = "street"
	var feet := Navigation.move_direction(Vector2(269,176),Vector2.UP,30.0)
	person.pos = [feet.x,feet.y]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	person.appearance.hat = 1
	person.appearance.shirt = 3
	scene.facing.player = Vector2.LEFT
	scene.selected_id = "player"
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	scene.refresh_status()
	scene.update_room()
	scene.update_environment(0.0)
	scene.actors.queue_redraw()
	for _frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../artifacts/facade-collision/alma-window-night.png")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var result := viewport.get_texture().get_image().save_png(output)
	expect(result == OK and Navigation.is_walkable(feet),"nighttime gameplay capture places the avatar at the legal facade boundary")
	print("CAPTURE " + output + " feet=" + str(feet))
	scene.free()
	viewport.free()

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	for id: String in IDS:
		var regions: Array[Rect2] = Lighting.object_light_regions(id)
		var frame: Dictionary = Sprites.frame_info(id)
		var valid := not regions.is_empty()
		var area := 0.0
		for region: Rect2 in regions:
			valid = valid and Rect2(Vector2.ZERO,frame.source.size).encloses(region)
			area += region.get_area()
		var runs: Array[Dictionary] = Lighting._light_runs(id,regions)
		var run_area := 0.0
		for run: Dictionary in runs:
			run_area += run.rect.get_area()
			valid = valid and run.color.a > 0.0
		expect(valid and area == run_area,id + " light covers only the measured opaque glass pixels")
	var cache_size: int = Lighting._source_runs.size()
	for _iteration in range(100):
		for id: String in IDS: Lighting._light_runs(id,Lighting.object_light_regions(id))
	expect(Lighting._source_runs.size() == cache_size and cache_size == IDS.size(),"source pixels and native runs are reused without per-frame image allocation")
	if "--capture-occlusion" in OS.get_cmdline_user_args(): await render_checks()
	print("WORLD OCCLUSION: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
