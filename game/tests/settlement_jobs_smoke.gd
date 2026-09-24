extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures: Array[String] = []
var invalid_steps := 0
var walked := 0.0
var sequence := 0
var files: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func fixture(developed: bool = false):
	var world = Colony.new()
	sequence += 1
	world.save_path = "user://settlement_jobs_%d_%d.json" % [OS.get_process_id(), sequence]
	files.append(world.save_path)
	world.setup(false, developed)
	world.settlement_jobs.autonomous_enabled = false
	world._social._willingness_roll = func() -> float: return 1.0
	return world

func place(world, id: String, room: String, point: Vector2) -> void:
	var actor: Dictionary = world.get_resident(id)
	actor.room = room
	actor.pos = [point.x, point.y]
	actor.target = actor.pos.duplicate()
	actor.erase("travel_route")
	actor.erase("sleep")
	actor.travel_intent = ""
	world._daily_life.forget(id)

func walk(world, id: String, budget: float = 120.0) -> void:
	var actor: Dictionary = world.get_resident(id)
	if world.is_sleeping(id) or id in world.conversation_holds: return
	var point := Layout.point(actor.pos)
	var goal := Layout.point(actor.target)
	for waypoint: Vector2 in Navigation.route(point, goal, actor.room):
		while point.distance_to(waypoint) > 0.001 and budget > 0.001:
			var step: float = minf(2, minf(budget, point.distance_to(waypoint)))
			point = point.move_toward(waypoint, step)
			if not Navigation.is_walkable(point, actor.room): invalid_steps += 1
			walked += step
			budget -= step
		if budget <= 0.001: break
	actor.pos = [point.x, point.y]
	if point.distance_to(goal) <= 0.01: world.on_arrival(id)

func reach(world, id: String, room: String, point: Vector2) -> bool:
	for _step in range(120):
		walk(world, id)
		var person: Dictionary = world.get_resident(id)
		if person.room == room and Layout.point(person.pos).distance_to(point) < 0.01 and not person.has("travel_route"): return true
	print("ROUTE FAILURE ", id, " ", world.get_resident(id).room, " ", world.get_resident(id).pos, " target=", world.get_resident(id).target, " route=", world.get_resident(id).get("travel_route", {}), " error=", world.last_error)
	return false

func finish(world, id: String, limit: int = 100) -> bool:
	for _step in range(limit):
		walk(world, id)
		world.minute += 5
		world.settlement_jobs.tick()
		if not world.settlement_jobs.busy(id): return true
	return false

