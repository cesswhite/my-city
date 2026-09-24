extends SceneTree
## Simulated time and isolated save fixtures only. No UI or provider calls.
const Colony = preload("res://scripts/colony.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures: Array[String] = []
var save_path := "user://test_energy_%d.json" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func fixture():
	var colony = Colony.new()
	colony.save_path = save_path
	colony.setup(false, true)
	return colony

func place(player: Dictionary, room: String, point: Array) -> void:
	player.room = room
	player.pos = point.duplicate()
	player.target = point.duplicate()
	player.travel_intent = ""

func write_save(content: String) -> void:
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))

func run() -> void:
	cleanup()
	var colony = fixture()
	var player: Dictionary = colony.get_resident("player")
	expect(colony.player_energy() == 100.0 and player.energy is float, "new player starts with 100 energy")
	var npc_fields := false
	for resident in colony.residents:
		if resident.id != "player" and resident.has("energy"): npc_fields = true
	expect(not npc_fields, "energy adds no unused neighbor stat")
	for _frame in range(4): await process_frame
	for _read in range(30): colony.player_energy()
	expect(colony.player_energy() == 100.0 and colony.minute == 480, "frames and HUD reads do not drain energy without a simulation tick")
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 99.875) and colony.minute == 485, "one five-minute awake tick costs 0.125 energy")
	for _tick in range(191): colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 76.0), "sixteen simulated awake hours cost 24 energy")
	expect(not colony.context_for("player").has("energy") and not colony.context_for("player").identity.has("energy"), "HUD energy is omitted from model context")

	colony = fixture()
	player = colony.get_resident("player")
	player.energy = 50.0
	place(player, "player", Colony.HOME_REST)
	var point: Array = player.pos.duplicate()
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 50.5), "standing still at the home rest point restores 0.5 per tick")
	expect(player.pos == point and player.target == point, "energy recovery never teleports or changes a destination")
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 51.0), "continued physical rest restores energy each simulated interval")
	player.energy = 99.9
	colony.tick(false)
	expect(colony.player_energy() == 100.0, "rest cannot exceed 100 energy")

	colony = fixture()
	player = colony.get_resident("player")
	player.energy = 20.0
	var bed: Vector2 = Layout.stand_at("bed", "player")
	place(player, "player", [bed.x, bed.y])
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 20.5), "the visible bed interaction point also permits manual rest")
	colony.conversation_holds.assign(["player", "mateo"])
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 20.375), "a reserved conversation at the bedside is awake time")
	colony.conversation_holds.clear()
	player.pos[0] += 4.0
	player.target = player.pos.duplicate()
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 20.25), "actual position changes prevent recovery even when keyboard movement keeps target equal to position")
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 20.75), "recovery resumes once the player stays still near the bed")
	player.target = Colony.ROOM_EXIT.duplicate()
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 20.625), "a pending walk away from the bed prevents recovery")

	for location in ["street", "lupita"]:
		colony = fixture()
		player = colony.get_resident("player")
		player.energy = 30.0
		place(player, location, Colony.HOME_REST)
		player.routine_place = "casa"
		colony.tick(false)
		expect(is_equal_approx(colony.player_energy(), 29.875), "rest coordinates and stale agenda do not recharge outside the own home: " + location)
	colony = fixture()
	player = colony.get_resident("player")
	player.energy = 30.0
	place(player, "player", Colony.ROOM_ENTRY)
	player.routine_place = "casa"
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 29.875), "manual idle time far from the bed is awake even with an old rest label")

	colony = fixture()
	player = colony.get_resident("player")
	player.energy = 30.0
	colony.minute = 60
	place(player, "player", Colony.ROOM_ENTRY)
	colony.set_player_autonomy(true)
	colony.tick(false)
	expect(player.routine_place == "casa" and is_equal_approx(colony.player_energy(), 29.875), "night agenda does not recharge while still walking to the rest point")
	player.pos = player.target.duplicate()
	colony.tick(false)
	expect(is_equal_approx(colony.player_energy(), 29.75), "arrival interval is not mistaken for already stationary rest")
	colony.tick(false)
	expect(colony.is_sleeping("player") and is_equal_approx(colony.player_energy(), 31.0), "autonomous nighttime sleep restores 1.25 per tick after physical bed arrival")
	# Sleep cannot keep charging after an invalid external move away from the bed.
	var before: float = colony.player_energy()
	place(player, "player", Colony.ROOM_ENTRY)
	colony.tick(false)
	colony.tick(false)
	expect(not colony.is_sleeping("player") and is_equal_approx(colony.player_energy(), before - 0.25), "leaving the physical bed stops sleep recovery and requires a new route to bed")

	colony = fixture()
	player = colony.get_resident("player")
	player.energy = 0.05
	colony.tick(false)
	expect(colony.player_energy() == 0.0, "awake drain cannot fall below zero")
	expect(colony.is_exhausted() and colony.is_sleeping("player") and not colony.apply_decision("player", "cafe"), "zero energy starts forced sleep and blocks movement decisions")
	place(player, "street", Colony.PLACES.cafe)
	place(colony.get_resident("ines"), "street", Colony.PLACES.cafe)
	expect(not colony.record_dialogue("player", "ines", "Hola, Inés.", "Hola, qué gusto verte.", "Prueba local sin IA"), "exhausted player cannot record a conversation while asleep")
	var progression: Dictionary = colony.progression_state()
	var tea_quest: String = ""
	for quest: Dictionary in colony.available_apprenticeships():
		if quest.mentor_id == "ines": tea_quest = quest.id
	expect(not tea_quest.is_empty() and not colony.start_apprenticeship(tea_quest).ok and colony.progression_state() == progression, "a late lesson request beside its actual mentor cannot start during exhaustion")
	expect(not colony.wake_resident("player") and not colony.advance_exhaustion(7.0) and colony.player_energy() == 0.0, "forced sleep cannot be ended early or award partial energy")
	expect(colony.advance_exhaustion(1.0) and colony.player_energy() == 5.0 and not colony.is_exhausted(), "eight real seconds wake the player at exactly five percent")
	expect(colony.start_apprenticeship(tea_quest).ok, "the same nearby lesson becomes available after recovering")
	player.energy = 42.375
	expect(colony.save_game(), "fractional energy persists in a valid version-one save")
	var original: String = FileAccess.get_file_as_string(save_path)
	var reopened = fixture()
	expect(reopened.load_game() and is_equal_approx(reopened.player_energy(), 42.375), "loading restores exact fractional energy")
	expect(JSON.parse_string(original).version == 1, "energy requires no broad save version migration")
	for invalid in [-0.01, 100.01, NAN, INF, -INF, "50", true, null]:
		player.energy = invalid
		expect(not colony.save_game() and FileAccess.get_file_as_string(save_path) == original, "invalid runtime energy cannot overwrite a save: " + str(invalid))
	player.energy = 42.375
	var old_payload: Dictionary = JSON.parse_string(original)
	for resident in old_payload.residents:
		if resident.id == "player": resident.erase("energy")
	write_save(JSON.stringify(old_payload))
	expect(reopened.load_game() and reopened.player_energy() == 100.0, "legacy save without energy migrates to 100")
	expect(reopened.save_game() and FileAccess.get_file_as_string(save_path).contains('"energy"'), "the next legacy save persists the migrated field")
	for invalid in [-1.0, 101.0, "50", null]:
		var damaged: Dictionary = JSON.parse_string(original)
		for resident in damaged.residents:
			if resident.id == "player": resident.energy = invalid
		var bad_bytes: String = JSON.stringify(damaged)
		write_save(bad_bytes)
		var prior: float = reopened.player_energy()
		expect(not reopened.load_game() and reopened.player_energy() == prior, "invalid persisted energy is rejected before changing live state: " + str(invalid))
		expect(not reopened.save_game() and FileAccess.get_file_as_string(save_path) == bad_bytes, "rejected energy save remains intact on disk: " + str(invalid))
	write_save(original.replace('"energy": 42.375', '"energy": NaN'))
	expect(not reopened.load_game(), "non-JSON NaN cannot be loaded as energy")
	cleanup()
	print("ENERGY: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
