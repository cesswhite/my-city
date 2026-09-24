extends SceneTree
## Orchestration tests only: every dialogue start and AI scheduler dispatch is captured in memory.
## Run with --ui-test. No server, HTTP fixture, provider API, or real save is used.

class MainProbe:
	extends "res://scripts/main.gd"
	var dialogue_calls: Array[Dictionary] = []
	var decision_times: Array[float] = []
	var simulated_real_time: float = 0.0
	var inspect_real_selector: bool = false

	func request_dialogue(resident_id: String, speaker_id: String, utterance: String) -> void:
		if dialogue_job.is_empty(): return
		dialogue_calls.append({"resident_id": resident_id, "speaker_id": speaker_id, "utterance": utterance, "serial": dialogue_job.get("serial", -1)})
		stream_text = ""
		stream_prefix = colony.get_resident(resident_id).name + ": "
		dialogue_request.metrics = {"ttft_ms": 10, "total_ms": 30}

	func decide_with_jev() -> void:
		decision_times.append(simulated_real_time)
		if inspect_real_selector:
			# Tests install a future decision_after for every resident, so super stops before HTTP.
			super.decide_with_jev()

var checks: int = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func fixture() -> MainProbe:
	var scene = MainProbe.new()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0 # Keep transport/lifecycle assertions deterministic.
	scene.set_process(false)
	scene.controls_active = false
	scene.service_token = "offline-test-never-sent"
	# Even an accidental regression past our capture must not address a network host.
	scene.service_url = ""
	return scene

func place_pair(scene, first: String, second: String, point: Array = [236.0, 210.0]):
	for resident in scene.colony.residents:
		resident.room = resident.id
		resident.pos = [88.0, 212.0]
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	for id in [first, second]:
		var resident: Dictionary = scene.colony.get_resident(id)
		resident.room = "street"
		resident.pos = point.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""

