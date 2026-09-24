extends SceneTree
## Real seat targets, walking and control transitions. No save or provider access.
const Seats = preload("res://scripts/seating.gd")
const Targets = preload("res://scripts/world_interactions.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Sprites = preload("res://scripts/sprite_art.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var walked_samples := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func object_for(key: String) -> Dictionary:
	for object: Dictionary in Sprites.scenery_objects("street"):
		if object.key == key: return object
	return {}

func reset_player(scene) -> void:
	for action in ["city_left","city_right","city_up","city_down"]: Input.action_release(action)
	scene.take_control()
	scene.hide_inspector()
	scene.close_help()
	scene.close_door_panel()
	scene.learning.close()
	scene.overlay.dismiss_toast()
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = "street"
	player.pos = [192.0,230.0]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	scene.update_room()
	scene.get_viewport().gui_release_focus()
	scene.controls_active = true
	scene.paused = false
	scene.riding_bicycle = false
	scene.elapsed = 0.0

func click_world(scene, point: Vector2) -> void:
	scene.overlay.dismiss_toast()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = scene.world_to_screen(point)
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func press_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func walk_to_seat(scene) -> bool:
	var player: Dictionary = scene.colony.get_resident("player")
	var safe := true
	for _frame in range(600):
		if scene.seating.is_seated(): return safe
		var before: Vector2 = scene.position_of(player)
		scene.move_resident(player,0.05)
		scene.resolve_player_arrival()
		var after: Vector2 = scene.position_of(player)
		walked_samples += 1
		safe = safe and Navigation.is_walkable(after,"street") and before.distance_to(after) <= 2.41 and Navigation._clear_segment(before,after,"street")
	return false

func run() -> void:
	root.size = Vector2i(768,432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; never load or save normal progress.")
		quit(1)
		return
	var catalog: Array[Dictionary] = Seats.seats()
	var types := {"cafe": 0, "bench": 0, "fountain": 0}
	var ids: Dictionary = {}
	var routes_ok := true
	var targets_ok := true
	var solids_ok := true
	var geometry_ok := true
	var facing_ok := true
	for seat: Dictionary in catalog:
		ids[seat.id] = true
		if str(seat.prop_key).begins_with("cafe_table"): types.cafe += 1
		elif str(seat.prop_key).begins_with("bench"): types.bench += 1
		else: types.fountain += 1
		var object: Dictionary = object_for(seat.prop_key)
		var frame: Dictionary = Sprites.frame_info(object.id)
		geometry_ok = geometry_ok and seat.rect == Rect2(object.rect.position+seat.source_rect.position,seat.source_rect.size) and Rect2(Vector2.ZERO,frame.source.size).encloses(seat.source_rect)
		facing_ok = facing_ok and seat.facing in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT] and Seats.actor_rect(seat).has_area()
		var route: Array[Vector2] = Navigation.route(Vector2(192,230),seat.stand_at)
		routes_ok = routes_ok and not route.is_empty() and route[-1] == seat.stand_at and Navigation.is_walkable(seat.stand_at)
		var previous := Vector2(192,230)
		for point: Vector2 in route:
			routes_ok = routes_ok and Navigation._clear_segment(previous,point,"street")
			previous = point
		var picked: Dictionary = Targets.pick(seat.rect.get_center(),"street")
		targets_ok = targets_ok and picked.get("kind","") == "seat" and picked.get("seat_id","") == seat.id
		targets_ok = targets_ok and picked.get("object",{}).get("glow_rect",Rect2()) == seat.rect
		for prop: Dictionary in Layout.props("street"):
			if prop.key == seat.prop_key and prop.has("footprint"):
				solids_ok = solids_ok and not Navigation.is_walkable(prop.footprint.get_center())
	expect(catalog.size() == 11 and ids.size() == 11 and types == {"cafe":4,"bench":3,"fountain":4}, "catalog provides four cafe stools, three front-facing benches and four fountain edges")
	expect(geometry_ok and facing_ok, "every seat crop and seated body use the actual sprite with a cardinal facing")
	expect(routes_ok, "all eleven approach points are exactly reachable through collision-safe routes")
	expect(targets_ok, "clicks and glow resolve each actual seat crop rather than the whole furnishing")
	expect(solids_ok, "seating never makes cafe tables, benches or fountain solids walkable")
	var negatives_ok := true
	for key in ["cafe_table_left","cafe_table_right"]:
		var object: Dictionary = object_for(key)
		negatives_ok = negatives_ok and Targets.pick(object.rect.position+Vector2(19,6),"street").get("kind","") != "seat"
	for key in ["bench_north","bench_south","bench_west"]:
		var object: Dictionary = object_for(key)
		negatives_ok = negatives_ok and Targets.pick(object.rect.position+Vector2(18,3),"street").get("kind","") != "seat"
	var fountain: Dictionary = object_for("fountain")
	for offset: Vector2 in [Vector2(30,3),Vector2(30,10),Vector2(30,26),Vector2(18,22)]:
		negatives_ok = negatives_ok and Targets.pick(fountain.rect.position+offset,"street").get("kind","") != "seat"
	expect(negatives_ok, "tabletops, backrests, central spout and water never advertise seating")
	var proximity_ok := true
	for seat: Dictionary in catalog: proximity_ok = proximity_ok and Seats.nearest(seat.stand_at,0.1).get("id","") == seat.id
	expect(proximity_ok and Seats.nearest(Vector2.ZERO,1).is_empty() and Seats.nearest(Vector2.INF).is_empty(), "nearby interaction measures safe approach points and rejects distant or invalid positions")
	var old_title: String = catalog.front().title
	catalog.front().title = "Caller mutation"
	expect(Seats.get_seat(str(catalog.front().id)).title == old_title and Seats.get_seat("missing").is_empty(), "seat metadata returned to callers cannot corrupt the catalog")
	catalog = Seats.seats()
	var scene := MainProbe.new()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_url = ""
	scene.service_token = ""
	for resident: Dictionary in scene.colony.residents:
		if resident.id != "player":
			resident.room = resident.id
			resident.pos = Layout.data().entry.duplicate()
			resident.target = resident.pos.duplicate()
	var player: Dictionary = scene.colony.get_resident("player")
	for seat: Dictionary in catalog:
		reset_player(scene)
		click_world(scene,seat.rect.get_center())
		expect(scene.seating.pending_id == seat.id and player.target == [seat.stand_at.x,seat.stand_at.y], "actual viewport click creates the safe approach: " + str(seat.id))
		var arrived := walk_to_seat(scene)
		expect(arrived and scene.seating.active_id == seat.id and scene.position_of(player) == seat.stand_at, "walking reaches a seated pose while keeping logical feet outside furniture: " + str(seat.id))
		expect(scene.pointer_actor_rect(player,scene.colony.daily_state("player")) == Seats.actor_rect(seat) and scene.resident_depth(player,scene.colony.daily_state("player")) == float(seat.sort_y), "picking and draw order follow the seated body: " + str(seat.id))
	var bench: Dictionary = Seats.get_seat("bench_west_front")
	reset_player(scene)
	expect(not scene.seating.request("missing") and scene.seating.pending_id.is_empty(), "an unknown seat cannot create a movement intention")
	player.room = "player"
	scene.update_room()
	expect(not scene.seating.request(str(bench.id)), "an outdoor seat cannot be requested from inside a house")
	reset_player(scene)
	scene.seating.request(str(bench.id))
	var before: Array = player.pos.duplicate()
	scene.paused = true
	scene._process(2.0)
	expect(player.pos == before and scene.seating.pending_id == bench.id and not scene.seating.is_seated(), "pause freezes the approach and cannot activate a distant seated pose")
	scene.paused = false
	walk_to_seat(scene)
	before = player.pos.duplicate()
	scene.paused = true
	scene._process(2.0)
	expect(scene.seating.is_seated() and player.pos == before, "pausing preserves an established seat without moving logical feet")
	scene.paused = false
	press_e()
	expect(not scene.seating.is_seated() and player.pos == before and Navigation.is_walkable(scene.position_of(player)), "E stands on the same accessible floor without teleporting through the bench")
	press_e()
	expect(scene.seating.is_seated() and scene.seating.active_id == bench.id, "E at the real approach point can sit again")
	Input.action_press("city_down")
	scene._process(0.1)
	Input.action_release("city_down")
	expect(not scene.seating.is_seated() and scene.seating.pending_id.is_empty() and player.pos != before and Navigation.is_walkable(scene.position_of(player)), "WASD stands and walks safely in the same input frame")
	scene.seating.request(str(bench.id))
	walk_to_seat(scene)
	click_world(scene,Vector2(290,180))
	expect(not scene.seating.is_seated() and scene.seating.pending_id.is_empty() and player.target == [290.0,180.0], "a new terrain click stands and replaces the seating intention with its walking route")
	reset_player(scene)
	scene.seating.request(str(catalog.front().id))
	Input.action_press("city_down")
	scene._process(0.1)
	Input.action_release("city_down")
	expect(scene.seating.pending_id.is_empty() and not scene.seating.is_seated() and player.target == player.pos, "manual movement cancels an unfinished approach so it cannot seat the player later")
	reset_player(scene)
	scene.riding_bicycle = true
	scene.seating.request(str(bench.id))
	expect(not scene.riding_bicycle and scene.seating.pending_id == bench.id and not scene.colony.can_ride_bicycle(), "requesting a seat dismounts without granting bicycle progression")
	reset_player(scene)
	scene.toggle_autonomy()
	scene.seating.request(str(bench.id))
	expect(not scene.colony.player_autonomy and scene.seating.pending_id == bench.id, "requesting a seat returns from autonomous observation to a deliberate player action")
	walk_to_seat(scene)
	scene.toggle_autonomy()
	expect(not scene.seating.is_seated() and scene.seating.pending_id.is_empty() and scene.colony.player_autonomy, "returning to autonomous life releases an established seat")
	reset_player(scene)
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	mateo.room = "street"
	mateo.pos = [player.pos[0]+20.0,player.pos[1]]
	mateo.target = mateo.pos.duplicate()
	expect(scene.start_player_conversation("mateo"), "chat fixture begins a legitimate nearby encounter without sending text")
	scene.seating.request(str(bench.id))
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty() and scene.seating.pending_id == bench.id, "choosing a seat closes the voluntary chat and releases its reservations")
	scene.take_control()
	expect(scene.seating.pending_id.is_empty() and not scene.seating.is_seated() and player.target == player.pos, "taking control clears remaining seating state and path")
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and not scene.dialogue_request.busy and player.memories.is_empty(), "sitting and standing create no provider calls, invented memories or pending dialogues")
	scene.free()
	await process_frame
	print("SEATING: %d/%d checks passed; %d movement samples" % [checks-failures.size(),checks,walked_samples])
	quit(0 if failures.is_empty() else 1)
