extends SceneTree
## Main's actual clock, movement, crowd and input in an isolated small settlement.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 0.05
class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_a: String,_b: String,_text: String) -> void: provider_calls += 1
var scene: MainProbe
var checks := 0
var failures: Array[String] = []
var invalid_steps := 0
var overlaps := 0
var movement_samples := 0
var movement_distance := 0.0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func place(id: String, room: String, point: Vector2) -> void:
	var person: Dictionary = scene.colony.get_resident(id)
	person.room = room
	person.pos = [point.x,point.y]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	person.erase("travel_route")
	scene.paths.erase(id)
	scene.colony._daily_life.forget(id)
	scene.update_room()

func frame() -> void:
	var before := {}
	for actor: Dictionary in scene.colony.active_residents(): before[actor.id] = {"room":actor.room,"point":scene.position_of(actor)}
	scene.advance_world(STEP,false,false)
	for actor: Dictionary in scene.colony.active_residents():
		var point: Vector2 = scene.position_of(actor)
		movement_samples += 1
		if not Navigation.is_walkable(point,actor.room): invalid_steps += 1
		if before.has(actor.id) and actor.room == before[actor.id].room: movement_distance += point.distance_to(before[actor.id].point)
		for other: Dictionary in scene.colony.active_residents():
			if actor.id >= other.id or actor.room != other.room: continue
			if ((point-scene.position_of(other))/Vector2(16,14)).length_squared() < 0.999: overlaps += 1