func run() -> void:
	var world = fixture()
	var jobs = world.settlement_jobs
	expect(world.active_residents().size() == 3 and not world.is_present("cesar"), "new town keeps only player, Lupita and Inés active")
	expect(world.get_resident("mateo").work_profile.capabilities.has("craft") and world.get_resident("cesar").work_profile.interests.has("farm"), "authored work profiles preserve each resident's distinct abilities")
	var absent: Dictionary = world.get_resident("cesar").duplicate(true)
	for _tick in range(3): world.tick(false)
	expect(world.get_resident("cesar") == absent, "absent character neither moves, works, recovers relationships nor acquires memories")
	var before: Dictionary = world.settlement.snapshot()
	var memories: Array = world.get_resident("player").memories.duplicate(true)
	for _preview in range(10): jobs.preview("player", "gather:fallen_branches")
	expect(world.settlement.snapshot() == before and world.get_resident("player").memories == memories, "opening a task repeatedly is a pure preview")
	expect(not jobs.request("cesar", "gather:fallen_branches").ok and world.settlement.snapshot() == before, "absent worker cannot reserve resources")
	var pos: Array = world.get_resident("player").pos.duplicate()
	expect(jobs.request("player", "gather:fallen_branches").ok, "player accepts a gathering job in the small starting town")
	expect(world.get_resident("player").pos == pos and jobs.busy("player"), "acceptance assigns physical travel without teleporting")
	expect(int(world.progression_state().inventory.get("madera", 0)) == 0 and world.settlement.state.nodes.fallen_branches.remaining == 4, "stock is reserved without granting resources before work")
	var reserved: Dictionary = world.settlement.snapshot()
	expect(not jobs.request("player", "gather:fallen_branches").ok and world.settlement.snapshot() == reserved, "double submission cannot charge or reserve twice")
	jobs.tick()
	expect(world.settlement.state.jobs.player.progress == 0, "no remote work progresses before arrival")
	var spec: Dictionary = world.settlement.task_spec("gather:fallen_branches")
	expect(reach(world,"player",spec.room,Layout.point(spec.at)), "player reaches the material along walkable paths")
	jobs.tick()
	expect(world.settlement.state.jobs.player.phase == "working" and world.settlement.state.jobs.player.progress == 0, "arrival starts work without crediting the travel interval")
	world.conversation_holds.append("player")
	var energy: float = world.player_energy()
	jobs.tick(15)
	expect(world.settlement.state.jobs.player.phase == "paused" and world.settlement.state.jobs.player.progress == 0 and world.player_energy() == energy, "conversation pause advances neither work nor energy cost")
	world.conversation_holds.clear()
	jobs.tick()
	jobs.tick()
	expect(world.settlement.state.jobs.player.progress == 5 and is_equal_approx(world.player_energy(),energy-1.5), "resumed physical work charges only its actual half-duration")
	expect(world.save_game(), "an in-progress commitment saves with escrow and spent energy")
	var restored = Colony.new()
	restored.save_path = world.save_path
	restored.setup(false)
	expect(restored.load_game(), "saved work loads into the same persistent ledger")
	restored.settlement_jobs.autonomous_enabled = false
	expect(restored.settlement.state.jobs.player.progress == 5 and restored.get_resident("player").work_profile == world.get_resident("player").work_profile, "load preserves work and merges authored capabilities")
	var stock: int = int(restored.settlement.state.nodes.fallen_branches.remaining)
	expect(restored.settlement_jobs.cancel("player").ok and restored.settlement.state.nodes.fallen_branches.remaining == stock+2, "cancellation releases reserved gathering stock")
	expect(not restored.settlement_jobs.cancel("player").ok and restored.settlement.state.nodes.fallen_branches.remaining == stock+2, "cancelling twice cannot create stock")
	expect(int(restored.progression_state().inventory.get("madera",0)) == 0, "cancelled gathering grants no output")
	world = fixture(true)
	jobs = world.settlement_jobs
	world._progression._add_items({"madera": 2})
	expect(jobs.request("player", "produce:boards").ok and world.progression_state().inventory.get("madera",0) == 0, "production holds inputs in escrow once")
	expect(jobs.cancel("player").ok and world.progression_state().inventory.madera == 2, "production cancellation returns its exact ingredients")
	expect(jobs.request("player", "produce:boards").ok and finish(world,"player"), "production requires travel and the full local work duration")
	expect(world.progression_state().inventory.get("tablones",0) == 1 and world.progression_state().inventory.get("madera",0) == 0, "a completed recipe produces exactly one declared output")
	var receipts: Dictionary = world.settlement.state.receipts.duplicate()
	jobs.tick(60)
	expect(world.progression_state().inventory.get("tablones",0) == 1 and world.settlement.state.receipts == receipts, "later ticks do not replay completion")
	world = fixture()
	jobs = world.settlement_jobs
	world.minute = 600
	place(world,"lupita","street",Vector2(280,214))
	place(world,"player","street",Vector2(300,246))
	var relation: Dictionary = world.get_resident("lupita").relationships.player.duplicate(true)
	expect(jobs.request("lupita","gather:fallen_branches").ok, "Lupita voluntarily accepts a preferred task while free")
	expect(world.save_game(), "NPC cross-area travel with a job can be saved")
	var reload = Colony.new()
	reload.save_path = world.save_path
	reload.setup(false)
	expect(reload.load_game() and reload.get_resident("lupita").travel_route.room == "homes", "load restores the actual route to another area")
	reload.settlement_jobs.autonomous_enabled = false
	world = reload
	jobs = world.settlement_jobs
	spec = world.settlement.task_spec("gather:fallen_branches")
	expect(reach(world,"lupita",spec.room,Layout.point(spec.at)), "NPC gathers in the correct area rather than at an equal coordinate elsewhere")
	jobs.tick()
	jobs.tick()
	jobs.tick()
	expect(world.settlement.state.jobs.lupita.phase == "returning" and world.progression_state().inventory.get("madera",0) == 0, "finished NPC gathering is carried home before becoming shared inventory")
	expect(world.save_game(), "return trip with gathered goods is persistent")
	expect(finish(world,"lupita") and world.progression_state().inventory.get("madera",0) == 2, "physical arrival at the community board settles the gathered goods")
	expect(world.get_resident("lupita").relationships.player.trust == relation.trust, "ordinary cooperation does not farm relationship trust")
	expect(world.get_resident("cesar").memories.is_empty(), "absent resident cannot witness another person's work")
	world = fixture()
	jobs = world.settlement_jobs
	var target: Dictionary = world.get_resident("ines").relationships.player
	var emotional: Dictionary = target.duplicate(true)
	var snapshot: Dictionary = world.settlement.snapshot()
	for _preview in range(12): jobs.preview("ines", "gather:fallen_branches")
	expect(world.settlement.snapshot() == snapshot and target == emotional, "previewing a busy neighbour does not count as insistence")
	expect(not jobs.request("ines", "gather:fallen_branches").ok and target == emotional, "first refusal respects the café responsibility without harming friendship")
	world.minute += 5
	jobs.request("ines", "gather:fallen_branches")
	world.minute += 5
	jobs.request("ines", "gather:fallen_branches")
	expect(target.frustration == emotional.frustration+4 and target.tolerance == emotional.tolerance-3 and target.trust == emotional.trust, "repeated real requests exert bounded directed pressure")
	jobs.request("ines", "gather:fallen_branches")
	expect(target.frustration == emotional.frustration+4, "same-minute repeats cannot amplify the penalty")
	expect(world.save_game(), "bounded request history is save-compatible")
	world = fixture()
	jobs = world.settlement_jobs
	world.minute = 600
	world.settlement.state.inhabitants.lupita.energy = 21
	expect(not jobs.preview("lupita", "gather:fallen_branches").ok, "NPC preserves an energy reserve instead of accepting exhaustion")
	world.settlement.state.inhabitants.lupita.energy = 100
	place(world,"lupita","street",Vector2(280,214))
	var offered: String = jobs.autonomous_offer("lupita")
	expect(not offered.is_empty() and not offered.begins_with("produce:") and not offered.begins_with("build:"), "autonomous offer uses a free task rather than spending communal materials")
	var wallet: Dictionary = world.progression_state()
	jobs.autonomous_enabled = true
	for _step in range(6): jobs.tick()
	expect(jobs.busy("lupita") and world.progression_state() == wallet, "bounded local autonomy accepts a productive task without provider calls or spending")
	jobs.cancel("lupita")
	expect(jobs.autonomous_offer("lupita").is_empty(), "a respectful cancellation leaves a cooldown before another autonomous offer")
	world = fixture()
	jobs = world.settlement_jobs
	world._progression.state.coins = 100
	world._progression._add_items({"madera":20,"piedra":20})
	expect(jobs.request("player","build:workbench").ok, "construction is funded explicitly before work")
	spec = world.settlement.task_spec("build:workbench")
	expect(reach(world,"player",spec.room,Layout.point(spec.at)), "builder reaches the fixed project footprint safely")
	jobs.tick()
	jobs.tick()
	var payment: Dictionary = world.progression_state()
	expect(jobs.cancel("player").ok and world.settlement.state.projects.workbench.progress == 5 and world.progression_state() == payment, "cancelled construction retains its actual work and invested cost")
	expect(jobs.request("player","build:workbench").ok and world.settlement.state.jobs.player.progress == 5 and world.progression_state() == payment, "resuming construction neither loses work nor charges again")
	expect(finish(world,"player") and world.settlement.building_ready("workbench"), "resumed construction finishes the building once")
	world = fixture()
	jobs = world.settlement_jobs
	world.minute = 1200
	place(world,"lupita","homes",Vector2(90,262))
	place(world,"player","street",Vector2(300,246))
	expect(jobs.request("lupita","gather:fallen_branches").ok, "late-day work begins only while the resident is available")
	spec = world.settlement.task_spec("gather:fallen_branches")
	reach(world,"lupita",spec.room,Layout.point(spec.at))
	jobs.tick()
	jobs.tick()
	world.minute = 1290
	jobs.tick()
	var partial: float = world.settlement.state.jobs.lupita.progress
	for _step in range(80):
		walk(world,"lupita")
		world.tick(false)
		if world.is_sleeping("lupita"): break
	expect(world.is_sleeping("lupita") and world.get_resident("lupita").room == "lupita", "nightfall pauses the accepted job and walks the neighbour to her real bed")
	expect(partial == 5 and world.settlement.state.jobs.lupita.progress == partial, "travel home and sleep do not manufacture productive progress")
	expect(world.daily_state("lupita").kind == "sleeping", "the visible state shows sleep rather than a permanent work label")
	expect(world.save_game(), "sleeping mid-job remains a valid persistent state")
	for _step in range(210):
		walk(world,"lupita")
		world.tick(false)
		if not jobs.busy("lupita"): break
	expect(not jobs.busy("lupita") and world.progression_state().inventory.get("madera",0) == 2, "the neighbour wakes, resumes the unfinished work and physically delivers it")
	expect(invalid_steps == 0 and walked > 1000, "all productive travel samples stay on navigable ground")
	for path: String in files:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("RESULT: %d/%d jobs checks; %.0f physical pixels walked" % [checks-failures.size(), checks, walked])
	quit(0 if failures.is_empty() else 1)
