extends SceneTree
## Real movement/context across connected streets. Optional eight PNGs; no save or network.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Encounters = preload("res://scripts/social_encounters.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var samples := 0
var crossings := 0
var captures := 0
var capture_enabled := false
var save_path := "user://unused_multi_area_%d.json" % OS.get_process_id()
var directory := ""

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func settle() -> void:
	for _frame in range(5): await process_frame

func place(scene: MainProbe, id: String, room: String, point: Vector2) -> void:
	var person: Dictionary = scene.colony.get_resident(id)
	person.room = room
	person.pos = [point.x, point.y]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	person.erase("travel_route")
	person.erase("sleep")
	scene.paths.erase(id)
	scene.colony._daily_life.forget(id)

func park_neighbors(scene: MainProbe) -> void:
	for person: Dictionary in scene.colony.residents:
		if person.id != "player": place(scene, person.id, person.id, Layout.point(Layout.data().home_rest))

func thoughts(scene: MainProbe, id: String) -> Array[String]:
	var lines: Array[String] = []
	for entry: Dictionary in scene.ambient_thoughts.candidates(id): lines.append(entry.text)
	return lines

func walk(scene: MainProbe, to: String, destination: Vector2) -> void:
	var player: Dictionary = scene.colony.get_resident("player")
	var before_room: String = player.room
	var before_pos: Array = player.pos.duplicate()
	scene.walk_to_area(to, destination)
	expect(player.room == before_room and player.pos == before_pos, "request toward " + to + " starts a route without relocating the player")
	var valid := true
	var transitions := true
	var arrived := false
	for _frame in range(1800):
		var old_room: String = player.room
		var old_pos: Vector2 = scene.position_of(player)
		scene.move_resident(player, 1.0 / 30.0)
		scene.update_room()
		scene.resolve_player_arrival()
		samples += 1
		valid = valid and Navigation.is_walkable(scene.position_of(player), player.room)
		if old_room != player.room:
			crossings += 1
			var matched := false
			for edge: Dictionary in Layout.exits(old_room):
				if edge.to == player.room and old_pos.distance_to(edge.at) <= 3.0 and scene.position_of(player).distance_to(edge.spawn) < 0.01: matched = true
			transitions = transitions and matched
		if player.room == to and scene.position_of(player).distance_to(destination) < 0.1 and not player.has("travel_route"):
			arrived = true
			break
	expect(arrived, "physical route reaches " + to + " and completes its final destination")
	expect(valid and transitions, "every step toward " + to + " stays walkable; only registered exits cross areas")
	expect(scene.current_room == player.room and scene.scenery.room == player.room, "renderer and interactions follow the player's actual room after " + to)

