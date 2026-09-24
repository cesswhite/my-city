extends SceneTree
## Physical crowd regression; isolated fixtures, no provider or real-save access.
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const NPCS: Array[String] = ["cesar", "lupita", "mateo", "ines", "alma"]
const STEP := 0.05

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var movement_samples := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func put(world, id: String, point: Vector2, goal: Vector2, room: String = "street") -> void:
	var person: Dictionary = world.get_resident(id)
	person.room = room
	person.pos = [point.x, point.y]
	person.target = [goal.x, goal.y]
	person.travel_intent = ""

func seed_fixture(world) -> void:
	for index in range(NPCS.size()):
		var point := Vector2(264 + index * 20, 180)
		put(world, NPCS[index], point, point)
	put(world,"player",Layout.point(Layout.data().entry),Layout.point(Layout.data().entry),"player")

func fixture() -> MainProbe:
	var scene := MainProbe.new()
	scene.start_new_game = true
	scene.colony.save_path = "user://test_crowd_spacing_%d.json" % OS.get_process_id()
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_url = ""
	scene.service_token = ""
	scene.use_jev = false
	scene.controls_active = true
	scene.paused = false
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	for resident: Dictionary in scene.colony.residents:
		put(scene.colony,resident.id,Layout.point(Layout.data().entry),Layout.point(Layout.data().entry),resident.id)
	return scene

func minimum_gap(world, ids: Array[String], targets: bool = false) -> float:
	var result := INF
	for a in range(ids.size()):
		var first: Dictionary = world.get_resident(ids[a])
		for b in range(a+1,ids.size()):
			var second: Dictionary = world.get_resident(ids[b])
			if first.room != second.room: continue
			var one: Vector2 = Layout.point(first.target if targets else first.pos)
			var two: Vector2 = Layout.point(second.target if targets else second.pos)
			result = minf(result,one.distance_to(two))
	return result

func body_clearance(world, ids: Array[String]) -> float:
	# Feet at different depths can pass with 14 px vertically; side-by-side needs 16.
	var result := INF
	for a in range(ids.size()):
		var first: Dictionary = world.get_resident(ids[a])
		for b in range(a+1,ids.size()):
			var second: Dictionary = world.get_resident(ids[b])
			if first.room != second.room: continue
			var offset: Vector2 = Layout.point(first.pos)-Layout.point(second.pos)
			result = minf(result,Vector2(offset.x/16.0,offset.y/14.0).length())
	return result

