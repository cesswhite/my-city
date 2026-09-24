extends SceneTree
## Isolated, deterministic invitations: no Main, network transport or user save.
const Colony = preload("res://scripts/colony.gd")
var checks := 0
var failures := 0
var rolls := 0
var roll_value := 0.0
var path := "user://test_chat_willingness_%d.json" % OS.get_process_id()

func _init() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func roll() -> float:
	rolls += 1
	return roll_value

func fresh():
	var world = Colony.new()
	world.save_path = path
	world.setup(false, true)
	rolls = 0
	roll_value = 0.0
	world._social._willingness_roll = roll
	var positions := {"player":[310.0,200.0],"cesar":[328.0,200.0],"lupita":[328.0,218.0],"mateo":[310.0,218.0]}
	for id in positions:
		var person: Dictionary = world.get_resident(id)
		person.room = "street"
		person.pos = positions[id].duplicate()
		person.target = person.pos.duplicate()
	return world

func relation(world, owner: String = "cesar", partner: String = "player") -> Dictionary:
	return world.get_resident(owner).relationships[partner]

func availability(world, owner: String = "cesar") -> Dictionary:
	return world.get_resident(owner).chat_availability

func clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))

func write_fixture(payload: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Pass -- --ui-test for this isolated fixture.")
		quit(1)
		return
	clean()
	var world = fresh()
	check(availability(world) == {"until":0,"declined":false,"notified":[],"line":0},"new NPC starts with neutral, bounded availability")
	relation(world).trust = 85.0
	relation(world).affection = 80.0
	var friends: Dictionary = relation(world).duplicate(true)
	var inverse: Dictionary = relation(world,"player","cesar").duplicate(true)
	var third: Dictionary = relation(world,"cesar","lupita").duplicate(true)
	var memories: Array = world.get_resident("cesar").memories.duplicate(true)
	var events: Array = world.events.duplicate()
	var serial: int = world._serial
	# Refusing an invitation must leave the NPC free to continue its actual route.
	world.get_resident("cesar").target = [340.0,200.0]
	var pos: Array = world.get_resident("cesar").pos.duplicate()
	var goal: Array = world.get_resident("cesar").target.duplicate()
	var first: Dictionary = world.social_start("cesar","player")
	check(not first.allowed and first.end and first.get("reason","") == "unavailable" and not first.reply.is_empty(),"good friends can decline a first invitation with a brief reply")
	check(rolls == 1 and availability(world).declined and availability(world).until == world.minute+45,"one local roll caches a forty-five-minute refusal")
	check(availability(world).notified == ["player"] and relation(world) == friends,"first refusal is neutral rather than relationship damage")
	check(world._social._sessions.is_empty() and world.conversation_holds.is_empty(),"refusal creates no conversation session or reservation")
	check(world.get_resident("cesar").pos == pos and world.get_resident("cesar").target == goal,"refusal does not move or freeze the NPC route")
	check(world.get_resident("cesar").memories == memories and world.events == events and world._serial == serial,"unspoken invitation does not fabricate dialogue memories")
	check(relation(world,"player","cesar") == inverse and relation(world,"cesar","lupita") == third,"availability does not alter reverse or third-party relationships")

	var repeat: Dictionary = world.social_start("cesar","player")
	check(not repeat.allowed and repeat.get("reason","") == "availability_pressure","insisting after the same refusal remains a refusal")
	check(relation(world).frustration == friends.frustration+8 and relation(world).tolerance == friends.tolerance-6 and relation(world).cooldown_until >= world.minute+30,"confirmed recontact applies pressure once")
	var pressured: Dictionary = relation(world).duplicate(true)
	for attempt in range(8): world.social_start("cesar","player")
	check(relation(world) == pressured and rolls == 1,"eight retries in the same minute do not multiply damage or reroll")
	check(relation(world).trust == friends.trust and relation(world).affection == friends.affection,"temporary refusal and pressure do not invent loss of trust or affection")
	var neighbor: Dictionary = world.social_start("cesar","lupita")
	check(not neighbor.allowed and neighbor.get("reason","") == "unavailable" and relation(world,"cesar","lupita") == third,"first invitation from a third neighbor is independently neutral")
	check(availability(world).notified.size() == 2 and rolls == 1,"existing refusal notifies a new neighbor without another lottery")

	# Read-only encounter queries honor the refusal without consuming a draw or pressure.
	world.get_resident("cesar").target = world.get_resident("cesar").pos.duplicate()
	var snapshot: String = JSON.stringify(world.residents)
	for index in range(6):
		check(not world.social_available("cesar") and world.greeting_pair("cesar","mateo").first.is_empty(),"ambient encounter query honors unavailability, pass %d" % index)
	check(JSON.stringify(world.residents) == snapshot and rolls == 1,"availability polling is read-only and never calls random or provider code")

	world = fresh()
	check(world.social_start("player","cesar").allowed and rolls == 0,"player-owned social state never rolls a random refusal")
	world.social_finish("player","cesar")
	relation(world).cooldown_until = world.minute+30
	var before_limits: Dictionary = availability(world).duplicate(true)
	check(not world.social_start("cesar","player").allowed and rolls == 0 and availability(world) == before_limits,"relationship boundaries take priority over willingness lottery")
	world = fresh()
	var npc_relationship: Dictionary = relation(world,"cesar","lupita").duplicate(true)
	check(not world.social_start("cesar","lupita").allowed and rolls == 1 and relation(world,"cesar","lupita") == npc_relationship,"neighbor-to-neighbor invitation can decline neutrally using the same local lottery")
	check(availability(world).notified == ["lupita"] and world._social._sessions.is_empty(),"NPC refusal reserves no session and remembers only the actual inviter")
	world = fresh()
	world.minute = 0
	world.social_start("cesar","player")
	var minute_zero: Dictionary = relation(world).duplicate(true)
	check(world.social_start("cesar","player").get("reason","") == "availability_pressure" and relation(world).frustration == minute_zero.frustration+8 and relation(world).tolerance == minute_zero.tolerance-6,"first pressure at minute zero is not mistaken for an already counted retry")
	var zero_pressure: Dictionary = relation(world).duplicate(true)
	world.social_start("cesar","player")
	check(relation(world) == zero_pressure,"subsequent pressure at minute zero is deduplicated normally")

	world = fresh()
	var trust_before_space: float = relation(world).trust
	world.social_start("cesar","player")
	world.minute += 44
	check(not world.social_available("cesar"),"declined availability remains in force before the promised interval")
	world.minute += 1
	var welcomed: Dictionary = world.social_start("cesar","player")
	check(welcomed.allowed and rolls == 1 and not availability(world).declined,"respecting forty-five minutes guarantees the next welcome without reroll")
	check(availability(world).until == world.minute+60 and availability(world).notified.is_empty(),"guaranteed welcome starts a clean sixty-minute acceptance window")
	check(relation(world).trust == trust_before_space and relation(world).frustration == 0,"giving space does not award trust or create resentment")
	world.social_finish("cesar","player")
	check(world.social_start("cesar","player").allowed and rolls == 1,"reopening within accepted window does not reroll")
	world.minute += 61
	check(world.social_start("cesar","player").allowed and rolls == 1,"active session remains accepted even when cached window expires")
	world.social_finish("cesar","player")
	check(not world.social_start("cesar","player").allowed and rolls == 2,"a later new encounter can choose a new temporary refusal")

	world = fresh()
	roll_value = 1.0
	check(world.social_start("cesar","player").allowed and rolls == 1 and availability(world).until == world.minute+60,"roll one accepts and caches the invitation")
	world.social_finish("cesar","player")
	roll_value = 0.0
	check(world.social_start("cesar","player").allowed and rolls == 1,"accepted window survives a subsequent rejecting test roll")

	# A postponed meeting cannot bypass an outstanding boundary from later insistence.
	world = fresh()
	world.social_start("cesar","player")
	world.minute += 40
	world.social_start("cesar","player")
	world.minute += 5
	check(not world.social_start("cesar","player").allowed and rolls == 1,"expired availability still respects a newer relationship cooldown")

	# Persist real prior memories together with a declined window; relaunch cannot reroll it.
	world = fresh()
	roll_value = 1.0
	world.social_start("cesar","player")
	check(world.record_dialogue("player","cesar","Hola, ¿cómo va tu mañana?","Estoy paseando junto al jardín.","Prueba local aislada"),"fixture commits one actual exchange before persistence")
	world.social_finish("cesar","player")
	world.minute += 61
	roll_value = 0.0
	check(not world.social_start("cesar","player").allowed,"fixture has a genuine new declined encounter")
	check(world.save_game(),"availability and existing memories save atomically")
	var stored: String = FileAccess.get_file_as_string(path)
	var payload: Dictionary = JSON.parse_string(stored)
	var expected: Dictionary = JSON.parse_string(JSON.stringify(availability(world)))
	var expected_memories: String = JSON.stringify(payload.residents[0].memories)
	var restored = fresh()
	check(restored.load_game() and availability(restored) == expected,"declined window survives reload with its original deadline and notified IDs")
	check(JSON.stringify(restored.get_resident("cesar").memories) == expected_memories,"reloading availability preserves previous dialogue and provenance")
	check(not restored.social_start("cesar","player").allowed and rolls == 0,"restarting does not reroll or erase an already communicated refusal")
	# Invalid runtime values must never overwrite the last validated file.
	for invalid in [
		{"until":-1,"declined":false,"notified":[],"line":0},
		{"until":0.5,"declined":false,"notified":[],"line":0},
		{"until":NAN,"declined":false,"notified":[],"line":0},
		{"until":INF,"declined":false,"notified":[],"line":0},
		{"until":0,"declined":"false","notified":[],"line":0},
		{"until":0,"declined":false,"notified":["intruso"],"line":0},
		{"until":0,"declined":false,"notified":["player","player"],"line":0},
		{"until":0,"declined":false,"notified":[],"line":-1}
	]:
		restored.get_resident("cesar").chat_availability = invalid.duplicate(true)
		check(not restored.save_game() and FileAccess.get_file_as_string(path) == stored,"invalid availability rejects save without overwriting, case %d" % checks)
	# Corrupt input is rejected before replacing in-memory residents.
	var corrupt: Dictionary = payload.duplicate(true)
	corrupt.residents[0].chat_availability.notified = ["intruso"]
	write_fixture(corrupt)
	var stable = fresh()
	var stable_snapshot: String = JSON.stringify(stable.residents)
	check(not stable.load_game() and JSON.stringify(stable.residents) == stable_snapshot,"invalid availability in a save cannot replace the live world")
	# Optional field keeps the existing save version and memories compatible.
	for person: Dictionary in payload.residents: person.erase("chat_availability")
	write_fixture(payload)
	check(stable.load_game() and availability(stable) == {"until":0,"declined":false,"notified":[],"line":0},"old saves migrate the missing field to neutral availability")
	check(JSON.stringify(stable.get_resident("cesar").memories) == expected_memories and stable.save_game(),"migration retains dialogue and can produce a new valid save")
	check(not stable.context_for("cesar","player").has("chat_availability") and stable.context_for("cesar","player").relationship.size() == 7,"availability does not expand or leak into the model relationship schema")
	clean()
	print("CHAT WILLINGNESS: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