func context_checks(scene: MainProbe) -> void:
	var world = scene.colony
	park_neighbors(scene)
	place(scene, "player", "homes", Vector2(280,196))
	place(scene, "mateo", "workshops", Vector2(280,196))
	place(scene, "cesar", "homes", Vector2(302,196))
	scene.update_room()
	var context: Dictionary = world.context_for("player")
	var observed: Array[String] = []
	var local_only := true
	for entry: Dictionary in context.observations:
		observed.append(entry.id)
		local_only = local_only and entry.room == "homes"
	expect("cesar" in observed and "mateo" not in observed and local_only, "equal coordinates in another block do not become an observation or reveal remote activity")
	expect(not scene.player_chat.nearby("mateo") and scene.player_chat.nearby("cesar"), "manual conversation proximity includes the room, not only distance")
	expect(JSON.stringify(context).length() <= 12000, "area metadata stays within the existing private context budget")
	var local_goal: Array = world.get_resident("cesar").target.duplicate()
	scene.encounters.let_leave("cesar", "mateo")
	expect(world.get_resident("cesar").target == local_goal, "a resident does not flee someone at matching coordinates in a different block")
	for venue: String in ["cafe", "taller", "huerto"]:
		var area: String = Layout.place_area(venue)
		var coordinate: Vector2 = Layout.point(world.PLACES[venue])
		place(scene, "mateo", area, coordinate)
		expect(world.conversation_scene_for("mateo").place == venue, "conversation identifies " + venue + " inside its actual block")
		place(scene, "mateo", "homes", coordinate)
		var scene_facts: Dictionary = world.conversation_scene_for("mateo")
		expect(scene_facts.place == "homes" and scene_facts.place_label == Layout.area_title("homes"), "matching coordinates in homes never imply " + venue + " or an indoor house")
	place(scene, "cesar", "gardens", Layout.point(world.PLACES.huerto))
	expect("Me alegra ver las plantas." in thoughts(scene,"cesar"), "garden thoughts require the actual garden area")
	place(scene, "cesar", "homes", Layout.point(world.PLACES.huerto))
	expect("Me alegra ver las plantas." not in thoughts(scene,"cesar"), "garden coordinates elsewhere do not fabricate nearby crops")
	world.minute = 180
	var weather_all := true
	for area: String in Layout.outdoor_ids():
		place(scene, "cesar", area, Vector2(280,196))
		weather_all = weather_all and "Qué tranquila la noche." in thoughts(scene,"cesar")
	expect(weather_all, "outdoor weather thoughts remain available in all registered streets")
	world.minute = 600
	park_neighbors(scene)
	place(scene,"player","player",Layout.point(Layout.data().home_rest))
	place(scene,"cesar","homes",Vector2(280,196))
	place(scene,"lupita","workshops",Vector2(300,196))
	scene.encounters = Encounters.new(scene)
	scene.encounters.advance(2.1)
	expect(scene.encounters._active.is_empty(), "autonomous greetings do not cross between blocks")
	place(scene,"lupita","homes",Vector2(300,196))
	scene.encounters.advance(0.3)
	expect(not scene.encounters._active.is_empty() and "cesar" in world.conversation_holds and "lupita" in world.conversation_holds, "neighbors can greet and reserve both participants outside the original plaza")
	var memories_before: int = world.get_resident("cesar").memories.size()
	place(scene,"lupita","workshops",Vector2(300,196))
	scene.encounters.advance(0.3)
	expect(scene.encounters._active.is_empty() and "cesar" not in world.conversation_holds and "lupita" not in world.conversation_holds, "changing areas cancels an interrupted greeting and releases both holds")
	expect(world.get_resident("cesar").memories.size() == memories_before, "an interrupted cross-area greeting is not recorded as a completed exchange")
	park_neighbors(scene)

func keyboard_checks(scene: MainProbe) -> void:
	park_neighbors(scene)
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	scene.paused = false
	var player: Dictionary = scene.colony.get_resident("player")
	# Traversal fixture explicitly includes the new forest. Growth tests unlock it through its real costs.
	if "forest" not in scene.colony.settlement.state.areas:
		scene.colony.settlement.state.areas.append("forest")
		scene.colony.settlement.state.discoveries.append("survey_forest")
		scene.colony.settlement.state.projects.forest_path = {"status":"completed","progress":30.0}
	for area: String in Layout.outdoor_ids():
		for edge: Dictionary in Layout.exits(area):
			place(scene,"player",area,edge.at - edge.direction * 24.0)
			scene.update_room()
			var legal := true
			for _frame in range(120):
				scene.move_player_keyboard(edge.direction,1.0/60.0)
				samples += 1
				legal = legal and Navigation.is_walkable(scene.position_of(player),player.room)
				if player.room != area: break
			expect(player.room == edge.to and scene.current_room == edge.to and legal, "keyboard crosses " + str(edge.id) + " through its physical opening")
			var reached: String = player.room
			for _frame in range(4): scene.update_room()
			scene.move_player_keyboard(edge.direction,1.0/60.0)
			expect(player.room == reached and Navigation.is_walkable(scene.position_of(player),player.room), "arrival at " + str(edge.id) + " does not bounce or require releasing direction")
	var blocked: Dictionary = Layout.exits("homes").front()
	place(scene,"player","homes",blocked.at - blocked.direction * 3.0)
	place(scene,"cesar",blocked.to,blocked.spawn)
	scene.update_room()
	var occupied_position: Array = scene.colony.get_resident("cesar").pos.duplicate()
	for _frame in range(12): scene.move_player_keyboard(blocked.direction,1.0/60.0)
	expect(player.room == "homes" and scene.colony.get_resident("cesar").pos == occupied_position, "an occupied destination opening blocks crossing without displacing its occupant")
	place(scene,"cesar","cesar",Layout.point(Layout.data().home_rest))
	for _frame in range(20):
		scene.move_player_keyboard(blocked.direction,1.0/60.0)
		if player.room != "homes": break
	expect(player.room == blocked.to, "held movement can continue once the destination opening clears")
	park_neighbors(scene)

