extends SceneTree
## Environment anchors, draw layers and safe routes. No scene, saves or provider calls.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Sprites = preload("res://scripts/sprite_art.gd")

var checks: int = 0
var failures: Array[String] = []
var sampled_positions: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func objects_by_key() -> Dictionary:
	var result: Dictionary = {}
	for item in Sprites.scenery_objects("street"):
		result[str(item.get("key", ""))] = item
	return result

func safe_route(origin: Vector2, destination: Vector2) -> bool:
	if not Navigation.is_walkable(origin) or not Navigation.is_walkable(destination): return false
	var route: Array[Vector2] = Navigation.route(origin, destination)
	if route.is_empty() or route[-1].distance_to(destination) > 0.01: return false
	var previous: Vector2 = origin
	for point in route:
		var steps: int = maxi(1, ceili(previous.distance_to(point)))
		for index in range(steps + 1):
			sampled_positions += 1
			if not Navigation.is_walkable(previous.lerp(point, float(index) / steps)): return false
		previous = point
	return true

func check_garden_routes() -> void:
	var garden: Vector2 = Layout.point(Layout.data().places.huerto)
	expect(Navigation.is_walkable(garden), "garden routine destination is outside beds, sign posts and fences")
	for id in Layout.door_positions():
		var door: Vector2 = Layout.door_positions()[id]
		expect(safe_route(door, garden) and safe_route(garden, door), "resident can visit the garden and return home: " + str(id))
	for id in Layout.data().places:
		if id == "huerto": continue
		var destination: Vector2 = Layout.point(Layout.data().places[id])
		expect(safe_route(garden, destination) and safe_route(destination, garden), "garden connects to the daily activity: " + str(id))
	var shop: Vector2 = Layout.stand_at("shop", "street")
	expect(safe_route(garden, shop) and safe_route(shop, garden), "garden remains connected to the shop in both directions")
	for item in Layout.props("street"):
		if not item.get("crop_row", false): continue
		var footprint: Rect2 = item.get("footprint", Rect2())
		expect(footprint.has_area() and not Navigation.is_walkable(footprint.get_center()), "crop bed is a real solid rather than walkable soil: " + str(item.key))

func check_anchors_and_depth(objects: Dictionary) -> void:
	var bunting: Dictionary = objects.get("bunting", {})
	expect(not bunting.is_empty(), "suspended bunting is part of the rendered environment")
	if bunting.is_empty(): return
	var anchors: Array = bunting.get("anchors", [])
	expect(anchors.size() == 2, "bunting declares both physical attachment points")
	for anchor in anchors:
		var support: Dictionary = objects.get(str(anchor.get("support", "")), {})
		expect(not support.is_empty(), "bunting support exists: " + str(anchor.get("support", "")))
		if support.is_empty(): continue
		var attachment: Vector2 = support.rect.position + Layout.point(anchor.point)
		var rope_end: Vector2 = bunting.rect.position + Layout.point(anchor.sprite_point)
		expect(attachment.distance_to(rope_end) <= 0.01, "rope endpoint meets its declared facade attachment: " + str(anchor.support))
		expect(support.rect.has_point(attachment), "bunting attachment lies on its support facade: " + str(anchor.support))
		expect(float(bunting.y) > float(support.y), "bunting draws in front of its supporting facade: " + str(anchor.support))
	expect(not bunting.has("footprint"), "suspended decoration does not create an invisible street wall")
	for id in ["cafe_table_left", "cafe_table_right", "lamp"]:
		var item: Dictionary = objects.get(id, {})
		expect(not item.is_empty() and is_equal_approx(float(item.y), item.rect.end.y), "depth follows the visible feet of the object: " + id)
	var sign: Dictionary = objects.get("garden_sign", {})
	var fence: Dictionary = objects.get("garden_fence", {})
	expect(not sign.is_empty() and not fence.is_empty(), "garden sign has its visible rear fence support")
	if not sign.is_empty() and not fence.is_empty():
		expect(sign.rect.intersects(fence.rect) and float(sign.y) > float(fence.y), "garden label attaches visibly in front of the rear fence")
		expect(not sign.has("footprint"), "fence-mounted sign adds no invisible post to the path")

