extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures: Array[String] = []
var path := "user://test_sleep_%d.json" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func place(world, id: String, room: String, at: Vector2) -> Dictionary:
	var person: Dictionary = world.get_resident(id)
	person.room = room
	person.pos = [at.x, at.y]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	return person

func cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func run() -> void:
	cleanup()
	var world = Colony.new()
	world.setup(false, true)
	world.save_path = path
	var bed: Vector2 = Layout.stand_at("bed", "player")
	expect(not world.start_sleep("player", 480), "cannot sleep on the street")
	place(world, "player", "cesar", bed)
	expect(not world.start_sleep("player", 480), "cannot use a neighbor's bed")
	var player: Dictionary = place(world, "player", "player", Layout.point(Layout.data().entry))
	expect(not world.start_sleep("player", 480), "must physically reach own bed")
	player = place(world, "player", "player", bed)
	player.target = Layout.data().entry.duplicate()
	expect(not world.start_sleep("player", 480), "a pending walk must settle before sleeping")
	player.target = player.pos.duplicate()
	world.conversation_holds.assign(["player"])
	expect(not world.start_sleep("player", 480), "conversation reservation prevents sleep")
	world.conversation_holds.clear()
	for duration in [-1, 0, 4, 901]:
		expect(not world.start_sleep("player", duration), "reject invalid sleep duration %d" % duration)
	player.energy = 20.0
	world.minute = 23 * 60
	var start_pos: Array = player.pos.duplicate()
	expect(world.start_sleep("player", 480), "bed starts an eight hour sleep")
	expect(world.is_sleeping("player") and player.sleep.until == 1860 and player.sleep.started == 1380, "sleep spans midnight and records absolute simulation times")
	expect(player.pos == start_pos and player.target == start_pos and world.player_energy() == 20.0, "starting sleep neither teleports nor instantly grants energy")
	expect(not world.start_sleep("player", 60), "repeated activation cannot reset the deadline")
	expect(not world.decision_due("player") and not world.apply_decision("player", "plaza"), "sleeping resident refuses AI movement decisions")
	place(world, "cesar", "player", bed + Vector2(10, 0))
	expect(not world.record_dialogue("player", "cesar", "Hola", "Hola", "Prueba"), "sleeping characters cannot record a completed conversation")
	world.tick(false)
	expect(is_equal_approx(world.player_energy(), 21.25), "five minutes asleep restore 1.25 energy")
	expect(world.save_game(), "active sleep is saved atomically")
	var reopened = Colony.new()
	reopened.setup(false, true)
	reopened.save_path = path
	expect(reopened.load_game() and reopened.is_sleeping("player"), "loading preserves valid sleep")
	expect(reopened.minute == world.minute and reopened.player_energy() == world.player_energy(), "loading does not invent offline time or recovery")
	expect(reopened.get_resident("player").sleep.until == 1860, "loading retains the original wake deadline")
	var original: String = FileAccess.get_file_as_string(path)
	for invalid in [{"started": -1, "until": 1860}, {"started": 1380, "until": 9000}, {"started": "1380", "until": 1860}, {"started": 1380, "until": 1381}, false]:
		player.sleep = invalid
		expect(not world.save_game() and FileAccess.get_file_as_string(path) == original, "invalid sleep cannot replace the previous save")
	world = reopened
	player = world.get_resident("player")
	for _tick in range(95): world.tick(false)
	expect(world.minute == 1860 and not world.is_sleeping("player"), "sleep ends at the chosen morning without an extra tick")
	expect(world.player_energy() == 100.0 and player.pos == start_pos, "eight hours recover energy with an upper limit and leave a walkable bedside position")
	player.energy = 15.0
	expect(world.start_sleep("player", 60) and world.wake_resident("player"), "player can wake immediately from a nap")
	expect(world.player_energy() == 15.0 and not world.is_sleeping("player"), "waking early awards no free energy")
	expect(not world.wake_resident("player"), "waking an awake player is harmless")
	cleanup()
	print("SLEEP: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