func capture_area(scene: MainProbe, viewport: SubViewport, area: String) -> void:
	if not capture_enabled: return
	scene.encounters.cancel()
	for person: Dictionary in scene.colony.residents:
		var spawn: Dictionary = Layout.resident_spawn(person.id)
		place(scene, person.id, spawn.room, spawn.position)
	place(scene,"player",area,Vector2(280,196))
	scene.colony.minute = 660
	scene.update_room()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	scene.interaction_hover.clear()
	scene.refresh_status()
	scene.update_camera(0.0,true)
	scene.actors.queue_redraw()
	await settle()
	await RenderingServer.frame_post_draw
	var picture: Image = viewport.get_texture().get_image()
	var path := directory.path_join("%dx%d-%s.png" % [viewport.size.x,viewport.size.y,area])
	var saved: bool = picture != null and not picture.is_empty() and picture.save_png(path) == OK
	expect(saved, "capture exports the actual " + area + " scene")
	if saved:
		captures += 1
		print("CAPTURE: " + path)

func manual_exit_checks(scene: MainProbe) -> void:
	park_neighbors(scene)
	var player: Dictionary = scene.colony.get_resident("player")
	var outside: String = Layout.home_area("player")
	var door: Vector2 = Navigation.door_positions().player
	place(scene,"player","player",Layout.point(Layout.data().entry))
	place(scene,"cesar",outside,door)
	scene.update_room()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	await settle()
	var before: Array = player.pos.duplicate()
	scene.exit_button.pressed.emit()
	expect(scene.pending_exit and player.room == "player" and player.pos == before, "the real house Exit button starts walking without changing rooms immediately")
	var legal := true
	for _frame in range(90):
		scene.move_resident(player,1.0/30.0)
		scene.resolve_player_arrival()
		scene.update_room()
		samples += 1
		legal = legal and Navigation.is_walkable(scene.position_of(player),player.room)
	expect(player.room == "player" and scene.pending_exit and scene.position_of(player).distance_to(Layout.point(Layout.data().exit)) < 0.1 and legal, "a blocked manual house exit reaches the threshold and retains its pending intention")
	expect(scene.colony.get_resident("cesar").room == outside and scene.position_of(scene.colony.get_resident("cesar")) == door, "waiting at a house exit never displaces the resident outside")
	place(scene,"cesar","cesar",Layout.point(Layout.data().home_rest))
	for _frame in range(20):
		scene.move_resident(player,1.0/30.0)
		scene.resolve_player_arrival()
		scene.update_room()
		samples += 1
		if player.room == outside: break
	expect(player.room == outside and scene.current_room == outside and not scene.pending_exit and scene.position_of(player) == door, "clearing the obstruction completes the same Exit command without another click")

func typing_map_checks(scene: MainProbe) -> void:
	park_neighbors(scene)
	place(scene,"player","homes",Vector2(280,196))
	place(scene,"mateo","homes",Vector2(300,196))
	scene.update_room()
	expect(scene.start_player_conversation("mateo"), "map-shortcut fixture opens a real nearby chat without submitting dialogue")
	if not is_instance_valid(scene.chat_input): return
	scene.chat_input.text = "Hola, "
	scene.chat_input.text_changed.emit()
	scene.chat_input.set_caret_column(scene.chat_input.text.length())
	scene.chat_input.grab_focus()
	await settle()
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.physical_keycode = KEY_M
	key.unicode = 109
	key.pressed = true
	scene.get_viewport().push_input(key)
	await settle()
	key.pressed = false
	scene.get_viewport().push_input(key)
	expect(not is_instance_valid(scene.help_panel) and scene.chat_input.has_focus() and scene.chat_input.text == "Hola, m", "typing M belongs to the focused chat draft and cannot open the neighborhood map")
	expect(scene.chat_partner_id == "mateo" and scene.provider_calls == 0 and scene.dialogue_job.is_empty(), "the M shortcut neither ends the chat nor submits its unfinished draft")
	scene.end_player_conversation()
	scene.hide_inspector()
	scene.get_viewport().gui_release_focus()
	park_neighbors(scene)

