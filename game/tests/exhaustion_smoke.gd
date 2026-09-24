extends SceneTree
## Real scene and clock; no provider, normal save or wall-clock sleeping.
const Layout = preload("res://scripts/world_layout.gd")
const Seats = preload("res://scripts/seating.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void:
		provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void:
		provider_calls += 1
		dialogue_request._reset_state()
		dialogue_request.busy = true
		dialogue_request.set_process(false)

var checks := 0
var failures: Array[String] = []
var save_path := "user://test_exhaustion_%d.json" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func fixture(room: String = "street") -> MainProbe:
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = ""
	scene.service_url = ""
	scene.use_jev = false
	scene.controls_active = true
	scene.paused = false
	scene.elapsed = 0.0
	scene.colony.minute = 600
	scene.colony.save_path = save_path
	scene.colony._social._willingness_roll = func(): return 1.0
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = scene.colony.HOME_REST.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	var player: Dictionary = scene.colony.get_resident("player")
	var origin: Vector2 = Vector2(236,210) if room == "street" else Layout.stand_at("bed", "player")
	player.room = room
	player.pos = [origin.x,origin.y]
	player.target = player.pos.duplicate()
	player.energy = 1.0
	scene.paths.clear()
	scene.update_room()
	return scene

func collapse(scene) -> void:
	scene.colony.get_resident("player").energy = 0.0
	scene._process(0.0)

func press(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	root.push_input(key)
	key = key.duplicate()
	key.pressed = false
	root.push_input(key)

func clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))

func position(scene, id: String, at: Vector2, room: String = "street") -> void:
	var resident: Dictionary = scene.colony.get_resident(id)
	resident.room = room
	resident.pos = [at.x,at.y]
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""
	scene.paths.erase(id)

func earn_bicycle(scene) -> bool:
	var world = scene.colony
	position(scene,"player",Layout.point(world.PLACES.taller))
	position(scene,"mateo",Layout.point(world.PLACES.taller))
	if not world.start_apprenticeship("bicicleta_de_mateo").ok: return false
	position(scene,"player",Layout.stand_at("shop","street"))
	if not world.buy_item("aceite").ok: return false
	position(scene,"player",Layout.point(world.PLACES.taller))
	if not world.deliver_apprenticeship("bicicleta_de_mateo").ok: return false
	position(scene,"player",Layout.stand_at("bicycle","player"),"player")
	for _step in range(4):
		if not world.perform_procedure("reparar_bicicleta").ok: return false
	return world.can_ride_bicycle()

func pattern(frames: Array[float], speed: float, room: String, label: String) -> void:
	var scene := fixture(room)
	scene.time_speed = speed
	var player: Dictionary = scene.colony.get_resident("player")
	var origin: Array = player.pos.duplicate()
	var minute: int = scene.colony.minute
	collapse(scene)
	expect(scene.colony.is_exhausted() and scene.colony.is_sleeping("player") and scene.colony.player_energy() == 0.0, label + ": zero energy collapses immediately without granting energy")
	var elapsed := 0.0
	var index := 0
	var stayed := true
	var timing := true
	while elapsed < 8.0 - 0.00000001:
		var delta: float = minf(frames[index % frames.size()], 8.0 - elapsed)
		scene._process(delta)
		elapsed += delta
		index += 1
		stayed = stayed and player.pos == origin and player.room == room
		if elapsed < 8.0 - 0.000001:
			timing = timing and scene.colony.is_exhausted() and scene.colony.player_energy() == 0.0
	expect(stayed, label + ": every sample keeps the original position and room")
	expect(timing and not scene.colony.is_exhausted() and not scene.colony.is_sleeping("player"), label + ": wakes at eight active real seconds, never earlier")
	expect(scene.colony.player_energy() == 5.0, label + ": waking restores exactly five percent energy")
	expect(scene.colony.minute == minute + 10, label + ": the world advances only ten normal game minutes, regardless of speed")
	expect(scene.provider_calls == 0 and not scene.colony.player_autonomy, label + ": collapse starts no provider work or autonomous player route")
	scene.free()

