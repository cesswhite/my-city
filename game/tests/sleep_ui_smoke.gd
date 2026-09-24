extends SceneTree
## Exercise physical sleep through the real scene; every provider entry point is a local probe.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var decision_calls := 0
	var dialogue_calls := 0
	func decide_with_jev() -> void:
		decision_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void:
		dialogue_calls += 1

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func settle() -> void:
	for _frame in range(4): await process_frame

func find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == caption: return child
		var found := find_button(child, caption)
		if found != null: return found
	return null

func click(viewport: SubViewport, button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = button.get_global_rect().get_center()
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)

func press(viewport: SubViewport, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)

func at_bed(scene, energy: float = 35.0) -> Dictionary:
	var player: Dictionary = scene.colony.get_resident("player")
	var bed: Vector2 = Layout.stand_at("bed", "player")
	player.room = "player"
	player.pos = [bed.x, bed.y]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	player.energy = energy
	scene.paths.erase("player")
	scene.update_room()
	scene.get_viewport().gui_release_focus()
	scene.controls_active = true
	return player

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test to avoid loading or saving player progress.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768, 432)
	root.add_child(viewport)
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	viewport.add_child(scene)
	await settle()
	scene.set_process(false)
	scene.service_token = ""
	scene.service_url = ""
	scene.save_allowed = false
	scene.use_jev = false
	var world = scene.colony
	expect(scene.preview_mode and scene.paused and world.minute == 480, "sleep fixture starts isolated with simulation paused")
	expect(not scene.sleep_ui.start(480) and not world.is_sleeping("player"), "a toolbar or stale callback cannot start sleep away from the real bed")
	var player: Dictionary = at_bed(scene)
	scene.paused = false
	press(viewport, KEY_E)
	# Bed interaction may first resolve its already-arrived physical target.
	scene._process(0.1)
	await settle()
	expect(is_instance_valid(scene.sleep_ui.panel) and scene.keyboard_blocked(), "E at the bed opens physical sleep choices and blocks world controls")
	if not is_instance_valid(scene.sleep_ui.panel):
		scene.free()
		viewport.free()
		quit(1)
		return
	var paused_minute: int = world.minute
	for _frame in range(30): scene._process(0.1)
	expect(world.minute == paused_minute and not world.is_sleeping("player"), "choosing a duration pauses time without beginning sleep")
	var morning: Button = find_button(scene.sleep_ui.panel, "Hasta las 7:00")
	expect(morning != null and morning.disabled, "morning option rejects a next-day wait longer than the allowed rest")
	var back: Button = find_button(scene.sleep_ui.panel, "Volver")
	expect(back != null, "duration panel offers a clear cancel action")
	if back != null: click(viewport, back)
	await settle()
	expect(not is_instance_valid(scene.sleep_ui.panel) and not scene.paused and not world.is_sleeping("player"), "cancel restores the original running state without sleeping")
	scene.sleep_ui.show_choices()
	await settle()
	var sleep_button: Button = find_button(scene.sleep_ui.panel, "Dormir 8 horas")
	expect(sleep_button != null, "eight-hour sleep is an explicit button action")
	var started: int = world.minute
	var initial_energy: float = world.player_energy()
	# A pending NPC stream must release its pair before accelerated rest begins.
	var cesar: Dictionary = world.get_resident("cesar")
	var lupita: Dictionary = world.get_resident("lupita")
	var old_memories: int = cesar.memories.size() + lupita.memories.size()
	scene.dialogue_job = {"a": "cesar", "b": "lupita", "first": "Intercambio incompleto", "phase": "reply", "autonomous": true, "serial": -1}
	world.conversation_holds.assign(["cesar", "lupita"])
	scene.freeze_conversation()
	scene.decision_pending = true
	if sleep_button != null: click(viewport, sleep_button)
	await settle()
	expect(world.is_sleeping("player") and player.sleep.started == started and player.sleep.until == started + 480, "sleep button stores an actual eight-hour interval")
	scene._dialogue_completed({"text": "Respuesta tardía que debe descartarse", "source": "openai"})
	expect(scene.dialogue_job.is_empty() and world.conversation_holds.is_empty() and not scene.decision_pending and cesar.memories.size() + lupita.memories.size() == old_memories, "starting sleep cancels pending AI work and releases NPCs without saving a partial conversation")
	expect(world.player_energy() == initial_energy and not scene.paused, "starting sleep restores no energy instantly and lets the colony keep running")
	expect(not is_instance_valid(scene.sleep_ui.panel) and is_instance_valid(scene.sleep_ui.banner) and not scene.keyboard_blocked(), "sleep replaces the modal with a nonblocking status and wake control")
	expect(scene.sleep_ui.progress.size.y == 6 and scene.sleep_ui.banner.get_global_rect().encloses(scene.sleep_ui.progress.get_global_rect()), "sleep progress stays within its six-pixel native track")
	# Acceleration drives ordinary local ticks and navigation; it never multiplies provider work.
	scene.use_jev = true
	var fixed_position: Array = player.pos.duplicate()
	var neighbors_before: Dictionary = {}
	for resident: Dictionary in world.residents:
		if resident.id != "player": neighbors_before[resident.id] = resident.pos.duplicate()
	var walkable := true
	for _frame in range(30):
		scene._process(0.1)
		for resident: Dictionary in world.residents:
			walkable = walkable and Navigation.is_walkable(scene.position_of(resident), resident.room)
	var moved := false
	for resident: Dictionary in world.residents:
		if resident.id != "player" and resident.pos != neighbors_before[resident.id]: moved = true
	expect(world.minute == started + 180 and world.is_sleeping("player"), "three real seconds advance exactly three sleeping hours")
	expect(player.pos == fixed_position and walkable and moved, "sleep holds the player at the bed while neighbors follow walkable routes")
	expect(world.player_energy() > initial_energy and scene.hud.energy_bar.value == world.player_energy(), "local rest ticks recharge the displayed energy")
	expect(scene.decision_calls == 0 and scene.dialogue_calls == 0, "sleep acceleration starts no Jev or OpenAI work even when AI mode is enabled")
	# Menu suspension retains the interval and freezes the entire running world.
	var interval: Dictionary = player.sleep.duplicate()
	var menu_minute: int = world.minute
	var menu_energy: float = world.player_energy()
	var requested_menu := [false]
	scene.menu_requested.connect(func(): requested_menu[0] = true)
	viewport.gui_release_focus()
	press(viewport, KEY_ESCAPE)
	expect(requested_menu[0] and world.is_sleeping("player"), "Escape requests the menu without waking the sleeper")
	scene.suspend_for_menu()
	scene._process(20.0)
	await settle()
	expect(world.minute == menu_minute and world.player_energy() == menu_energy and player.sleep == interval, "suspended menu preserves the sleep deadline, clock and energy")
	scene.resume_from_menu()
	scene.set_process(false)
	expect(world.is_sleeping("player") and player.sleep == interval and scene.decision_calls == 0, "resume preserves the same sleep and does not schedule a provider call")
	scene.controls_active = true
	viewport.gui_release_focus()
	press(viewport, KEY_E)
	expect(not world.is_sleeping("player") and scene.time_speed == 1.0 and world.player_energy() == menu_energy, "E wakes early at normal speed without granting instant energy")
	scene.sleep_ui.refresh()
	await settle()
	expect(not is_instance_valid(scene.sleep_ui.banner), "early wake removes the sleeping banner")
	scene.use_jev = false
	at_bed(scene, 25.0)
	expect(scene.sleep_ui.start(60), "the same bed supports a new short nap")
	viewport.gui_release_focus()
	press(viewport, KEY_W)
	expect(not world.is_sleeping("player") and scene.time_speed == 1.0, "WASD also wakes the player and returns manual speed")
	# Until morning uses the next 07:00 and is completed by normal ticks.
	at_bed(scene, 30.0)
	world.minute = 23 * 60
	scene.elapsed = 0.0
	scene.sleep_ui.show_choices()
	await settle()
	morning = find_button(scene.sleep_ui.panel, "Hasta las 7:00")
	expect(morning != null and not morning.disabled, "the same morning action is available at 23:00")
	if morning != null: click(viewport, morning)
	expect(world.is_sleeping("player") and player.sleep.until == 1440 + 420, "until-morning sleep targets 07:00 across the day boundary")
	var deadline: int = int(player.get("sleep", {}).get("until", 0))
	var frame_count := 0
	while world.is_sleeping("player") and frame_count < 180:
		scene._process(0.1)
		frame_count += 1
	scene.sleep_ui.refresh()
	await settle()
	expect(not world.is_sleeping("player") and world.minute == deadline and frame_count == 80, "eight seconds of local ticks complete eight hours exactly at the morning deadline")
	expect(scene.time_speed == 1.0 and not is_instance_valid(scene.sleep_ui.banner) and player.pos == fixed_position, "automatic wake restores normal controls and leaves the player at the bed")
	expect(scene.dialogue_job.is_empty() and world.conversation_holds.is_empty() and not scene.decision_pending and not scene.dialogue_request.busy and scene.dialogue_calls == 0, "sleep lifecycle leaves no reserved conversation, partial reply or provider request")
	scene.free()
	viewport.free()
	print("SLEEP UI: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