func follow_until(scene: MainProbe, mentor_id: String, door_home: String = "") -> Dictionary:
	var player: Dictionary = scene.colony.get_resident("player")
	var mentor: Dictionary = scene.colony.get_resident(mentor_id)
	var legal := true
	var rooms: Array[String] = [player.room]
	for frame in range(1800):
		if frame % 15 == 0: scene.follow_mentor()
		scene.move_resident(player,1.0/30.0)
		scene.resolve_player_arrival()
		scene.update_room()
		samples += 1
		legal = legal and Navigation.is_walkable(scene.position_of(player),player.room)
		if player.room != rooms.back(): rooms.append(player.room)
		if not door_home.is_empty() and is_instance_valid(scene.door_panel) and scene.door_panel.get_meta("home_id","") == door_home:
			return {"arrived":player.room == Layout.home_area(door_home) and scene.position_of(player).distance_to(Navigation.door_positions()[door_home]) < 5.0,"legal":legal,"rooms":rooms}
		if door_home.is_empty() and scene.pending_mentor.is_empty():
			return {"arrived":player.room == mentor.room and scene.position_of(player).distance_to(scene.position_of(mentor)) < 20.0,"legal":legal,"rooms":rooms}
	return {"arrived":false,"legal":legal,"rooms":rooms}

func mentor_follow_checks(scene: MainProbe) -> void:
	park_neighbors(scene)
	var player: Dictionary = scene.colony.get_resident("player")
	var door: Vector2 = Navigation.door_positions().player
	place(scene,"player",Layout.home_area("player"),door)
	place(scene,"mateo","player",Layout.point(Layout.data().entry))
	scene.update_room()
	scene.walk_to_mentor("mateo")
	scene.resolve_player_arrival()
	expect(is_instance_valid(scene.door_panel) and scene.door_panel.get_meta("home_id","") == "player", "following a mentor indoors first reaches the correct physical door")
	# The mentor moves while the player is deciding at that door.
	place(scene,"mateo","workshops",Vector2(280,196))
	var before: Array = player.pos.duplicate()
	scene.follow_mentor()
	expect(not is_instance_valid(scene.door_panel) and scene.pending_home.is_empty() and scene.pending_mentor == "mateo" and player.pos == before, "a mentor changing to another street dismisses the stale door and redirects without teleporting")
	var route: Dictionary = follow_until(scene,"mateo")
	expect(route.arrived and route.legal and route.rooms == ["homes","street","workshops"], "the redirected follower physically reaches the mentor across the intervening plaza")
	# A different house is a different permission boundary, not the old modal.
	place(scene,"player",Layout.home_area("player"),door)
	place(scene,"mateo","player",Layout.point(Layout.data().entry))
	scene.update_room()
	scene.walk_to_mentor("mateo")
	scene.resolve_player_arrival()
	place(scene,"mateo","mateo",Layout.point(Layout.data().home_rest))
	scene.follow_mentor()
	expect(not is_instance_valid(scene.door_panel) and scene.pending_home == "mateo" and scene.pending_mentor == "mateo", "a mentor in a different house replaces the obsolete door request with the correct home")
	route = follow_until(scene,"mateo","mateo")
	expect(route.arrived and route.legal and route.rooms == ["homes","street","workshops"], "following to another house reaches its actual door through connected streets")
	var waiting: Array = player.pos.duplicate()
	for _attempt in range(3): scene.follow_mentor()
	expect(is_instance_valid(scene.door_panel) and scene.door_panel.get_meta("home_id","") == "mateo" and player.room == "workshops" and player.pos == waiting, "the matching door remains available and following does not bypass entry consent")
	scene.close_door_panel()
	scene.take_control()
	place(scene,"player","player",Layout.point(Layout.data().entry))
	place(scene,"mateo","gardens",Vector2(280,196))
	scene.update_room()
	scene.walk_to_mentor("mateo")
	expect(scene.pending_exit and scene.pending_mentor == "mateo" and player.room == "player", "following from indoors first prepares the existing house exit")
	route = follow_until(scene,"mateo")
	expect(route.arrived and route.legal and route.rooms == ["player","homes","street","gardens"], "the follower leaves home and physically reaches the mentor in the garden area")
	park_neighbors(scene)
	scene.hide_inspector()
	scene.overlay.dismiss_toast()

