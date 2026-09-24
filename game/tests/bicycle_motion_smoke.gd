extends SceneTree
## Real player movement, collision sweeps and route traversal; no saves or providers.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const CrowdMotion = preload("res://scripts/crowd_motion.gd")
const ACTIONS := ["city_left", "city_right", "city_up", "city_down"]

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

class CrowdProbe:
	extends "res://scripts/crowd_motion.gd"
	var samples := 0
	var longest_step := 0.0
	var invalid_steps := 0
	func _init(owner: Control) -> void: super(owner)
	func can_step(from: Vector2, to: Vector2, room: String, occupied: Array[Vector2]) -> bool:
		samples += 1
		longest_step = maxf(longest_step,from.distance_to(to))
		var allowed: bool = super.can_step(from,to,room,occupied)
		if allowed and not Navigation.is_walkable(to,room): invalid_steps += 1
		return allowed

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func release_keys() -> void:
	for action in ACTIONS: Input.action_release(action)

func position(scene, id: String, at: Vector2, room: String = "street") -> void:
	var resident: Dictionary = scene.colony.get_resident(id)
	resident.room = room
	resident.pos = [at.x,at.y]
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""
	scene.paths.erase(id)

func reset(scene, at: Vector2 = Vector2(336,196), room: String = "street") -> void:
	release_keys()
	scene.take_control()
	scene.hide_inspector()
	scene.close_door_panel()
	scene.close_help()
	scene.learning.close()
	scene.overlay.dismiss_toast()
	scene.controls_active = true
	scene.paused = false
	scene.time_speed = 1.0
	scene.elapsed = 0.0
	scene.get_viewport().gui_release_focus()
	for resident: Dictionary in scene.colony.residents:
		if resident.id != "player": position(scene,resident.id,Layout.point(Layout.data().home_rest),resident.id)
	position(scene,"player",at,room)
	scene.update_room()
	scene.riding_bicycle = Layout.is_outdoor(room)

func unlock(scene) -> bool:
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

