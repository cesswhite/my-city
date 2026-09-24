extends SceneTree
## Layout and renderer fixture only: no save, simulation, service credentials or network.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Art = preload("res://scripts/pixel_art.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const HOMES = ["cesar", "lupita", "mateo", "ines", "alma", "player"]
var checks := 0
var failures := 0

class InteriorView extends Node2D:
	var room := "player"
	var font: Font
	var completed := false
	func _draw() -> void:
		var sprites = preload("res://scripts/sprite_art.gd")
		draw_rect(Rect2(0, 0, 500, 330), Color("edf0df"))
		draw_string(font, Vector2(18, 26), room.to_upper() + (" / TERMINADO" if completed else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("203c32"))
		var state: Dictionary = {"garden_planted": true, "tea_ready": true, "bicycle_repaired": true} if completed else {}
		sprites.draw_interior(self, font, room, state, false)
		var objects: Array[Dictionary] = sprites.scenery_objects(room, state)
		objects.append({"actor": true, "y": 252.0})
		objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
		for object in objects:
			if object.get("actor", false): sprites.draw_person(self, Vector2(236, 252), {"skin": 2, "hair_style": 0, "shirt": 2}, 1)
			else: sprites.draw_object(self, object, font)
		draw_string(font, Vector2(18, 316), "Sprites 1:1 · entrada libre · distribución por casa", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("203c32"))

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func route_valid(origin: Vector2, destination: Vector2, room: String) -> bool:
	var route: Array[Vector2] = Navigation.route(origin, destination, room)
	if route.is_empty() or route[-1].distance_to(destination) > 0.1: return false
	var previous := origin
	for waypoint in route:
		for step in range(ceili(previous.distance_to(waypoint)) + 1):
			var position: Vector2 = previous.move_toward(waypoint, float(step))
			if not Navigation.is_walkable(position, room): return false
		previous = waypoint
	return true

func by_key(items: Array[Dictionary]) -> Dictionary:
	var result := {}
	for item in items: result[str(item.key)] = item
	return result

func run() -> void:
	expect(Sprites.reload_manifest() == OK and Sprites.validation_errors().is_empty(), "existing native sprites load without generation")
	var wall_styles := {}
	var arrangements := {}
	var entry: Vector2 = Layout.point(Layout.data().entry)
	var exit_point: Vector2 = Layout.point(Layout.data().exit)
	for room in HOMES:
		var section: Dictionary = Layout.section(room)
		var furniture: Dictionary = by_key(Layout.props(room))
		var objects: Dictionary = by_key(Sprites.scenery_objects(room))
		wall_styles[str(section.wall_asset)] = true
		arrangements[JSON.stringify(section.props)] = true
		expect(furniture.bed.rect == Rect2(132, 136, 26, 38) and Layout.stand_at("bed", room) == Vector2(168, 172), "sleep geometry remains stable: " + room)
		expect(furniture.cabinet.rect.end.y <= 151 and furniture.cabinet.rect.position.y >= 120, "kitchen cabinet meets the back wall: " + room)
		expect(room == "player" or furniture.storage.rect.end.y <= 151, "neighbor storage meets the back wall: " + room)
		expect(furniture.chair.rect.position.y >= furniture.table.rect.end.y and furniture.chair_guest.rect.position.y >= furniture.table.rect.end.y, "dining chairs stand in front of the table: " + room)
		var clear_entrance := true
		for obstacle in Layout.obstacles(room):
			if obstacle.intersects(Rect2(220, 218, 32, 52)): clear_entrance = false
		expect(clear_entrance and route_valid(entry, exit_point, room), "front doorway has an unobstructed approach: " + room)
		var native := true
		var supports_valid := true
		for object in objects.values():
			var info: Dictionary = Sprites.frame_info(str(object.id))
			if info.is_empty() or object.rect.size != info.source.size or object.rect.position != object.rect.position.round(): native = false
			var support: String = str(object.get("support", ""))
			if support.is_empty(): continue
			if not objects.has(support): supports_valid = false; continue
			var parent: Dictionary = objects[support]
			var contact: Vector2 = Vector2(object.rect.get_center().x, object.rect.end.y)
			var tabletop: Rect2 = Rect2(parent.rect.position + Vector2(2, 2), Vector2(parent.rect.size.x - 4, 12))
			if not tabletop.has_point(contact) or object.y <= parent.y or object.has("footprint"): supports_valid = false
		expect(native, "all furniture and decorations render at native PNG dimensions: " + room)
		expect(supports_valid, "tabletop objects have real supports and render above them: " + room)
		var interactions_valid := true
		for item in Art.interior_items(room):
			if not route_valid(entry, item.stand_at, room): interactions_valid = false
		expect(interactions_valid and route_valid(entry, Layout.point(Layout.data().home_rest), room), "every interaction and rest spot has a collision-safe route: " + room)
		expect(Navigation._grids.has(room), "navigation caches the actual room geometry: " + room)
	expect(wall_styles.size() == 3 and arrangements.size() == HOMES.size(), "all six homes have distinct arrangements across three native wall palettes")
	var original: Vector2 = Layout.props("player")[0].rect.position
	var detached: Array[Dictionary] = Layout.props("player")
	detached[0].rect.position = Vector2.ZERO
	expect(Layout.props("player")[0].rect.position == original, "renderer adjustments cannot mutate cached room geometry")
	var required_lamps := {"lamp_plaza": false, "lamp_homes": false, "lamp_south": false}
	for area in Layout.outdoor_ids():
		for lamp: Dictionary in Layout.props(area):
			if str(lamp.id) != "lamp": continue
			var id: String = str(lamp.key)
			if required_lamps.has(id): required_lamps[id] = true
			var solid_base: bool = lamp.has("footprint") and not Navigation.is_walkable(lamp.footprint.get_center(), area)
			expect(lamp.rect.size == Vector2(10, 39) and solid_base, "outdoor lamp keeps native scale and a solid base in its actual area: " + area + ":" + id)
	for id in required_lamps:
		expect(required_lamps[id], "required lamp remains present after neighborhood distribution: " + id)
	var initial: Dictionary = by_key(Sprites.scenery_objects("player"))
	var completed: Dictionary = by_key(Sprites.scenery_objects("player", {"tea_ready": true, "garden_planted": true, "bicycle_repaired": true}))
	expect(completed.tea.rect.end.y == initial.tea.rect.end.y and completed.tea.id == "tea_ready", "prepared cup keeps its tabletop contact when its sprite size changes")
	expect(completed.storage.rect == initial.storage.rect and completed.storage.id == "planter_seeded" and completed.project.id == "bicycle_fixed", "verified project states keep their station geometry")
	print("INTERIORS: %d/%d checks passed" % [checks - failures, checks])
	if "--capture" in OS.get_cmdline_user_args() and failures == 0: await capture()
	quit(0 if failures == 0 else 1)

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		expect(false, "capture requires a graphical renderer")
		return
	var output: String = ProjectSettings.globalize_path("res://../artifacts/interiors")
	DirAccess.make_dir_recursive_absolute(output)
	var atlas := SubViewport.new()
	atlas.size = Vector2i(1000, 990)
	atlas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(atlas)
	for index in range(HOMES.size()):
		var room: String = HOMES[index]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(500, 330)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var view := InteriorView.new()
		view.room = room
		view.font = load("res://assets/fonts/PixelOperator.ttf")
		viewport.add_child(view)
		await process_frame
		await RenderingServer.frame_post_draw
		expect(viewport.get_texture().get_image().save_png(output.path_join(room + ".png")) == OK, "captured isolated room: " + room)
		viewport.remove_child(view)
		atlas.add_child(view)
		view.position = Vector2(index % 2 * 500, floori(index / 2.0) * 330)
		viewport.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(atlas.get_texture().get_image().save_png(output.path_join("all-homes.png")) == OK, "captured all six compositions")
	atlas.queue_free()