func map_checks(scene: MainProbe, viewport: SubViewport) -> void:
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	var before: String = JSON.stringify({"people":scene.colony.residents,"minute":scene.colony.minute,"progression":scene.colony.progression_state()})
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_M
	key.physical_keycode = KEY_M
	scene._input(key)
	await settle()
	expect(is_instance_valid(scene.help_panel) and scene.help_panel.has_meta("neighborhood_map") and scene.help_panel.is_visible_in_tree(), "M opens the neighborhood map at " + str(viewport.size))
	expect(scene.keyboard_blocked() and not scene.move_player_keyboard(Vector2.RIGHT,0.1), "reading the map keeps movement beneath its panel blocked")
	if capture_enabled and is_instance_valid(scene.help_panel):
		await RenderingServer.frame_post_draw
		var path := directory.path_join("%dx%d-map.png" % [viewport.size.x,viewport.size.y])
		var picture: Image = viewport.get_texture().get_image()
		var saved: bool = picture != null and not picture.is_empty() and picture.save_png(path) == OK
		expect(saved,"capture exports the neighborhood map at " + str(viewport.size))
		if saved:
			captures += 1
			print("CAPTURE: " + path)
	scene._input(key)
	await settle()
	expect(not is_instance_valid(scene.help_panel), "M closes the same map without opening another panel")
	scene._input(key)
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	scene._input(key)
	await settle()
	expect(not is_instance_valid(scene.help_panel) and not scene.keyboard_blocked(), "Escape closes the map and restores movement")
	expect(JSON.stringify({"people":scene.colony.residents,"minute":scene.colony.minute,"progression":scene.colony.progression_state()}) == before, "map navigation changes no positions, clock, relationship or progress")

func transition_checks(scene: MainProbe) -> void:
	var before: String = JSON.stringify({"people":scene.colony.residents,"minute":scene.colony.minute,"progression":scene.colony.progression_state()})
	# Only the presentation helper leaves preview mode; processing and providers
	# stay disabled, and no save/load entry point runs in this short interval.
	scene.preview_mode = false
	scene.neighborhood.changed_area()
	var veil: ColorRect = scene.neighborhood.veil
	expect(is_instance_valid(veil) and veil.visible and veil.mouse_filter == Control.MOUSE_FILTER_IGNORE and veil.size == scene.layout_size(), "the real area transition covers the viewport without intercepting controls")
	if is_instance_valid(veil):
		expect(veil.get_parent() == scene and veil.get_index() > scene.world_clip.get_index() and veil.get_index() < scene.hud.stats_panel.get_index() and veil.get_index() < scene.hud.controls_panel.get_index() and veil.get_index() < scene.hud.dock_panel.get_index(), "the transition is drawn above the world but below every HUD group")
	await create_timer(0.3).timeout
	expect(is_instance_valid(veil) and not veil.visible and is_zero_approx(veil.modulate.a), "the area fade completes and hides within three tenths of a second")
	scene.preview_mode = true
	expect(JSON.stringify({"people":scene.colony.residents,"minute":scene.colony.minute,"progression":scene.colony.progression_state()}) == before and not scene.is_processing() and not scene.save_allowed and scene.service_token.is_empty() and scene.provider_calls == 0, "the real presentation tween changes no simulation, save or provider state")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ui-test" not in args:
		push_error("Requires -- --ui-test; real progress must remain untouched.")
		quit(1)
		return
	capture_enabled = "--capture" in args
	if capture_enabled and DisplayServer.get_name() == "headless":
		push_error("PNG captures require a rendering display.")
		quit(1)
		return
	directory = ProjectSettings.globalize_path("res://../artifacts/multi-area")
	if capture_enabled: DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,432)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = save_path
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.use_jev = false
	scene.save_allowed = false
	scene.service_token = ""
	scene.service_url = ""
	scene.colony._social._willingness_roll = func(): return 1.0
	scene.colony.minute = 600
	scene.hide_inspector()
	park_neighbors(scene)
	await settle()
	expect(scene.current_room == "homes" and Layout.outdoor_ids().size() == 6, "a new isolated game begins in the connected residential street")
	for area: String in ["street","gardens","atelier","workshops","street","homes"]:
		walk(scene,area,Vector2(280,196))
	expect(crossings >= 6, "the round trip actually crosses six physical block connections")
	context_checks(scene)
	keyboard_checks(scene)
	await manual_exit_checks(scene)
	await typing_map_checks(scene)
	mentor_follow_checks(scene)
	for area: String in Layout.outdoor_ids(): await capture_area(scene,viewport,area)
	await map_checks(scene,viewport)
	if capture_enabled:
		viewport.size = Vector2i(960,540)
		await settle()
		await capture_area(scene,viewport,"street")
		await map_checks(scene,viewport)
	await transition_checks(scene)
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not FileAccess.file_exists(save_path), "walking, perception and visual review create no provider request or real save")
	scene.encounters.cancel()
	scene.free()
	viewport.free()
	await process_frame
	print("MULTI AREA: %d/%d checks passed; %d movement samples; %d crossings; %d captures" % [checks-failures.size(),checks,samples,crossings,captures])
	quit(0 if failures.is_empty() else 1)