func check_controls() -> void:
	var scene := fixture("player")
	var player: Dictionary = scene.colony.get_resident("player")
	var origin: Array = player.pos.duplicate()
	collapse(scene)
	var interval: Dictionary = player.sleep.duplicate(true)
	expect(not scene.colony.wake_resident("player"), "the normal wake API cannot interrupt forced rest")
	for code: Key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_LEFT,KEY_DOWN,KEY_RIGHT,KEY_E]: press(code)
	scene.move_player_keyboard(Vector2.RIGHT, 0.1)
	scene.interact_nearby()
	scene.toggle_autonomy()
	scene.toggle_bicycle()
	scene.sleep_ui.wake()
	scene.sleep_ui.show_choices()
	var bed_started: bool = scene.sleep_ui.start(480)
	expect(scene.colony.is_exhausted() and player.sleep == interval and not bed_started, "keyboard, E, autonomy, bicycle and bed controls neither wake nor replace forced rest")
	expect(player.pos == origin and player.room == "player" and not scene.colony.player_autonomy and not scene.riding_bicycle, "blocked controls cannot move or activate a travel mode")
	expect(not is_instance_valid(scene.sleep_ui.panel), "forced rest cannot open a bed duration modal")
	var mentor: Dictionary = scene.colony.get_resident("mateo")
	mentor.room = player.room
	mentor.pos = [float(player.pos[0])+18,float(player.pos[1])]
	mentor.target = mentor.pos.duplicate()
	scene.selected_id = "mateo"
	expect(not scene.start_player_conversation("mateo"), "a collapsed player cannot reserve a nearby conversation")
	scene.send_chat_text("Hola, Mateo.")
	expect(scene.chat_partner_id.is_empty() and scene.dialogue_job.is_empty() and scene.provider_calls == 0, "sending from a stale chat control cannot start dialogue while exhausted")
	scene.free()
	# Exercise the positive prerequisite: the bicycle is earned and usable here.
	scene = fixture()
	expect(earn_bicycle(scene), "bicycle fixture earns the vehicle through purchases, delivery and every verified repair step")
	position(scene,"player",Vector2(236,210))
	scene.update_room()
	scene.toggle_bicycle()
	expect(scene.riding_bicycle, "an awake player can use the earned bicycle before collapse")
	origin = scene.colony.get_resident("player").pos.duplicate()
	collapse(scene)
	scene.toggle_bicycle()
	expect(not scene.riding_bicycle and scene.colony.can_ride_bicycle() and scene.colony.get_resident("player").pos == origin, "collapse dismounts in place and blocks remounting without removing the earned bicycle")
	scene.free()

func check_cancellation() -> void:
	var scene := fixture()
	var player: Dictionary = scene.colony.get_resident("player")
	var mentor: Dictionary = scene.colony.get_resident("mateo")
	mentor.room = "street"
	mentor.pos = [260.0,210.0]
	mentor.target = [296.0,210.0]
	mentor.travel_intent = "taller"
	scene.selected_id = "mateo"
	scene.service_token = "fixture-never-sent"
	scene.send_chat_text("Un mensaje que aún espera respuesta.")
	expect(scene.chat_partner_id == "mateo" and scene.dialogue_request.busy, "cancellation fixture starts a real reserved pending chat")
	var memories: int = player.memories.size()
	var calls: int = scene.provider_calls
	scene.pending_mentor = "mateo"
	scene.player_chat.approach_id = "mateo"
	scene.pending_shop = true
	scene.pending_home = "lupita"
	scene.pending_exit = true
	var seat: Dictionary = Seats.seats()[0]
	scene.seating.pending_id = str(seat.id)
	collapse(scene)
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty() and scene.dialogue_job.is_empty() and not scene.dialogue_request.busy, "collapse cancels transport and releases both conversation reservations")
	expect(scene.pending_mentor.is_empty() and scene.player_chat.approach_id.is_empty() and not scene.pending_shop and scene.pending_home.is_empty() and not scene.pending_exit and scene.seating.pending_id.is_empty(), "collapse cancels following, shopping, portals and the pending seat")
	scene._dialogue_completed({"text":"Respuesta tardía", "source":"openai"})
	expect(player.memories.size() == memories and scene.provider_calls == calls, "late completion after collapse creates neither memory nor new provider work")
	scene.free()
	# A real already-occupied seat is also abandoned without moving the feet.
	scene = fixture()
	player = scene.colony.get_resident("player")
	player.pos = [seat.stand_at.x,seat.stand_at.y]
	player.target = player.pos.duplicate()
	expect(scene.seating.request(str(seat.id)) and scene.seating.is_seated(), "seated collapse fixture occupies an actual accessible seat")
	var origin: Array = player.pos.duplicate()
	collapse(scene)
	expect(not scene.seating.is_seated() and player.pos == origin and scene.colony.is_exhausted(), "collapse clears seated posture without teleporting the player")
	scene.free()