func complete(task: String, worker: String = "player", max_seconds: float = 90.0) -> bool:
	scene.begin_settlement_task(task,worker)
	if not scene.colony.settlement_jobs.busy(worker):
		print("REQUEST FAILED ",task," ",scene.colony.settlement_jobs.preview(worker,task))
		return false
	var elapsed := 0.0
	for _frame in range(int(max_seconds/STEP)):
		frame()
		elapsed += STEP
		if not scene.colony.settlement_jobs.busy(worker):
			print("COMPLETED ",task," worker=",worker," seconds=",elapsed," room=",scene.colony.get_resident(worker).room)
			return true
	print("STALLED ",task," worker=",worker," actor=",scene.colony.get_resident(worker).pos," room=",scene.colony.get_resident(worker).room," job=",scene.colony.settlement.state.jobs.get(worker,{})," route=",scene.paths.get(worker,{}))
	return false

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args() or "--settlement-start" not in OS.get_cmdline_user_args():
		push_error("Run with -- --ui-test --settlement-start")
		quit(1)
		return
	root.size = Vector2i(768,432)
	scene = MainProbe.new()
	scene.start_new_game = true
	scene.managed_by_shell = true
	scene.colony.save_path = "user://settlement_runtime_%d.json" % OS.get_process_id()
	root.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_url = ""
	scene.service_token = ""
	scene.paused = false
	scene.controls_active = true
	scene.colony.settlement_jobs.autonomous_enabled = false
	scene.colony._social._willingness_roll = func() -> float: return 1.0
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	expect(scene.colony.active_residents().size() == 3 and scene.colony.progression_state().coins == 8, "real Main starts with three residents and the small-town wallet")
	var initial: Array = scene.colony.get_resident("player").pos.duplicate()
	expect(complete("gather:fallen_branches"), "Main moves the player to wood and performs the complete gathering job")
	expect(scene.colony.get_resident("player").pos != initial and scene.colony.progression_state().inventory.get("madera",0) == 2, "resources appear after actual travel and work")
	expect(complete("gather:loose_stones"), "player walks from wood to stone through the live crowd controller")
	expect(complete("build:workbench"), "gathered resources fund and complete the first construction in Main")
	expect(scene.colony.settlement.building_ready("workbench") and scene.colony.progression_state().inventory.get("madera",0) == 0 and scene.colony.progression_state().inventory.get("piedra",0) == 0, "first building consumes its real gathered materials once")
	# The NPC path starts in another area and includes the actual outbound and return portals.
	scene.colony.minute = 600
	if scene.encounters != null: scene.encounters.cancel()
	place("lupita","street",Vector2(280,214))
	place("ines","street",Vector2(184,192))
	scene.colony.conversation_holds.append("ines")
	var held: Array = scene.colony.get_resident("ines").pos.duplicate()
	scene.begin_settlement_task("gather:fallen_branches","lupita")
	expect(scene.colony.settlement_jobs.busy("lupita"), "a real Main request starts Lupita's cross-area commitment")
	var reached_work := false
	for _frame in range(1200):
		frame()
		if scene.colony.settlement.state.jobs.get("lupita",{}).get("phase","") == "working":
			reached_work = true
			break
	expect(reached_work and scene.colony.get_resident("lupita").room == "homes", "NPC reaches the resource with real pathfinding and room crossing")
	scene.colony.conversation_holds.append("lupita")
	var stopped: Array = scene.colony.get_resident("lupita").pos.duplicate()
	var progress: float = float(scene.colony.settlement.state.jobs.get("lupita",{}).get("progress",-1))
	for _frame in range(100): frame()
	expect(scene.colony.get_resident("lupita").pos == stopped and scene.colony.settlement.state.jobs.get("lupita",{}).get("progress",-2) == progress, "live held conversation freezes the worker and all productive progress")
	scene.colony.conversation_holds.erase("lupita")
	var returning_seen := false
	var returned := false
	for _frame in range(1600):
		frame()
		var job: Dictionary = scene.colony.settlement.state.jobs.get("lupita",{})
		if job.get("phase","") == "returning":
			returning_seen = true
			if scene.colony.progression_state().inventory.get("madera",0) != 0: expect(false,"return cargo must not be credited before delivery")
		if job.is_empty():
			returned = true
			break
	if not returned: print("NPC RETURN STALLED ",scene.colony.get_resident("lupita").pos," ",scene.colony.get_resident("lupita").room," ",scene.paths.get("lupita",{}))
	expect(returning_seen and returned and scene.colony.progression_state().inventory.get("madera",0) == 2, "NPC resumes and carries the materials back through live portals before settlement")
	expect(scene.colony.get_resident("ines").pos == held, "moving worker routes around a stationary held resident")
	expect(invalid_steps == 0 and overlaps == 0 and movement_distance > 1000, "productive runtime paths stay on ground and outside other bodies")
	scene.colony.conversation_holds.clear()
	# Closed frontier remains closed through real keyboard movement.
	if scene.encounters != null: scene.encounters.cancel()
	place("player","street",Vector2(244,84))
	scene.get_viewport().gui_release_focus()
	for _step in range(8): scene.move_player_keyboard(Vector2.UP,0.1)
	expect(scene.colony.get_resident("player").room == "street" and scene.position_of(scene.colony.get_resident("player")).y >= 76, "keyboard cannot cross the locked northern frontier")
	expect(not scene.colony.travel_to("player","gardens",Vector2(244,268)), "click travel cannot bypass the same locked area")
	# Absent records may share stored coordinates; they are neither hit targets nor bodies.
	place("player","homes",Vector2(250,230))
	place("cesar","homes",Vector2(280,230))
	var absent: Dictionary = scene.colony.get_resident("cesar")
	var hit: Dictionary = scene.pick_world_target(Vector2(280,215),scene.home_project_state())
	expect(hit.get("resident_id","") != "cesar" and Vector2(280,230) not in scene.crowd.people(scene.colony.get_resident("player")), "absent NPC is excluded from hover targets and collision bodies")
	for _step in range(10): scene.move_player_keyboard(Vector2.RIGHT,0.1)
	expect(scene.position_of(scene.colony.get_resident("player")).x > 286 and Layout.point(absent.pos) == Vector2(280,230), "manual player crosses an absent record without pushing or being blocked")
	expect(scene.provider_calls == 0 and not FileAccess.file_exists(scene.colony.save_path), "entire runtime test performs no provider call or save write")
	print("RESULT: %d/%d settlement runtime checks; %d actor samples; %.0f physical pixels" % [checks-failures.size(),checks,movement_samples,movement_distance])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
