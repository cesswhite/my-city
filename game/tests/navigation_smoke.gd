extends SceneTree
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Colony = preload("res://scripts/colony.gd")
const Art = preload("res://scripts/pixel_art.gd")
var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, text: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func _path_is_safe(origin: Vector2, points: Array[Vector2], room: String) -> bool:
	if points.is_empty():
		return false
	var previous: Vector2 = origin
	for point in points:
		if not Navigation._clear_segment(previous, point, room):
			return false
		previous = point
	return true

func _prop(room: String, key: String) -> Dictionary:
	for item: Dictionary in Layout.props(room):
		if item.key == key: return item
	return {}

func _run() -> void:
	var entry: Vector2 = Layout.point(Layout.data().entry)
	var exit: Vector2 = Layout.point(Layout.data().exit)
	var starting_positions = [Vector2(236, 210), Vector2(264, 214), Vector2(386, 178), Vector2(110, 178), Layout.point(Colony.PLACES.huerto), Vector2(192, 230)]
	for point in starting_positions:
		_check(Navigation.is_walkable(point), "initial resident feet are outside solids: " + str(point))
	for home in Navigation.door_positions():
		var door: Vector2 = Navigation.door_positions()[home]
		var path: Array[Vector2] = Navigation.route(Vector2(192, 230), door)
		_check(_path_is_safe(Vector2(192, 230), path, "street") and path[-1] == door, "walk to exact doorway: " + home)
		var bedside: Vector2 = Layout.stand_at("bed", home)
		var indoor: Array[Vector2] = Navigation.route(entry, bedside, home)
		_check(_path_is_safe(entry, indoor, home), "walk around furniture: " + home)
		var leave: Array[Vector2] = Navigation.route(bedside, exit, home)
		_check(_path_is_safe(bedside, leave, home) and leave[-1] == exit, "interior exit reachable: " + home)
		for item in Art.interior_items(home):
			_check(_path_is_safe(entry, Navigation.route(entry, item.stand_at, home), home), "object inspection reachable: " + home + " · " + item.title)
	var detour: Array[Vector2] = Navigation.route(Vector2(192, 232), Vector2(284, 232))
	_check(_path_is_safe(Vector2(192, 232), detour, "street") and detour.size() > 24, "fountain crossing detours around basin")
	_check(Navigation.route(Vector2(192, 230), Vector2(236, 236)).is_empty(), "deep fountain click fails without teleport")
	_check(Navigation.route(Vector2(192, 230), Vector2(82, 120)).is_empty(), "building interior cannot be clicked through")
	var bed_center: Vector2 = _prop("cesar", "bed").footprint.get_center()
	_check(Navigation.route(entry, bed_center, "cesar").is_empty(), "deep bed click is rejected")
	var table: Rect2 = _prop("cesar", "table").footprint
	var edge: Vector2 = table.position + Vector2(table.size.x / 2, 2)
	var table_edge: Array[Vector2] = Navigation.route(entry, edge, "cesar")
	_check(not Navigation.is_walkable(edge,"cesar") and _path_is_safe(entry, table_edge, "cesar") and table_edge[-1] != edge and table_edge[-1].distance_to(edge) <= 12, "compact table click reaches nearby floor without crossing its footprint")
	_check(Navigation.route(Vector2(236, 236), Vector2(192, 230)).is_empty(), "invalid origin does not teleport out of fountain")
	var nearby: Array[Vector2] = Navigation.route(Vector2(192, 230), Vector2(205, 230))
	_check(_path_is_safe(Vector2(192, 230), nearby, "street") and nearby[-1].distance_to(Vector2(205, 230)) <= 12, "edge click snaps at most twelve pixels to free floor")
	for raw in Layout.data().places.values():
		var destination: Vector2 = Layout.point(raw)
		_check(_path_is_safe(Vector2(192, 230), Navigation.route(Vector2(192, 230), destination), "street"), "shared venue is reachable: " + str(destination))
	_check(Navigation.door_positions().player == Layout.point(Colony.HOME_DOORS.player), "player doorway agrees with the shared simulation geometry")
	var shop: Dictionary = Art.street_items()[0]
	_check(shop.id == "shop" and shop.stand_at == Layout.stand_at("shop", "street"), "shop advertises the agreed service point")
	var shopping_path: Array[Vector2] = Navigation.route(Navigation.door_positions().player, shop.stand_at)
	_check(_path_is_safe(Navigation.door_positions().player, shopping_path, "street") and shopping_path[-1] == shop.stand_at, "can walk from own doorstep to the shop")
	_check(Navigation.route(Vector2(192, 230), Vector2(48, 222)).is_empty(), "shop counter cannot be crossed")
	var home_area: String = Layout.home_area("player")
	var home_wall: Vector2 = _prop(home_area,"player_home").footprint.get_center()
	_check(Navigation.route(Layout.door_positions().player, home_wall, home_area).is_empty(), "player house wall cannot be crossed in its actual block")
	var stations: Dictionary = {}
	for item in Art.interior_items("player"):
		if item.has("station"):
			stations[item.station] = item.stand_at
	_check(stations == {"bicycle": Layout.stand_at("bicycle"), "planting": Layout.stand_at("planting"), "tea_station": Layout.stand_at("tea_station")}, "practice station IDs and positions agree with the simulation")
	_check(Navigation.home_spawns().player == entry, "player spawn is the shared safe entry point")
	for old_position in [Vector2(49, 210), Vector2(380, 240)]:
		var recovered: Vector2 = Navigation.recover_position(old_position)
		_check(Navigation.is_walkable(recovered) and recovered.distance_to(old_position) <= 64, "load migration recovers newly solid old position: " + str(old_position))
		_check(_path_is_safe(recovered, Navigation.route(recovered, Vector2(192, 230)), "street"), "recovered position reconnects to street routes")
	_check(Navigation.recover_position(Vector2(192.5, 230.25)) == Vector2(192.5, 230.25), "load migration preserves valid positions exactly")
	_check(Navigation.recover_position(Vector2(-500, -500)) == Vector2(192, 230), "distant invalid street position uses safe fallback")
	_check(Navigation.recover_position(Vector2(-500, -500), "player") == entry, "distant invalid interior position uses entry fallback")
	_check(Navigation.is_walkable(Navigation.recover_position(Vector2(144, 160), "player"), "player"), "load migration recovers position inside furniture")
	_check(Navigation.route(Vector2(49, 210), Layout.stand_at("shop", "street")).is_empty(), "normal movement still rejects invalid origins without migration")
	_check(Navigation.route(entry, exit, "unknown").is_empty(), "unknown rooms fail closed")
	for home in Navigation.door_positions():
		_check(Navigation.door_positions()[home] == Layout.point(Colony.HOME_DOORS[home]), "portal and simulation share doorway: " + home)
		_check(_path_is_safe(entry, Navigation.route(entry, Layout.point(Colony.HOME_REST), home), home), "shared rest position remains reachable: " + home)
	_check(_path_is_safe(Vector2(336, 254), Navigation.route(Vector2(336, 254), Layout.point(Colony.PLACES.huerto)), "street"), "garden western entrance reaches the semantic cultivation destination")
	var world = Colony.new()
	world.setup(false, true)
	_check(world._progression.catalog.shop.pos == [shop.stand_at.x, shop.stand_at.y], "purchase validation uses the reachable shop stand")
	for apprenticeship in world.available_apprenticeships():
		var station: Dictionary = apprenticeship.practice_station
		_check(Layout.point(station.pos) == stations[station.id], "procedure validation uses the same interaction stand: " + station.id)
	print("RESULT: %d/%d navigation checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