func step_people(scene: MainProbe, ids: Array[String], frames: int) -> Dictionary:
	var result := {"walkable":true,"speed":true,"gap":minimum_gap(scene.colony,ids),"clearance":body_clearance(scene.colony,ids),"reached":false}
	for _frame in range(frames):
		for id: String in ids:
			var resident: Dictionary = scene.colony.get_resident(id)
			var before: Vector2 = Layout.point(resident.pos)
			var old_room: String = resident.room
			scene.move_resident(resident,STEP)
			var after: Vector2 = Layout.point(resident.pos)
			movement_samples += 1
			result.walkable = result.walkable and Navigation.is_walkable(after,resident.room)
			if old_room == resident.room:
				result.speed = result.speed and before.distance_to(after) <= scene.resident_walk_speed(resident)*STEP+0.01
				result.walkable = result.walkable and Navigation._clear_segment(before,after,resident.room)
		result.gap = minf(result.gap,minimum_gap(scene.colony,ids))
		result.clearance = minf(result.clearance,body_clearance(scene.colony,ids))
		var arrived := true
		for id: String in ids:
			var resident: Dictionary = scene.colony.get_resident(id)
			# Portals fire at the actual waypoint; proximity alone must not end the trip.
			arrived = arrived and Layout.point(resident.pos).distance_to(Layout.point(resident.target)) < 0.01
		if arrived:
			result.reached = true
			return result
	return result

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; refusing access to real progress.")
		quit(1)
		return
	root.size = Vector2i(768,432)
	for place: String in ["plaza","cafe","taller","huerto"]:
		var world = Colony.new()
		world.setup(false, true)
		seed_fixture(world)
		var accepted := true
		for id: String in NPCS: accepted = world.apply_decision(id,place) and accepted
		var valid := true
		for id: String in NPCS:
			var resident: Dictionary = world.get_resident(id)
			var target: Vector2 = Layout.point(resident.target)
			var route: Array[Vector2] = Navigation.route(Layout.point(resident.pos),target,"street")
			valid = valid and Navigation.is_walkable(target,"street") and not route.is_empty() and route[-1].distance_to(target) < 0.01
		expect(accepted,place + " accepts the same real destination choice for all five neighbors")
		expect(valid,place + " assigns five physical destinations with reachable routes")
		expect(minimum_gap(world,NPCS,true) >= 17.99,place + " destinations reserve eighteen pixels between neighbors")
		world.set_player_autonomy(true)
		put(world,"player",Vector2(364,180),Vector2(364,180))
		var six: Array[String] = NPCS.duplicate()
		six.append("player")
		for id: String in six: accepted = world.apply_decision(id,place) and accepted
		var valid_six := true
		for id: String in six:
			var resident: Dictionary = world.get_resident(id)
			var target: Vector2 = Layout.point(resident.target)
			valid_six = valid_six and Navigation.is_walkable(target,"street") and not Navigation.route(Layout.point(resident.pos),target,"street").is_empty()
		expect(accepted and valid_six and minimum_gap(world,six,true) >= 17.99,place + " also reserves six reachable places when the player opts into autonomous life")

	# The actual mover must handle the convergence, not just choose spread-out goals.
	for place: String in ["plaza","cafe","huerto"]:
		var scene := fixture()
		seed_fixture(scene.colony)
		var travelers: Array[String] = NPCS.duplicate()
		if place == "huerto":
			scene.colony.set_player_autonomy(true)
			put(scene.colony,"player",Vector2(364,180),Vector2(364,180))
			travelers.append("player")
		for id: String in travelers: scene.colony.apply_decision(id,place)
		var travel := step_people(scene,travelers,1200)
		print("CROWD %s: reached=%s min_gap=%.2f" % [place,travel.reached,travel.gap])
		if not travel.reached:
			for id: String in travelers:
				var resident: Dictionary = scene.colony.get_resident(id)
				var path: Dictionary = scene.paths.get(id,{})
				print("STALLED %s room=%s pos=%s target=%s blocked=%s path_index=%s path_size=%s" % [id,resident.room,resident.pos,resident.target,path.get("blocked",false),path.get("index",0),path.get("points",[]).size()])
		expect(travel.reached,place + " crowd reaches its distributed destinations without a permanent queue")
		expect(travel.walkable and travel.speed,place + " avoidance stays on walkable segments at normal walking speed")
		expect(float(travel.clearance) >= 0.99,place + " convergence respects the sixteen-by-fourteen-pixel body spacing")
		expect(minimum_gap(scene.colony,travelers) >= 15.99,place + " resting neighbors remain visibly separated")
		expect(scene.provider_calls == 0 and scene.colony.minute == 480,place + " physical movement creates no AI work or artificial time changes")
		scene.free()

	# Two people walking towards each other's start must pass, rather than both wait forever.
	var scene := fixture()
	put(scene.colony,"cesar",Vector2(264,196),Vector2(336,196))
	put(scene.colony,"lupita",Vector2(336,196),Vector2(264,196))
	var crossing := step_people(scene,["cesar","lupita"],800)
	print("CROWD head-on: reached=%s min_gap=%.2f" % [crossing.reached,crossing.gap])
	expect(crossing.reached,"opposing walkers both reach the far side without deadlock")
	expect(crossing.walkable and crossing.speed,"passing another neighbor never crosses furniture or exceeds walking speed")
	expect(float(crossing.clearance) >= 0.99,"opposing walkers keep their bodies apart while passing")
	scene.free()

	# A manual player and a held partner never get shoved by a passing neighbor.
	scene = fixture()
	put(scene.colony,"player",Vector2(284,196),Vector2(284,196))
	put(scene.colony,"mateo",Vector2(302,196),Vector2(302,196))
	put(scene.colony,"cesar",Vector2(258,196),Vector2(338,196))
	scene.update_room()
	expect(scene.start_player_conversation("mateo"),"a legitimate nearby conversation reserves the stationary pair")
	var player_start: Array = scene.colony.get_resident("player").pos.duplicate()
	var partner_start: Array = scene.colony.get_resident("mateo").pos.duplicate()
	var passing := step_people(scene,["player","mateo","cesar"],1000)
	expect(passing.reached and passing.walkable and passing.speed,"a passerby can navigate around a held conversation")
	expect(scene.colony.get_resident("player").pos == player_start and scene.colony.get_resident("mateo").pos == partner_start,"avoidance never displaces the manual player or held interlocutor")
	expect(float(passing.clearance) >= 0.99,"passing a conversation does not cut through either participant")
	scene.player_chat.finish()
	put(scene.colony,"mateo",Layout.point(Layout.data().entry),Layout.point(Layout.data().entry),"mateo")
	put(scene.colony,"cesar",Vector2(258,196),Vector2(338,196))
	scene.paths.clear()
	var manual := step_people(scene,["player","cesar"],800)
	expect(manual.reached and manual.walkable and float(manual.clearance) >= 0.99 and scene.colony.get_resident("player").pos == player_start,"an idle manual player stays fixed while a neighbor finds a way around")
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty(),"reserving and passing the pair sends no conversation request")
	scene.free()

	scene = fixture()
	put(scene.colony,"player",Vector2(264,196),Vector2(264,196))
	put(scene.colony,"mateo",Vector2(318,196),Vector2(318,196))
	scene.update_room()
	var manual_clearance := INF
	var manual_valid := true
	for _frame in range(20):
		var before: Vector2 = scene.position_of(scene.colony.get_resident("player"))
		scene.move_player_keyboard(Vector2.RIGHT,0.1)
		var after: Vector2 = scene.position_of(scene.colony.get_resident("player"))
		manual_clearance = minf(manual_clearance,body_clearance(scene.colony,["player","mateo"]))
		manual_valid = manual_valid and Navigation._clear_segment(before,after,"street") and before.distance_to(after) <= 4.81
	var stopped: Vector2 = scene.position_of(scene.colony.get_resident("player"))
	expect(manual_clearance >= 0.99 and manual_valid and stopped.x > 280 and stopped.x < 318,"held manual movement approaches a stationary neighbor without crossing their body")
	expect(Layout.point(scene.colony.get_resident("mateo").pos) == Vector2(318,196),"keyboard collision never pushes the stationary neighbor")
	for _frame in range(4): scene.move_player_keyboard(Vector2.UP,0.1)
	var escaped: Vector2 = scene.position_of(scene.colony.get_resident("player"))
	expect(escaped.y < stopped.y-15 and Navigation.is_walkable(escaped,"street") and body_clearance(scene.colony,["player","mateo"]) >= 0.99,"after contact the player can immediately walk sideways away from the neighbor")
	scene.free()

	# Existing saves can start with identical coordinates. Recovery must be gradual.
	scene = fixture()
	for id: String in ["cesar","lupita","mateo","player"]:
		put(scene.colony,id,Vector2(280,180),Vector2(280,180))
	var recovery_valid := true
	var recovery_speed := true
	for _frame in range(240):
		for id: String in ["cesar","lupita","mateo","player"]:
			var resident: Dictionary = scene.colony.get_resident(id)
			var before: Vector2 = Layout.point(resident.pos)
			scene.move_resident(resident,STEP)
			var after: Vector2 = Layout.point(resident.pos)
			recovery_speed = recovery_speed and before.distance_to(after) <= scene.resident_walk_speed(resident)*STEP+0.01
			recovery_valid = recovery_valid and Navigation.is_walkable(after,"street") and Navigation._clear_segment(before,after,"street")
			movement_samples += 1
	expect(body_clearance(scene.colony,["cesar","lupita","mateo","player"]) >= 0.99,"neighbors already overlapping in an old position separate within twelve seconds")
	expect(recovery_speed and recovery_valid,"recovering an existing overlap walks gradually without teleporting through obstacles")
	expect(Layout.point(scene.colony.get_resident("player").pos) == Vector2(280,180),"overlap recovery never pushes the stationary manual player")
	scene.free()

	# A portal waits for the destination room's occupied arrival point, then retries.
	scene = fixture()
	var door: Vector2 = Layout.door_positions().cesar
	var entry: Vector2 = Layout.point(Layout.data().entry)
	put(scene.colony,"cesar",door-Vector2(20,0),door)
	put(scene.colony,"lupita",entry,entry,"cesar")
	var entering: Dictionary = scene.colony.get_resident("cesar")
	entering.travel_intent = "casa"
	entering.routine_place = "casa"
	for _frame in range(50): scene.move_resident(entering,STEP)
	expect(entering.room == "street" and Layout.point(entering.pos).distance_to(door) < 0.01,"an occupied interior arrival point makes the owner wait at the actual street door")
	expect(Layout.point(scene.colony.get_resident("lupita").pos) == entry,"waiting at a doorway never pushes the resident already inside")
	var visitor: Dictionary = scene.colony.get_resident("lupita")
	visitor.target = [264.0,240.0]
	var entering_trip := step_people(scene,["lupita","cesar"],500)
	expect(entering.room == "cesar" and entering_trip.reached and entering_trip.walkable and float(entering_trip.clearance) >= 0.99,"the same pending entry retries and completes once its physical arrival point becomes free")
	put(scene.colony,"mateo",door,door)
	entering.target = Layout.data().exit.duplicate()
	entering.travel_intent = "cafe"
	for _frame in range(300): scene.move_resident(entering,STEP)
	expect(entering.room == "cesar" and Layout.point(entering.pos).distance_to(Layout.point(Layout.data().exit)) < 0.01,"an occupied street arrival point makes an exiting resident wait inside")
	var blocker: Dictionary = scene.colony.get_resident("mateo")
	var clear_door: Vector2 = Navigation.recover_position(door+Vector2(0,32),"street")
	blocker.target = [clear_door.x,clear_door.y]
	var exiting_trip := step_people(scene,["mateo","cesar"],800)
	if entering.room != "street" or not exiting_trip.reached or not exiting_trip.walkable or float(exiting_trip.clearance) < 0.99:
		print("EXIT RETRY result=%s owner_room=%s owner_pos=%s owner_target=%s blocker_pos=%s blocker_target=%s owner_path=%s" % [exiting_trip,entering.room,entering.pos,entering.target,blocker.pos,blocker.target,scene.paths.get("cesar",{})])
	expect(entering.room == "street" and exiting_trip.reached and exiting_trip.walkable and float(exiting_trip.clearance) >= 0.99,"the queued exit retries after the street doorway clears and resumes the intended route")
	scene.free()

	# Run the schedule's actual portals, then let the morning crowd leave again.
	scene = fixture()
	seed_fixture(scene.colony)
	scene.colony.minute = 1315
	scene.colony.tick(false)
	var home_trip := step_people(scene,NPCS,3000)
	var home_ok := true
	for id: String in NPCS: home_ok = home_ok and scene.colony.get_resident(id).room == id
	expect(home_ok and home_trip.reached,"night routines still bring all five neighbors through their own doors")
	expect(home_trip.walkable and home_trip.speed,"night crowd routes preserve legal movement on both sides of each portal")
	scene.colony.minute = 2040
	scene.colony.tick(false)
	var morning_trip := step_people(scene,NPCS,3000)
	var outside := true
	for id: String in NPCS: outside = outside and scene.colony.get_resident(id).room == "street"
	if not outside or not morning_trip.reached:
		for id: String in NPCS:
			var resident: Dictionary = scene.colony.get_resident(id)
			var path: Dictionary = scene.paths.get(id,{})
			print("MORNING %s room=%s pos=%s target=%s intent=%s blocked=%s path_index=%s path_size=%s" % [id,resident.room,resident.pos,resident.target,resident.get("travel_intent",""),path.get("blocked",false),path.get("index",0),path.get("points",[]).size()])
	expect(outside and morning_trip.reached,"morning routines leave home and reach their shared neighborhood places")
	expect(morning_trip.walkable and morning_trip.speed,"morning exit and shared routes never invalidate the navigation geometry")
	expect(scene.provider_calls == 0 and not scene.decision_pending and scene.dialogue_job.is_empty(),"all crowd fixtures finish without provider calls or pending jobs")
	scene.free()
	print("CROWD SPACING: %d/%d checks passed; %d movement samples" % [checks-failures.size(),checks,movement_samples])
	quit(0 if failures.is_empty() else 1)