func run() -> void:
	root.size = Vector2i(768,432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Pass -- --ui-test to isolate saves and network.")
		quit(1)
		return
	var scene := MainProbe.new()
	scene.start_new_game = true
	scene.colony.save_path = "user://test_bicycle_motion_%d.json" % OS.get_process_id()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_url = ""
	scene.service_token = ""
	scene.crowd = CrowdProbe.new(scene)
	expect(scene.preview_mode and not FileAccess.file_exists(scene.colony.save_path), "isolated scene never loads or writes real progress")
	var player: Dictionary = scene.colony.get_resident("player")
	reset(scene)
	expect(scene.resident_walk_speed(player) == 48.0, "a riding flag alone cannot enable speed before real repair")
	expect(unlock(scene), "fixture earns bicycle through actual purchase, delivery and four repair steps")
	reset(scene)
	expect(scene.resident_walk_speed(player) == 120.0 and scene.resident_walk_speed(scene.colony.get_resident("mateo")) == 30.0, "repaired outdoor bicycle uses120 while neighbors remain30")
	for fps in [30,60,120]:
		reset(scene)
		var origin: Vector2 = scene.position_of(player)
		for _frame in range(fps/2): scene.move_player_keyboard(Vector2.RIGHT,1.0/fps)
		expect(absf(scene.position_of(player).distance_to(origin)-60.0) < 0.01, "manual bicycle advances60px in halfsecond at%dFPS" % fps)
		reset(scene)
		origin = scene.position_of(player)
		player.target = [434.0,196.0]
		for _frame in range(fps/2): scene.move_resident(player,1.0/fps)
		expect(absf(scene.position_of(player).distance_to(origin)-60.0) < 0.01, "route bicycle advances60px in halfsecond at%dFPS" % fps)
	reset(scene)
	var origin: Vector2 = scene.position_of(player)
	for dt in [0.017,0.083,0.03,0.07,0.1,0.04,0.06,0.1]: scene.move_player_keyboard(Vector2.RIGHT,dt)
	expect(absf(scene.position_of(player).distance_to(origin)-60.0) < 0.01, "jittered input frames preserve elapsed-time bicycle speed")
	reset(scene)
	origin = scene.position_of(player)
	scene.move_player_keyboard(Vector2(1,1),0.1)
	expect(absf(scene.position_of(player).distance_to(origin)-12.0) < 0.01, "diagonal cycling does not multiply speed")
	reset(scene)
	origin = scene.position_of(player)
	scene.move_player_keyboard(Vector2.RIGHT,10.0)
	expect(absf(scene.position_of(player).distance_to(origin)-12.0) < 0.01, "real-frame spike is clamped to12px of manual cycling")
	reset(scene)
	scene.time_speed = 4.0
	origin = scene.position_of(player)
	Input.action_press("city_right")
	scene._process(0.1)
	release_keys()
	expect(absf(scene.position_of(player).distance_to(origin)-12.0) < 0.01, "live4x world clock does not accelerate manual input beyond120px/s")
	reset(scene)
	scene.riding_bicycle = false
	origin = scene.position_of(player)
	scene.move_player_keyboard(Vector2.RIGHT,0.1)
	expect(absf(scene.position_of(player).distance_to(origin)-4.8) < 0.01, "dismounting restores48px/s and bicycle is2.5times walking")
	reset(scene,Vector2(224,252),"player")
	scene.riding_bicycle = true
	expect(scene.resident_walk_speed(player) == 48.0, "house movement never inherits outdoor bicycle speed")
	reset(scene)
	scene.paused = true
	origin = scene.position_of(player)
	expect(not scene.move_player_keyboard(Vector2.RIGHT,0.1) and scene.position_of(player) == origin, "paused bicycle does not move")
	reset(scene)
	scene.controls_active = false
	origin = scene.position_of(player)
	expect(not scene.move_player_keyboard(Vector2.RIGHT,0.1) and scene.position_of(player) == origin, "inactive input does not move the rider")

	# Frontal collision with fountain and façade: no endpoint can jump a solid strip.
	reset(scene,Vector2(184,232))
	for _frame in range(30): scene.move_player_keyboard(Vector2.RIGHT,0.1)
	expect(scene.position_of(player).x < 204.0 and scene.position_of(player).y == 232.0 and Navigation.is_walkable(scene.position_of(player)), "120px/s keyboard cannot tunnel through the fountain")
	reset(scene,Vector2(380,192),"workshops")
	for _frame in range(10): scene.move_player_keyboard(Vector2.UP,0.1)
	expect(scene.position_of(player).y >= 160.0 and Navigation.is_walkable(scene.position_of(player),player.room), "rider cannot cross façade or top street boundary")
	reset(scene,Vector2(330,254),"gardens")
	for _frame in range(20): scene.move_player_keyboard(Vector2(1,-1),0.1)
	expect(Navigation.is_walkable(scene.position_of(player),player.room), "diagonal cycling respects narrow garden borders")
	reset(scene,Vector2(280,180))
	position(scene,"mateo",Vector2(320,180))
	var npc_origin: Vector2 = scene.position_of(scene.colony.get_resident("mateo"))
	for _frame in range(10): scene.move_player_keyboard(Vector2.RIGHT,0.1)
	var offset: Vector2 = (scene.position_of(player)-npc_origin)/Vector2(16,14)
	expect(offset.length_squared() >= 0.9999 and scene.position_of(player).x < npc_origin.x and scene.position_of(scene.colony.get_resident("mateo")) == npc_origin, "fast rider stops before a neighbor and does not push through")
	scene.move_player_keyboard(Vector2.DOWN,0.1)
	expect(scene.position_of(player).y > npc_origin.y, "contact still permits steering away from the neighbor")
	reset(scene,Vector2(184,232))
	player.target = [276.0,232.0]
	var arrived := false
	for _frame in range(100):
		scene.move_resident(player,0.4)
		if scene.position_of(player).distance_to(Vector2(276,232)) < 0.01:
			arrived = true
			break
	expect(arrived and Navigation.is_walkable(scene.position_of(player)), "large route delta walks around fountain to destination without cutting through")
	reset(scene,Vector2(280,180))
	position(scene,"mateo",Vector2(320,180))
	player.target = [364.0,180.0]
	for _frame in range(50): scene.move_resident(player,0.4)
	expect(scene.position_of(player).distance_to(Vector2(364,180)) < 0.01 and scene.position_of(scene.colony.get_resident("mateo")) == Vector2(320,180), "routed bicycle passes a stationary neighbor without moving it")
	expect(scene.crowd.samples > 500 and scene.crowd.longest_step <= 1.001 and scene.crowd.invalid_steps == 0, "all accepted movement sweeps stay walkable and at most one pixel")
	expect(scene.provider_calls == 0 and not FileAccess.file_exists(scene.colony.save_path), "movement verification makes no provider requests or save writes")
	release_keys()
	var samples: int = scene.crowd.samples
	scene.queue_free()
	await process_frame
	print("BICYCLE MOTION: %d/%d checks passed; %d collision sweeps" % [checks-failures.size(),checks,samples])
	quit(0 if failures.is_empty() else 1)
