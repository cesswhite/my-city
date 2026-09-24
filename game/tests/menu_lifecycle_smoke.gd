extends SceneTree
## Isolated lifecycle fixture. Run with -- --ui-test; no providers or user save access.

class MainProbe:
	extends "res://scripts/main.gd"
	var dialogue_calls: Array[Dictionary] = []
	var decision_calls := 0

	func request_dialogue(resident_id: String, speaker_id: String, utterance: String) -> void:
		if dialogue_job.is_empty(): return
		dialogue_calls.append({"resident": resident_id, "speaker": speaker_id, "utterance": utterance})
		dialogue_request._reset_state()
		dialogue_request.busy = true
		dialogue_request.set_process(false)

	func decide_with_jev() -> void:
		decision_calls += 1

var checks := 0
var failures: Array[String] = []
var menu_requests := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func fixture() -> MainProbe:
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = "user://test_menu_lifecycle_%d.json" % OS.get_process_id()
	scene.menu_requested.connect(func(): menu_requests += 1)
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0 # Acceptance is deterministic; cancellation remains real.
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = "offline-fixture-never-sent"
	scene.service_url = ""
	scene.use_jev = false
	return scene

func place_pair(scene, first: String, second: String) -> void:
	for resident in scene.colony.residents:
		resident.room = resident.id
		resident.pos = [180.0, 240.0]
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	for id in [first, second]:
		var resident: Dictionary = scene.colony.get_resident(id)
		resident.room = "street"
		resident.pos = [280.0 if id == first else 296.0, 200.0]
		resident.target = resident.pos.duplicate()
	scene.paths.clear()
	scene.update_room()

