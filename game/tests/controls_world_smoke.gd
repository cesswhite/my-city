extends SceneTree
## Real input actions and the live scene loop, isolated from saves and providers.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const MOVEMENT_ACTIONS = ["city_left", "city_right", "city_up", "city_down"]

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func release_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)

func click_world(scene: Node, position: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = scene.world_to_screen(position)
	scene._gui_input(click)

func reset_player(scene: Node, position: Vector2 = Vector2(280, 180)) -> void:
	release_actions()
	scene.take_control()
	scene.close_door_panel()
	scene.learning.close()
	scene.get_viewport().gui_release_focus()
	scene.controls_active = true
	scene.paused = false
	scene.elapsed = 0.0
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = "street"
	player.pos = [position.x, position.y]
	player.target = player.pos.duplicate()
	scene.update_room()

func advance(scene: Node, frames: int) -> void:
	for _frame in range(frames):
		scene._process(0.1)

func has_physical_binding(action: String, code: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == code:
			return true
	return false

func autonomous_trip(scene: Node, destination_room: String, destination: Vector2, shared_place: bool = false) -> Dictionary:
	var player: Dictionary = scene.colony.get_resident("player")
	var valid_steps := true
	var manual_intents_absent := true
	var transitions: int = 0
	for _frame in range(1800):
		var previous_room: String = player.room
		var previous: Vector2 = scene.position_of(player)
		scene._process(0.1)
		var position: Vector2 = scene.position_of(player)
		valid_steps = valid_steps and Navigation.is_walkable(position, player.room)
		manual_intents_absent = manual_intents_absent and scene.pending_home.is_empty() and not scene.pending_exit
		if previous_room == player.room:
			valid_steps = valid_steps and previous.distance_to(position) <= 4.81
		else:
			transitions += 1
			if previous_room == "street":
				valid_steps = valid_steps and previous.distance_to(Navigation.door_positions().player) <= 4.81 and position == Layout.point(Layout.data().entry)
			else:
				valid_steps = valid_steps and previous.distance_to(Layout.point(Layout.data().exit)) <= 4.81 and position == Navigation.door_positions().player
		var arrived: bool = position.distance_to(destination) < 1.0
		if shared_place:
			arrived = position.distance_to(destination) < scene.colony.MAX_DISTANCE and position.distance_to(Layout.point(player.target)) < 1.0
		if player.room == destination_room and arrived:
			return {"arrived": true, "valid_steps": valid_steps, "manual_intents_absent": manual_intents_absent, "transitions": transitions}
	return {"arrived": false, "valid_steps": valid_steps, "manual_intents_absent": manual_intents_absent, "transitions": transitions}

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test so this fixture cannot load or save user progress.")
		quit(1)
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	var player: Dictionary = scene.colony.get_resident("player")
	expect(scene.preview_mode and scene.paused and scene.colony.minute == 480, "fixture starts isolated without loading or saving progress")
	var bindings := {"city_left": [KEY_A, KEY_LEFT], "city_right": [KEY_D, KEY_RIGHT], "city_up": [KEY_W, KEY_UP], "city_down": [KEY_S, KEY_DOWN]}
	for action in bindings:
		expect(has_physical_binding(action, bindings[action][0]) and has_physical_binding(action, bindings[action][1]), action + " has both WASD and arrow physical bindings")
	var binding_count: int = InputMap.action_get_events("city_right").size()
	scene.configure_keyboard()
	expect(InputMap.action_get_events("city_right").size() == binding_count, "keyboard configuration is idempotent")

	reset_player(scene)
	var before: Vector2 = scene.position_of(player)
	Input.action_press("city_right")
	scene._process(0.1)
	expect(scene.position_of(player).is_equal_approx(before + Vector2(4.8, 0)) and scene.keyboard_walking, "held Input action moves through the live loop at forty-eight pixels per second")
	Input.action_press("city_down")
	before = scene.position_of(player)
	scene._process(0.1)
	var diagonal: Vector2 = scene.position_of(player) - before
	expect(absf(diagonal.length() - 4.8) < 0.001 and absf(diagonal.x - diagonal.y) < 0.001, "diagonal keyboard input preserves cardinal movement speed")
	release_actions()
	Input.action_press("city_right")
	before = scene.position_of(player)
	scene._process(10.0)
	expect(is_equal_approx(scene.position_of(player).distance_to(before), 4.8), "a frame spike is clamped before keyboard movement")
	scene.cycle_time_speed()
	scene.cycle_time_speed()
	before = scene.position_of(player)
	scene._process(0.1)
	expect(scene.time_speed == 4.0 and is_equal_approx(scene.position_of(player).distance_to(before), 4.8), "fast world time does not accelerate manual keyboard walking")
	release_actions()
	scene._process(0.1)
	expect(not scene.keyboard_walking and player.pos == player.target, "releasing movement stops the animation and leaves no walking target")
	reset_player(scene, Vector2(100, 280))
	Input.action_press("city_right")
	scene._process(0.017)
	release_actions()
	var fractional_stop: Vector2 = scene.position_of(player)
	var always_stationary := true
	var maximum_drift: float = 0.0
	for _frame in range(30):
		scene._process(0.017)
		var drift: float = scene.position_of(player).distance_to(fractional_stop)
		maximum_drift = maxf(maximum_drift, drift)
		always_stationary = always_stationary and drift < 0.001
	expect(scene.position_of(player).is_equal_approx(fractional_stop), "fractional keyboard stop preserves its final position")
	expect(always_stationary, "fractional keyboard stop remains still in every released frame (maximum drift %.3f px)" % maximum_drift)
	var resumed_route: Array[Vector2] = Navigation.route(fractional_stop, Vector2(116, 280))
	var route_is_walkable := not resumed_route.is_empty()
	for point in resumed_route:
		route_is_walkable = route_is_walkable and Navigation.is_walkable(point)
	expect(route_is_walkable and resumed_route[-1] == Vector2(116, 280), "a subsequent click route accepts the exact fractional keyboard position")

	# A click first creates a real path; a held key then takes over that path.
	reset_player(scene)
	click_world(scene, Vector2(316, 180))
	before = scene.position_of(player)
	scene._process(0.1)
	expect(is_equal_approx(scene.position_of(player).distance_to(before), 4.8), "click walking uses the same forty-eight pixel speed as the keyboard")
	expect(scene.paths.has("player") and player.target != player.pos, "world click produces an active walking route")
	Input.action_press("city_down")
	scene._process(0.1)
	expect(not scene.paths.has("player") and player.target == player.pos, "held keyboard movement cancels the previous click route")
	reset_player(scene)
	scene.toggle_autonomy()
	player.target = [316.0,180.0]
	scene.paths.erase("player")
	before = scene.position_of(player)
	scene._process(0.1)
	expect(scene.colony.player_autonomy and is_equal_approx(scene.position_of(player).distance_to(before), 4.8), "autonomous player walks at the same speed as manual and click movement")
	var npc: Dictionary = scene.colony.get_resident("mateo")
	var previous_npc: Dictionary = npc.duplicate(true)
	npc.room = "street"
	npc.pos = [280.0,180.0]
	npc.target = [316.0,180.0]
	scene.paths.erase(npc.id)
	scene.move_resident(npc, 0.1)
	expect(is_equal_approx(scene.position_of(npc).distance_to(Vector2(280,180)), 3.0), "neighbor walking remains thirty pixels per second")
	npc.merge(previous_npc, true)
	scene.paths.erase(npc.id)
	reset_player(scene)
	scene.toggle_autonomy()
	var auto_epoch: int = scene.control_epoch
	var neighbor: Dictionary = scene.colony.get_resident("mateo")
	click_world(scene, scene.position_of(neighbor) - Vector2(0, 10))
	expect(scene.selected_id == "mateo" and scene.colony.player_autonomy and scene.control_epoch == auto_epoch, "inspecting a neighbor leaves autonomous life running")
	scene.cycle_time_speed()
	scene.pending_home = "player"
	scene.pending_exit = true
	scene.pending_shop = true
	scene.pending_mentor = "mateo"
	scene.pending_item = {"room": "player", "stand_at": Layout.stand_at("bicycle")}
	Input.action_press("city_down")
	scene._process(0.1)
	expect(not scene.colony.player_autonomy and scene.control_epoch > auto_epoch and scene.time_speed == 1.0, "keyboard input reclaims control and restores normal world speed")
	expect(scene.pending_home.is_empty() and not scene.pending_exit and not scene.pending_shop and scene.pending_mentor.is_empty() and scene.pending_item.is_empty() and not scene.paths.has("player"), "taking control clears every pending manual intention before arrival handling")

	reset_player(scene)
	scene.open_inspector("lupita", "hablar")
	scene.chat_input.text = "WASD permanece dentro del borrador."
	scene.chat_input.grab_focus()
	await process_frame
	before = scene.position_of(player)
	Input.action_press("city_right")
	scene._process(0.1)
	expect(scene.chat_input.has_focus() and scene.keyboard_blocked() and scene.position_of(player) == before, "focused TextEdit blocks character movement")
	expect(scene.chat_input.text == "WASD permanece dentro del borrador." and scene.dialogue_job.is_empty(), "typing focus preserves the draft without starting a conversation")
	release_actions()
	scene.get_viewport().gui_release_focus()
	scene.learning.show_journal()
	Input.action_press("city_right")
	scene._process(0.1)
	expect(scene.keyboard_blocked() and scene.position_of(player) == before, "journal modal blocks held movement")
	scene.learning.close()
	scene.show_door_panel("player")
	scene._process(0.1)
	expect(scene.keyboard_blocked() and scene.position_of(player) == before, "door modal blocks held movement")
	scene.close_door_panel()
	scene._notification(scene.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(not scene.controls_active and not Input.is_action_pressed("city_right"), "window focus loss clears held input")
	Input.action_press("city_right")
	scene._process(0.1)
	expect(scene.keyboard_blocked() and scene.position_of(player) == before, "background window ignores newly pressed movement")
	release_actions()
	scene._notification(scene.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	Input.action_press("city_right")
	scene._process(0.1)
	expect(scene.controls_active and scene.position_of(player).distance_to(before) > 0, "regaining focus allows a fresh movement press")

	reset_player(scene)
	before = scene.position_of(player)
	var minute_before: int = scene.colony.minute
	scene.toggle_pause()
	Input.action_press("city_right")
	advance(scene, 45)
	expect(scene.paused and scene.position_of(player) == before and scene.colony.minute == minute_before and scene.elapsed == 0.0, "pause freezes keyboard movement and the world clock")
	release_actions()
	scene.toggle_pause()
	for multiplier in [1, 2, 4]:
		scene.elapsed = 0.0
		minute_before = scene.colony.minute
		expect(scene.time_speed == float(multiplier), "speed control selects %d×" % multiplier)
		advance(scene, 41)
		expect(scene.colony.minute - minute_before == 5 * multiplier, "%d× advances the actual four-second simulation clock proportionally" % multiplier)
		scene.cycle_time_speed()
	expect(scene.time_speed == 1.0, "speed control cycles back to normal")

	# Autonomy uses the same paths and portal arrival code as the other residents.
	reset_player(scene)
	scene.colony.minute = 1320
	scene.toggle_autonomy()
	minute_before = scene.colony.minute
	var trip: Dictionary = autonomous_trip(scene, "player", Layout.stand_at("bed", "player"))
	expect(trip.arrived and scene.current_room == "player", "autonomous player walks home and reaches the physical bedside")
	expect(trip.valid_steps and trip.transitions == 1, "home entry follows walkable segments and transitions only at the real doorway")
	expect(trip.manual_intents_absent and not is_instance_valid(scene.door_panel), "autonomous entry requires no pending_home or manual door modal")
	expect(scene.colony.minute > minute_before, "the clock remains active throughout autonomous travel")
	scene.colony.minute = 1440 + 415
	scene.colony.tick(false)
	trip = autonomous_trip(scene, "street", Vector2(110, 178), true)
	expect(trip.arrived and scene.current_room == "street", "morning routine walks out of the house and reaches the cafe")
	expect(trip.valid_steps and trip.transitions == 1 and trip.manual_intents_absent, "autonomous exit reaches the interior doorway without a manual exit intention")

	# Never request a provider. Inject only completed callbacks from an older epoch.
	var old_epoch: int = scene.control_epoch
	scene.deciding_id = "player"
	scene.deciding_epoch = old_epoch
	scene.decision_pending = true
	scene.take_control()
	expect(not scene.decision_pending and scene.control_epoch > old_epoch, "taking control cancels an outstanding player decision")
	scene.toggle_autonomy()
	var intended_target: Array = player.target.duplicate()
	scene.use_jev = true
	scene.decision_pending = true
	scene.deciding_epoch = old_epoch
	scene._decision_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"action":"huerto","source":"fixture"}'.to_utf8_buffer())
	expect(player.target == intended_target and scene.use_jev and not scene.decision_pending, "old successful player decision is rejected even after autonomy is re-enabled")
	scene.decision_pending = true
	scene.deciding_epoch = old_epoch
	scene._decision_received(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), '{}'.to_utf8_buffer())
	expect(scene.use_jev and player.target == intended_target, "old failed player decision cannot disable the active provider")
	scene.use_jev = false
	scene.take_control()
	expect(scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not scene.dialogue_request.busy and not scene.decision_pending, "fixture finishes without provider requests or pending work")
	release_actions()
	scene.free()
	await process_frame
	print("CONTROLS WORLD: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
