extends SceneTree
## Isolated persistence and transaction attacks; no provider or personal save access.
const Colony = preload("res://scripts/colony.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []
var paths: Array[String] = []

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
	world.save_path = "user://settlement_integrity_%d_%d.json" % [OS.get_process_id(), paths.size()]
	paths.append(world.save_path)
	world.setup(false, developed)
	world.settlement_jobs.autonomous_enabled = false
	return world

func place(world, id: String, room: String, point: Vector2) -> void:
	var actor: Dictionary = world.get_resident(id)
	actor.room = room
	actor.pos = [point.x, point.y]
	actor.target = actor.pos.duplicate()
	actor.travel_intent = ""
	actor.erase("travel_route")
	actor.erase("sleep")
	world._daily_life.forget(id)

func invalid(world, base: Dictionary, change: Callable, label: String) -> void:
	var data: Dictionary = base.duplicate(true)
	change.call(data)
	expect(not world.settlement.validate(data), label)

func job_from_spec(world, task_id: String, worker: String, serial: int) -> Dictionary:
	var spec: Dictionary = world.settlement.task_spec(task_id, worker)
	return {"id":"work-%d" % serial,"worker":worker,"task_id":task_id,"kind":spec.kind,"target_room":spec.room,"target":spec.at.duplicate(),
		"phase":"travelling","progress":0.0,"required":float(spec.minutes),"started":world.minute,"escrow":{"items":spec.inputs.duplicate(true)},"worked":false,"energy":float(spec.energy)}

func run() -> void:
	var world = fixture()
	expect(world.settlement_jobs.request("player","gather:fallen_branches").ok, "gather fixture reserves a real task before corruption tests")
	var base: Dictionary = world.settlement.snapshot()
	expect(world.settlement.validate(base), "unaltered active gathering is valid")
	invalid(world,base,func(d): d.jobs.player.escrow.items = {"madera":999}, "rejects invented refundable escrow items")
	invalid(world,base,func(d): d.jobs.player.escrow.node = "forest_wood", "rejects a reservation redirected to another resource node")
	invalid(world,base,func(d): d.jobs.player.escrow.quantity = 999, "rejects an enlarged reserved quantity")
	invalid(world,base,func(d): d.jobs.player.escrow.period = -1, "rejects a negative reservation period")
	invalid(world,base,func(d): d.jobs.player.energy = 0.0, "rejects free work by altering its authored energy cost")
	invalid(world,base,func(d): d.jobs.player.energy = NAN, "rejects nonfinite job energy")
	invalid(world,base,func(d): d.jobs.player.progress = 999.0, "rejects progress beyond the required duration")
	invalid(world,base,func(d): d.jobs.player.progress = 5.0, "positive progress requires actual worked evidence")
	invalid(world,base,func(d): d.jobs.player.phase = "returning", "player cannot invent a goods-return phase")
	invalid(world,base,func(d): d.jobs.player.target = [100,200], "catalog work location cannot be rewritten in a save")
	invalid(world,base,func(d): d.serial = 0, "active job serial must already have been issued")
	invalid(world,base,func(d): d.receipts[d.jobs.player.id] = world.minute, "settled receipts cannot coexist with an active claim")
	invalid(world,base,func(d):
		d.jobs.lupita = d.jobs.player.duplicate(true)
		d.jobs.lupita.worker = "lupita", "rejects duplicate job IDs across residents")
	invalid(world,base,func(d):
		d.serial = 2
		d.jobs.lupita = d.jobs.player.duplicate(true)
		d.jobs.lupita.worker = "lupita"
		d.jobs.lupita.id = "work-2", "rejects simultaneous reservations of one node")
	invalid(world,base,func(d): d.areas.append("forest"), "closed areas cannot open through an independent flag")
	invalid(world,base,func(d): d.buildings.append("community_hall"), "buildings require their completed project")
	invalid(world,base,func(d): d.inhabitants.cesar.present = true, "resident arrival requires the restored home")
	invalid(world,base,func(d): d.inhabitants.lupita.requests = {"task_id":"gather:fallen_branches","minute":480,"count":4}, "request insistence history is bounded")
	invalid(world,base,func(d): d.inhabitants.lupita.requests = {"task_id":"unknown:task","minute":480,"count":1}, "refusal history references an actual task")
	invalid(world,base,func(d): d.inhabitants.lupita.requests = {"task_id":"gather:fallen_branches","minute":480,"count":1,"extra":true}, "request history rejects extra unbounded metadata")
	invalid(world,base,func(d): d.nodes.erase("fallen_branches"), "reserved gathering requires its stock ledger")
	invalid(world,base,func(d): d.nodes.fallen_branches.remaining = 6, "same-period reserved stock cannot also remain available")
	invalid(world,base,func(d): d.jobs.player = job_from_spec(world,"produce:boards","player",1), "a job cannot bypass its unbuilt workbench prerequisite")
	# Caller copies are only references to an ID; the authority is the live job ledger.
	var spec: Dictionary = world.settlement.task_spec("gather:fallen_branches")
	place(world,"player",spec.room,Layout.point(spec.at))
	var forged: Dictionary = base.jobs.player.duplicate(true)
	forged.worked = true
	forged.progress = forged.required
	forged.phase = "working"
	var wallet: Dictionary = world.progression_state()
	expect(not world.settlement.complete_task(forged).ok and world.progression_state() == wallet, "forged completion copy cannot override unworked canonical progress")
	var genuine: Dictionary = world.settlement.state.jobs.player
	genuine.worked = true
	genuine.progress = genuine.required
	genuine.phase = "working"
	world.conversation_holds.append("player")
	expect(not world.settlement.complete_task(genuine).ok and world.progression_state() == wallet, "conversation hold prevents even a ready job from settling")
	world.conversation_holds.clear()
	place(world,"player","street",Layout.point(spec.at))
	expect(not world.settlement.complete_task(genuine).ok, "matching coordinates in another room cannot complete work")
	place(world,"player",spec.room,Layout.point(spec.at))
	expect(world.settlement.complete_task(genuine).ok, "canonical finished work at the real location settles once")
	var paid: Dictionary = world.progression_state()
	expect(not world.settlement.complete_task(genuine.duplicate(true)).ok and world.progression_state() == paid, "completion retry cannot duplicate resources")
	world.settlement.cancel_task(genuine)
	expect(world.progression_state() == paid and world.settlement.state.nodes.fallen_branches.remaining == 4, "cancelling a settled job cannot refund its stock")
	world.settlement.state.jobs.erase("player")
	expect(world.save_game(), "settled inventory and receipts save after the controller releases its job")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world.save_path))
	payload.settlement.areas.append("forest")
	var file := FileAccess.open(world.save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var corrupted: String = FileAccess.get_file_as_string(world.save_path)
	var loaded = Colony.new()
	loaded.save_path = world.save_path
	loaded.setup(false)
	expect(not loaded.load_game(), "corrupt unlocks are rejected through the full file load path")
	expect(not loaded.save_game() and FileAccess.get_file_as_string(world.save_path) == corrupted, "a rejected save is not overwritten by later saving")
	world = fixture(true)
	world._progression._add_items({"madera":2})
	expect(world.settlement_jobs.request("player","produce:boards").ok, "production escrow fixture consumes exactly two wood")
	var cancelled: Dictionary = world.settlement.state.jobs.player.duplicate(true)
	cancelled.escrow.items = {"madera":999}
	world.settlement.cancel_task(cancelled)
	expect(world.progression_state().inventory.get("madera",0) == 2, "cancel with forged escrow uses the canonical two wood")
	world.settlement.cancel_task(cancelled)
	expect(world.progression_state().inventory.get("madera",0) == 2, "direct cancellation retry is idempotent")
	world.settlement_jobs.cancel("player")
	expect(world.settlement.validate(world.settlement.snapshot()), "controller cleanup after a settled cancellation restores a valid ledger")
	world = fixture()
	world._progression.state.coins = 100
	world._progression._add_items({"madera":20,"piedra":20})
	expect(world.settlement_jobs.request("player","build:workbench").ok, "building fixture has a real paid project")
	base = world.settlement.snapshot()
	invalid(world,base,func(d): d.projects.erase("workbench"), "building work requires its funded project record")
	invalid(world,base,func(d): d.projects.workbench.progress = 5.0, "job and shared construction progress must agree")
	invalid(world,base,func(d): d.projects.workbench.status = "completed", "incomplete construction cannot carry a completed status")
	world = fixture(true)
	world._progression._add_items({"fruta":2})
	var bed := Layout.stand_at("bed","ines")
	place(world,"ines","ines",bed)
	place(world,"player","ines",bed+Vector2(20,0))
	expect(world.start_sleep("ines",60), "order recipient sleeps in her actual bed")
	wallet = world.progression_state()
	var trust: float = world.get_resident("ines").relationships.player.trust
	var unchanged: Dictionary = world.get_resident("ines").relationships.player.duplicate(true)
	for _attempt in range(4):
		world.settlement_jobs.request("ines","gather:fallen_branches")
		world.minute += 5
	expect(world.get_resident("ines").relationships.player == unchanged and world.settlement.state.inhabitants.ines.requests.is_empty(), "requests made while a resident sleeps never create emotional pressure")
	expect(not world.settlement.deliver_order("cafe_fruit").ok and world.progression_state() == wallet and world.get_resident("ines").relationships.player.trust == trust, "sleeping requester cannot receive, pay for or appreciate an order")
	world.wake_resident("ines")
	world.conversation_holds.append("ines")
	for _attempt in range(4):
		world.settlement_jobs.request("ines","gather:fallen_branches")
		world.minute += 5
	expect(world.get_resident("ines").relationships.player == unchanged and world.settlement.state.inhabitants.ines.requests.is_empty(), "a reserved conversation cannot be interrupted by job-pressure bookkeeping")
	world.conversation_holds.clear()
	expect(world.settlement.deliver_order("cafe_fruit").ok, "the same local order succeeds after its requester wakes")
	world = fixture(true)
	world.minute = 600
	spec = world.settlement.task_spec("explore:survey_forest","lupita")
	place(world,"lupita",spec.room,Layout.point(spec.at))
	expect(world.settlement_jobs.request("lupita",spec.id).ok, "explorer begins a real unlocked survey")
	world.on_arrival("lupita")
	world.settlement_jobs.tick()
	for _step in range(4): world.settlement_jobs.tick()
	expect(world.settlement.state.jobs.lupita.phase == "returning" and "survey_forest" not in world.settlement.state.discoveries, "unreported exploration stays with the returning worker")
	var board: Dictionary = world.settlement.catalog.board
	var board_at := Layout.point(board.at)
	place(world,"lupita",board.area,board_at)
	place(world,"player",board.area,board_at+Vector2(18,0))
	place(world,"ines",board.area,Vector2(90,260))
	place(world,"mateo","mateo",board_at)
	var distant_count: int = world.get_resident("ines").memories.size()
	var other_room_count: int = world.get_resident("mateo").memories.size()
	world.settlement_jobs.tick()
	expect(not world.settlement_jobs.busy("lupita") and "survey_forest" in world.settlement.state.discoveries, "survey is committed after the explorer returns to the board")
	var report: Dictionary = world.get_resident("player").memories.back()
	var own: Dictionary = world.get_resident("lupita").memories.back()
	expect(report.kind == "exploracion" and report.get("heard_from","") == "lupita" and report.get("epistemic_status","") == "testimonio_no_verificado", "nearby witness receives a sourced testimony, not a verified terrain observation")
	expect(report.minute == world.minute and report.origin.contains("Lupita") and not report.heard_text.is_empty(), "report retains its actual speaker, wording and time")
	expect(own.kind == "exploracion" and own.get("heard_from","") == "" and own.origin == "actividad presencial verificada", "the explorer retains her own verified experience")
	expect(world.get_resident("ines").memories.size() == distant_count and world.get_resident("mateo").memories.size() == other_room_count, "faraway and other-room residents do not receive the report")
	expect(world.save_game(), "report provenance and completed exploration remain save-compatible")
	world = fixture()
	var arrival_area: String = Layout.home_area("cesar")
	var entrance: Dictionary = Layout.exits(arrival_area)[0]
	var expected_spawn: Vector2 = Navigation.recover_position(entrance.at - entrance.direction * 20.0, arrival_area)
	place(world,"player",arrival_area,expected_spawn)
	var original_position: Array = world.get_resident("player").pos.duplicate()
	world.settlement._arrive("cesar")
	var arrival_position := Layout.point(world.get_resident("cesar").pos)
	expect(world.is_present("cesar") and Navigation.is_walkable(arrival_position,arrival_area), "a returning resident is placed on real navigable ground")
	expect(((arrival_position-expected_spawn)/Vector2(16,14)).length_squared() >= 1 and world.get_resident("player").pos == original_position, "occupied arrival chooses a separate point without moving the waiting player")
	for path in paths:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("RESULT: %d/%d settlement integrity checks" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