func escape(scene, repeated: bool = false) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	key.echo = repeated
	scene._input(key)

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Requires -- --ui-test; refusing to access real progress.")
		quit(1)
		return
	if DisplayServer.get_name() == "headless": root.size = Vector2i(768, 432)
	var scene := fixture()
	await process_frame
	expect(scene.preview_mode and scene.managed_by_shell and scene.start_new_game, "shell fixture is isolated before scene readiness")
	place_pair(scene, "player", "mateo")
	var player: Dictionary = scene.colony.get_resident("player")
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	var colony_instance: int = scene.colony.get_instance_id()
	var player_memories: int = player.memories.size()
	var mateo_memories: int = mateo.memories.size()
	mateo.target = scene.colony.PLACES.taller.duplicate()
	mateo.travel_intent = "taller"
	scene.selected_id = "mateo"
	scene.page = "hablar"
	scene.build_inspector()
	scene.send_chat_text("¿Qué reparación recuerdas?")
	scene._dialogue_delta("Una respuesta todavía incompleta")
	scene.chat_input.text = "Mi siguiente pregunta sigue aquí"
	scene.chat_drafts.lupita = "Borrador para Lupita"
	scene.paused = false
	scene.time_speed = 4.0
	var epoch: int = scene.control_epoch
	var serial: int = scene.dialogue_serial
	var minute: int = scene.colony.minute
	var elapsed: float = scene.elapsed
	var point: Array = player.pos.duplicate()
	Input.action_press("city_right")
	Input.action_press("city_interact")
	scene.suspend_for_menu()
	expect(not scene.visible and not scene.is_processing() and not scene.is_processing_input(), "suspension hides the scene and disables frame and keyboard processing")
	expect(scene.paused and not scene.controls_active and not scene.keyboard_walking, "suspension freezes clock and movement controls")
	expect(not Input.is_action_pressed("city_right") and not Input.is_action_pressed("city_interact"), "held movement and interaction keys are released")
	expect(scene.dialogue_job.is_empty() and not scene.dialogue_request.busy, "manual stream is cancelled before its incomplete reply can finish")
	expect(scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty(), "manual conversation reservations are released")
	expect(mateo.target == scene.colony.PLACES.taller and mateo.travel_intent == "taller", "the neighbor recovers his saved routine before the job is cleared")
	expect(str(scene.chat_drafts.get("mateo", "")).is_empty() and scene.chat_drafts.lupita == "Borrador para Lupita", "ending the encounter clears its draft without touching another prepared message")
	expect(scene.control_epoch > epoch and scene.dialogue_serial > serial, "suspension invalidates pending control and deferred dialogue generations")
	scene._dialogue_completed({"text": "Late completion must never be remembered", "source": "openai"})
	scene._dialogue_delta("Late partial text")
	scene.complete_local_chat(serial, "Late local completion")
	scene._process(20.0)
	await process_frame
	await process_frame
	expect(scene.colony.minute == minute and scene.elapsed == elapsed and player.pos == point, "real frames and stale frame calls cannot advance a suspended world")
	expect(player.memories.size() == player_memories and mateo.memories.size() == mateo_memories, "cancelled or late dialogue never writes partial memories")
	scene._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	expect(not scene.controls_active, "window focus cannot reactivate a suspended scene")
	scene.suspend_for_menu()
	var calls: int = scene.dialogue_calls.size()
	scene.resume_from_menu()
	expect(scene.visible and scene.is_processing() and scene.is_processing_input() and not scene.paused, "resume restores visibility, processing and the original running state")
	expect(scene.colony.get_instance_id() == colony_instance and scene.time_speed == 4.0, "resume keeps the same world and selected clock speed")
	expect(scene.controls_active == scene.get_window().has_focus(), "resume enables controls according to actual window focus")
	expect(scene.chat_input.text.is_empty() and scene.chat_partner_id.is_empty(), "resume presents a clean composer without reopening the old conversation")
	expect(scene.dialogue_calls.size() == calls and scene.decision_calls == 0, "resume itself starts no provider request")
	scene.set_process(false)
	scene.paused = true
	scene.suspend_for_menu()
	scene.resume_from_menu()
	expect(scene.paused, "a previously paused world stays paused after resume")
	scene.set_process(false)

	# NPC-only jobs, queued reply continuations, visits and decisions must all stop too.
	place_pair(scene, "cesar", "lupita")
	var cesar: Dictionary = scene.colony.get_resident("cesar")
	var lupita: Dictionary = scene.colony.get_resident("lupita")
	var npc_admitted: bool = scene.begin_npc_dialogue("cesar")
	expect(npc_admitted, "fixture opens an NPC-only conversation while both residents are stationary")
	if not npc_admitted:
		scene.free()
		quit(1)
		return
	# A clock/routine change during the stream is saved and then suspended again.
	cesar.target = scene.colony.PLACES.cafe.duplicate()
	cesar.travel_intent = "cafe"
	lupita.target = scene.colony.PLACES.huerto.duplicate()
	lupita.travel_intent = "huerto"
	scene.freeze_conversation()
	serial = scene.dialogue_job.serial
	scene._dialogue_completed({"text": "Un encuentro sin terminar.", "source": "openai"})
	calls = scene.dialogue_calls.size()
	scene.decision_pending = true
	scene.deciding_id = "alma"
	scene.deciding_epoch = scene.control_epoch
	scene.visit_job = {"home_id": "ines", "signature": "fixture-occupant"}
	var alma_target: Array = scene.colony.get_resident("alma").target.duplicate()
	scene.suspend_for_menu()
	expect(not scene.decision_pending and scene.deciding_id.is_empty() and scene.visit_job.is_empty(), "suspension also cancels NPC decisions and house admission jobs")
	expect(cesar.target == scene.colony.PLACES.cafe and lupita.target == scene.colony.PLACES.huerto, "NPC-only interruption restores both routes")
	expect(cesar.travel_intent == "cafe" and lupita.travel_intent == "huerto", "NPC-only interruption restores both travel intents")
	scene.continue_npc_dialogue(serial)
	scene._decision_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"action": "cafe", "source": "jev"}).to_utf8_buffer())
	scene._visit_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"allowed": true, "source": "jev"}).to_utf8_buffer())
	await process_frame
	expect(scene.dialogue_calls.size() == calls and scene.dialogue_job.is_empty(), "queued NPC reply and explicit stale serial cannot dispatch from the menu")
	expect(scene.colony.get_resident("alma").target == alma_target and player.room == "player", "late decision and visit responses cannot move anyone or grant entry")
	scene._notification(Control.NOTIFICATION_WM_CLOSE_REQUEST)
	expect(not FileAccess.file_exists(scene.colony.save_path), "managed close delegates persistence to the shell and does not write a save")
	scene.resume_from_menu()
	scene.set_process(false)
	place_pair(scene, "player", "mateo")
	scene.selected_id = "mateo"
	scene.page = "hablar"
	scene.build_inspector()

	# One Escape dismisses the current priority; a separate press requests the menu.
	scene.show_help()
	escape(scene, true)
	expect(is_instance_valid(scene.help_panel) and menu_requests == 0, "held Escape does not close a modal or request the menu")
	escape(scene)
	expect(not is_instance_valid(scene.help_panel) and menu_requests == 0, "Escape closes help before requesting the menu")
	scene.learning.show_journal()
	escape(scene)
	expect(not is_instance_valid(scene.learning.panel) and menu_requests == 0, "Escape closes the learning journal first")
	scene.show_door_panel("player")
	escape(scene)
	expect(not is_instance_valid(scene.door_panel) and menu_requests == 0, "Escape closes the door dialog first")
	scene.chat_input.grab_focus()
	escape(scene)
	expect(not scene.typing_in_field() and menu_requests == 0, "Escape releases a typing field before opening the menu")
	escape(scene)
	expect(menu_requests == 1, "Escape requests the shell menu once no modal or editor owns priority")
	escape(scene, true)
	expect(menu_requests == 1, "Escape echo cannot repeat a menu request")
	scene.managed_by_shell = false
	escape(scene)
	expect(menu_requests == 1, "standalone gameplay retains its existing Escape behavior")
	scene.managed_by_shell = true
	scene.suspend_for_menu()
	escape(scene)
	expect(menu_requests == 1, "hidden suspended gameplay cannot request another menu")
	scene.free()
	await process_frame
	print("MENU LIFECYCLE: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