func answer(action: String) -> PackedByteArray:
	return JSON.stringify({"action": action, "source": "jev", "confidence": 0.9}).to_utf8_buffer()

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("This isolated test requires -- --ui-test; refusing to load real user progress.")
		quit(1)
		return
	var scene = fixture()
	await process_frame
	expect(scene.preview_mode and scene.paused, "fixture uses isolated UI mode with automatic processing stopped")
	scene.toggle_autonomy()
	scene.paused = true
	place_pair(scene, "player", "lupita")
	var player: Dictionary = scene.colony.get_resident("player")
	var neighbor: Dictionary = scene.colony.get_resident("lupita")
	player.target = [386.0, 178.0]
	player.travel_intent = "taller"
	scene.use_jev = true
	scene.decision_pending = true
	scene.deciding_id = "player"
	scene.deciding_epoch = scene.control_epoch
	var epoch_before: int = scene.control_epoch
	scene.take_control()
	expect(not scene.decision_pending and not scene.colony.player_autonomy, "taking control cancels the pending player Jev decision")
	expect(scene.control_epoch > epoch_before and player.target == player.pos and player.travel_intent.is_empty(), "takeover advances epoch and stops the autonomous route")
	scene._decision_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), answer("taller"))
	expect(player.target == player.pos, "late callback after cancellation cannot move the manual player")
	scene.toggle_autonomy()
	scene.paused = true
	place_pair(scene, "player", "lupita")
	scene.decision_pending = true
	scene.deciding_id = "player"
	scene.deciding_epoch = scene.control_epoch - 1
	scene._decision_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), answer("taller"))
	expect(not scene.decision_pending and player.target == player.pos, "obsolete epoch is ignored even after autonomy was enabled again")
	expect(scene.dialogue_calls.is_empty(), "decision cancellation and epoch checks issue no dialogue request")

	var neighbor_goal: Array = scene.colony.PLACES.huerto.duplicate()
	var player_memories: int = player.memories.size()
	var neighbor_memories: int = neighbor.memories.size()
	var first_admitted: bool = scene.begin_npc_dialogue("player")
	expect(first_admitted, "autonomous player can open a nearby conversation")
	if not first_admitted:
		scene.free()
		quit(1)
		return
	expect(scene.dialogue_calls.size() == 1 and scene.dialogue_job.phase == "opening", "opening starts exactly one captured request")
	expect("player" in scene.colony.conversation_holds and "lupita" in scene.colony.conversation_holds, "both automatic participants are reserved from local activities")
	# Admit only idle neighbors, then simulate a routine change during their stream.
	player.target = [110.0, 178.0]
	player.travel_intent = "cafe"
	neighbor.target = neighbor_goal.duplicate()
	neighbor.travel_intent = "huerto"
	scene.freeze_conversation()
	expect(player.target == player.pos and neighbor.target == neighbor.pos and player.travel_intent.is_empty(), "conversation suspends routes and portal intents")
	scene._dialogue_delta("Apertura parcial que no debe guardarse")
	scene._dialogue_completed({"text": "Apertura completa antes de tomar control.", "source": "openai"})
	expect(scene.dialogue_job.phase == "reply" and scene.dialogue_calls.size() == 1, "opening completion defers the second request")
	scene.take_control()
	await process_frame
	expect(scene.dialogue_job.is_empty() and scene.dialogue_calls.size() == 1, "takeover between opening and deferred reply prevents a second request")
	expect(scene.colony.conversation_holds.is_empty(), "cancelled automatic dialogue releases both participant reservations")
	expect(player.memories.size() == player_memories and neighbor.memories.size() == neighbor_memories, "cancelled or partial conversation creates no participant memory")
	expect(neighbor.target == neighbor_goal and neighbor.travel_intent == "huerto", "cancelled conversation resumes the other resident's route")
	expect(player.target == player.pos and player.travel_intent.is_empty(), "cancelled conversation keeps the player under manual control")

	# Queue one old reply, cancel it, and create a new job before deferred callbacks drain.
	scene.toggle_autonomy()
	scene.paused = true
	place_pair(scene, "player", "lupita")
	var obsolete_admitted: bool = scene.begin_npc_dialogue("player")
	expect(obsolete_admitted, "cancelled conversation can be replaced without a false completed-exchange cooldown")
	if not obsolete_admitted:
		scene.free()
		quit(1)
		return
	var obsolete_serial: int = scene.dialogue_job.serial
	scene._dialogue_completed({"text": "Apertura del trabajo anterior.", "source": "openai"})
	scene.take_control()
	scene.toggle_autonomy()
	scene.paused = true
	place_pair(scene, "player", "lupita")
	var replacement_admitted: bool = scene.begin_npc_dialogue("player")
	expect(replacement_admitted, "a second cancelled opening releases its pair for a new job")
	if not replacement_admitted:
		scene.free()
		quit(1)
		return
	player.target = [110.0, 178.0]
	player.travel_intent = "cafe"
	neighbor.target = scene.colony.PLACES.huerto.duplicate()
	neighbor.travel_intent = "huerto"
	scene.freeze_conversation()
	var new_serial: int = scene.dialogue_job.serial
	var calls_before_drain: int = scene.dialogue_calls.size()
	await process_frame
	expect(new_serial > obsolete_serial and scene.dialogue_job.serial == new_serial, "new conversation has a distinct monotonically increasing serial")
	expect(scene.dialogue_calls.size() == calls_before_drain and scene.dialogue_job.phase == "opening", "old deferred reply cannot reuse a newer conversation job")
	scene.continue_npc_dialogue(obsolete_serial)
	expect(scene.dialogue_calls.size() == calls_before_drain, "explicit stale serial also cannot dispatch a request")
	scene._dialogue_completed({"text": "Apertura válida de la nueva conversación.", "source": "openai"})
	await process_frame
	expect(scene.dialogue_calls.size() == calls_before_drain + 1, "current serial dispatches exactly its own reply")
	expect(scene.dialogue_calls.back().serial == new_serial and scene.dialogue_calls.back().resident_id == "lupita", "reply belongs to the new job and correct respondent")
	scene._dialogue_completed({"text": "Respuesta válida y completa de Lupita.", "source": "openai"})
	expect(scene.dialogue_job.is_empty() and player.memories.size() == player_memories + 1 and neighbor.memories.size() == neighbor_memories + 1, "only a complete current conversation records one memory per participant")
	expect(scene.colony.conversation_holds.is_empty(), "completed automatic dialogue releases both participants")
	expect(not str(player.memories.back().content).contains("trabajo anterior"), "completed memory excludes discarded opening text")
	expect(player.target == [110.0, 178.0] and neighbor.target == scene.colony.PLACES.huerto.duplicate(), "successful conversation resumes both original routes")

	# A pending home arrival must not fire while its owner is speaking at the door.
	place_pair(scene, "player", "cesar", scene.colony.HOME_DOORS.cesar)
	var cesar: Dictionary = scene.colony.get_resident("cesar")
	expect(not scene.begin_npc_dialogue("player"), "recent conversation cooldown prevents immediately starting with another partner")
	scene.colony.minute += 60
	var door_admitted: bool = scene.begin_npc_dialogue("player")
	expect(door_admitted, "a stationary door encounter is admitted after the real social cooldown")
	if not door_admitted:
		scene.free()
		quit(1)
		return
	cesar.travel_intent = "casa"
	cesar.target = scene.colony.HOME_DOORS.cesar.duplicate()
	scene.freeze_conversation()
	scene.colony.on_arrival("cesar")
	expect(cesar.room == "street" and cesar.travel_intent.is_empty(), "frozen conversation prevents an accidental house transition")
	# A changed routine is refreshed into the stored goal before the stream finishes.
	cesar.target = [386.0, 178.0]
	cesar.travel_intent = "taller"
	scene.freeze_conversation()
	scene._dialogue_failed("Synthetic interruption without network")
	expect(cesar.target == [386.0, 178.0] and cesar.travel_intent == "taller", "failed conversation resumes the latest routine rather than stale home intent")
	expect(scene.colony.conversation_holds.is_empty(), "failed automatic dialogue releases its reservations")

	scene.take_control()
	place_pair(scene, "player", "cesar")
	var manual_calls: int = scene.dialogue_calls.size()
	expect(not scene.begin_npc_dialogue("player"), "manual player cannot be the automatic opening speaker")
	expect(not scene.begin_npc_dialogue("cesar"), "manual player is excluded as the only nearby automatic partner")
	expect(scene.dialogue_calls.size() == manual_calls, "excluded manual player causes no captured dialogue request")
	scene.inspect_real_selector = true
	scene.decision_pending = false
	scene.decision_index = 0
	for resident in scene.colony.residents: scene.decision_after[resident.id] = scene.colony.minute + 1000000
	var manual_selection: Array[String] = []
	for index in range(8):
		scene.decide_with_jev()
		manual_selection.append(scene.deciding_id)
	expect("player" not in manual_selection, "real Jev candidate selector excludes manual player before HTTP boundary")
	scene.toggle_autonomy()
	scene.paused = true
	scene.decision_index = 0
	var autonomous_selection: Array[String] = []
	for index in range(6):
		scene.decide_with_jev()
		autonomous_selection.append(scene.deciding_id)
	expect("player" in autonomous_selection, "real Jev candidate selector includes opted-in player")
	# Physical sleep excludes both an opening speaker and an otherwise nearby partner.
	place_pair(scene, "cesar", "lupita")
	var bed: Vector2 = scene.WorldLayout.stand_at("bed", "cesar")
	cesar.room = "cesar"
	cesar.pos = [bed.x, bed.y]
	cesar.target = cesar.pos.duplicate()
	neighbor.room = "cesar"
	neighbor.pos = [bed.x + 4, bed.y]
	neighbor.target = neighbor.pos.duplicate()
	var calls_before_sleep: int = scene.dialogue_calls.size()
	expect(scene.colony.start_sleep("cesar", 60), "sleep exclusion fixture starts real rest at the resident's own bed")
	expect(not scene.begin_npc_dialogue("cesar") and not scene.begin_npc_dialogue("lupita") and scene.dialogue_calls.size() == calls_before_sleep, "sleeping residents cannot open or receive automatic conversations")
	scene.colony.wake_resident("cesar")
	var awake_admitted: bool = scene.begin_npc_dialogue("cesar")
	expect(awake_admitted, "the same idle pair may converse after the sleeper wakes")
	if awake_admitted: scene._dialogue_failed("Fixture completed without a provider")
	scene.queue_free()
	await process_frame

	var counts: Dictionary = {}
	var clock_advances: Dictionary = {}
	for speed in [1.0, 4.0]:
		var paced = fixture()
		paced.paused = false
		paced.use_jev = true
		paced.time_speed = speed
		paced.decision_pending = true
		paced.elapsed = 0.0
		paced.ai_cooldown = 0.0
		var original_minute: int = paced.colony.minute
		for frame in range(120):
			paced.simulated_real_time += 0.1
			paced._process(0.1)
		counts[speed] = paced.decision_times.size()
		clock_advances[speed] = paced.colony.minute - original_minute
		for index in range(1, paced.decision_times.size()):
			expect(paced.decision_times[index] - paced.decision_times[index - 1] >= 3.99, "%.0f× world keeps at least four real seconds between AI dispatch opportunities" % speed)
		expect(paced.decision_times.size() <= 3, "%.0f× world permits at most three AI dispatch opportunities in twelve real seconds" % speed)
		expect(paced.dialogue_calls.is_empty(), "budget probe never starts provider dialogue")
		paced.queue_free()
		await process_frame
	expect(clock_advances[4.0] >= clock_advances[1.0] * 3, "4× advances the world clock faster during the same real interval")
	expect(counts[4.0] <= counts[1.0] + 1, "4× world speed does not multiply the AI request budget")
	print("AUTONOMY AI: %d/%d isolated checks passed; no network or provider calls." % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