func check_pause_and_menu() -> void:
	var scene := fixture()
	collapse(scene)
	scene._process(2.25)
	var player: Dictionary = scene.colony.get_resident("player")
	var interval: Dictionary = player.sleep.duplicate(true)
	var minute: int = scene.colony.minute
	scene.toggle_pause()
	scene._process(40.0)
	expect(player.sleep == interval and scene.colony.minute == minute and scene.colony.player_energy() == 0.0, "pause consumes no exhaustion time or game time")
	scene.toggle_pause()
	scene.suspend_for_menu()
	scene._process(40.0)
	expect(player.sleep == interval and scene.colony.minute == minute, "the menu freezes and preserves a partially elapsed collapse")
	scene.resume_from_menu()
	scene.set_process(false)
	scene._process(5.74)
	expect(scene.colony.is_exhausted() and scene.colony.player_energy() == 0.0, "resuming still requires every remaining active second")
	scene._process(0.01)
	expect(not scene.colony.is_exhausted() and scene.colony.player_energy() == 5.0, "pause and menu resume complete the same eight-second rest")
	scene.free()

func check_persistence() -> void:
	clean()
	var scene := fixture()
	collapse(scene)
	scene._process(2.375)
	var player: Dictionary = scene.colony.get_resident("player")
	var origin: Array = player.pos.duplicate()
	expect(scene.colony.save_game(), "a partial forced rest saves to an isolated test file")
	var saved: Dictionary = player.sleep.duplicate(true)
	scene.free()
	scene = fixture()
	expect(scene.colony.load_game(), "a fresh controller loads the partial rest")
	player = scene.colony.get_resident("player")
	scene.update_room()
	# JSON roundtrips may round the sub-frame decimal residue; require a difference
	# far below a frame while preserving the state shape and physical point exactly.
	expect(scene.colony.is_exhausted() and player.sleep.size() == saved.size() and player.sleep.kind == saved.kind and absf(float(player.sleep.remaining)-float(saved.remaining)) < 0.000000001 and player.pos == origin and player.room == "street", "reload preserves remaining duration and exact physical location")
	scene._process(5.624)
	expect(scene.colony.is_exhausted() and scene.colony.player_energy() == 0.0, "loading neither restarts eight seconds nor completes the rest early")
	scene._process(0.001)
	expect(not scene.colony.is_exhausted() and scene.colony.player_energy() == 5.0 and player.pos == origin, "loaded rest wakes at the original remaining deadline with exactly five percent")
	# A legacy zero-energy save has no forced-rest state; loading must start one.
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	for person: Dictionary in payload.residents:
		if person.id == "player":
			person.energy = 0.0
			person.erase("sleep")
	var file := FileAccess.open(save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	expect(scene.colony.load_game() and scene.colony.is_exhausted(), "loading an old zero-energy save starts forced rest automatically")
	player = scene.colony.get_resident("player")
	expect(player.pos == origin and player.room == "street" and scene.colony.player_energy() == 0.0, "legacy collapse keeps location and grants no instant recovery")
	scene.free()
	clean()

func run() -> void:
	root.size = Vector2i(768,432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; refusing to access normal player progress.")
		quit(1)
		return
	for action in ["city_left","city_right","city_up","city_down"]:
		if InputMap.has_action(action): Input.action_release(action)
	for speed: float in [1.0,4.0]:
		for hz in [10,60,144]: pattern([1.0/hz],speed,"street","%dHz at%dx" % [hz,speed])
		pattern([0.011,0.047,0.131,0.004,0.207,0.029],speed,"player","jitter at%dx" % speed)
		var scene := fixture()
		scene.time_speed = speed
		var origin: Array = scene.colony.get_resident("player").pos.duplicate()
		var minute: int = scene.colony.minute
		collapse(scene)
		scene._process(20.0)
		expect(not scene.colony.is_exhausted() and scene.colony.player_energy() == 5.0 and scene.colony.get_resident("player").pos == origin, "long frame at%dx stops exactly at waking with five percent and no movement" % speed)
		expect(scene.colony.minute == minute+10 and scene.provider_calls == 0, "long frame at%dx cannot simulate its unused twelve seconds after waking" % speed)
		scene.free()
	check_controls()
	check_cancellation()
	check_pause_and_menu()
	check_persistence()
	var scene := fixture()
	var player: Dictionary = scene.colony.get_resident("player")
	player.energy = 0.001
	scene.colony.tick(false)
	expect(scene.colony.is_exhausted() and scene.colony.is_sleeping("player") and scene.colony.player_energy() == 0.0, "normal energy drain reaching zero starts collapse in the same world tick")
	scene.free()
	await process_frame
	print("EXHAUSTION: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