func check_garden_ground(objects: Dictionary) -> void:
	var ground: Dictionary = {}
	var ground_order: Array[String] = []
	for raw in Layout.section("street").get("ground", []):
		ground[str(raw.key)] = {"id": str(raw.id), "rect": Layout.rect(raw.rect)}
		ground_order.append(str(raw.key))
	var required: Array[String] = ["garden_ground", "garden_soil", "garden_path", "garden_approach", "garden_side_path", "garden_south_path"]
	for id in required:
		expect(ground.has(id), "garden declares its unified ground element: " + id)
		if not ground.has(id): return
	var common: Rect2 = ground.garden_ground.rect
	var soil: Rect2 = ground.garden_soil.rect
	var path: Rect2 = ground.garden_path.rect
	var approach: Rect2 = ground.garden_approach.rect
	var side: Rect2 = ground.garden_side_path.rect
	var south: Rect2 = ground.garden_south_path.rect
	var destination: Vector2 = Layout.point(Layout.data().places.huerto)
	expect(ground.garden_ground.id == "tile_sand" and ground.garden_soil.id == "tile_soil" and common.encloses(soil), "cultivated soil belongs to one warm-earth plot")
	expect(ground_order.find("garden_ground") < ground_order.find("garden_soil") and ground_order.find("garden_soil") < ground_order.find("garden_path"), "the unified plot grounds the soil and its central path")
	expect(path.has_point(destination) and common.has_point(destination), "routine destination stands on the visible central path")
	expect(approach.intersects(side) and common.encloses(side) and common.encloses(south), "western approach and perimeter paths belong to the same plot")
	var rows: Array[Dictionary] = []
	for item in objects.values():
		if not item.get("crop_row", false): continue
		rows.append(item)
		expect(soil.encloses(item.rect) and not item.rect.intersects(path), "long crop row grows in shared soil outside the walking path: " + str(item.key))
		expect(item.rect == item.slot and item.rect == item.footprint, "crop-row layout preserves its full planted area and matching collision: " + str(item.key))
		expect(item.rect.size.x >= item.rect.size.y * 4.0, "crop row reads as a continuous planting rather than an isolated square: " + str(item.key))
	expect(rows.size() == 2, "the new plot contains two continuous planting rows")
	if rows.size() != 2: return
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.rect.position.y < b.rect.position.y)
	expect(rows[0].rect.end.y == path.position.y and rows[1].rect.position.y == path.end.y, "central walkway separates the two planting rows edge to edge")
	var entrance: Vector2 = Vector2(side.get_center().x, path.get_center().y)
	var near_path: Vector2 = Vector2(path.position.x + 4, path.get_center().y)
	expect(Navigation._clear_segment(entrance, destination, "street") and safe_route(entrance, destination) and safe_route(destination, entrance), "western stone-border opening gives real access to the central path")
	var passed: Vector2 = Navigation.move_direction(entrance, Vector2.RIGHT, near_path.x - entrance.x)
	expect(passed.is_equal_approx(near_path), "manual walking crosses the visible western opening without snapping")
	var right_inside: Vector2 = Vector2(path.end.x - 2, path.get_center().y)
	var right_stop: Vector2 = Navigation.move_direction(right_inside, Vector2.RIGHT, 16)
	expect(Navigation.is_walkable(right_stop) and right_stop.x < path.end.x, "the opposite stone border remains solid beside the walkway")
	var perimeter_north: Vector2 = Vector2(side.get_center().x, approach.get_center().y)
	var perimeter_south: Vector2 = Vector2(side.get_center().x, south.get_center().y)
	expect(Navigation._clear_segment(perimeter_north, perimeter_south, "street") and safe_route(perimeter_south, destination), "western perimeter joins the street approach, entrance and southern path")
	var south_far: Vector2 = Vector2(south.end.x - 4, south.get_center().y)
	expect(Navigation._clear_segment(perimeter_south, south_far, "street"), "southern perimeter stays walkable below both long rows")
	var fence: Dictionary = objects.get("garden_fence", {})
	expect(not fence.is_empty() and fence.has("footprint"), "rear fence retains a physical base")
	if not fence.is_empty() and fence.has("footprint"):
		var footprint: Rect2 = fence.footprint
		var start: Vector2 = Vector2(footprint.get_center().x, footprint.position.y - 3)
		var stopped: Vector2 = Navigation.move_direction(start, Vector2.DOWN, 20)
		expect(Navigation.is_walkable(start) and Navigation.is_walkable(stopped) and stopped.y < footprint.position.y, "walking from the street cannot cross the rear fence")

func run() -> void:
	var loaded: Error = Sprites.reload_manifest()
	expect(loaded == OK, "sprite manifest loads before checking the environment")
	if loaded != OK:
		finish()
		return
	var objects: Dictionary = objects_by_key()
	check_anchors_and_depth(objects)
	check_garden_ground(objects)
	check_garden_routes()
	finish()

func finish() -> void:
	print("ENVIRONMENT: %d/%d checks passed; %d sampled route positions." % [checks - failures.size(), checks, sampled_positions])
	quit(0 if failures.is_empty() else 1)
