extends SceneTree
## Real scene clock, rest state and physical routes, with no save or provider access.
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void:
		provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void:
		provider_calls += 1

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

func fixture() -> MainProbe:
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_url = ""
	scene.service_token = "isolated-probe-never-sent"
	scene.use_jev = true
	scene.ai_cooldown = 0.0
	scene.elapsed = 3.75 # A sleep must not inherit an almost-complete awake tick.
	scene.gathering = 20.0 # A prior social invitation must not freeze sleeping time.
	scene.time_speed = 4.0
	scene.colony.minute = 23 * 60
	var player: Dictionary = scene.colony.get_resident("player")
	var bed: Vector2 = Layout.stand_at("bed", "player")
	player.room = "player"
	player.pos = [bed.x, bed.y]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	player.energy = 10.0
	scene.paths.clear()
	scene.update_room()
	scene.controls_active = true
	return scene

func run_pattern(duration: int, frames: Array[float], label: String) -> void:
	var scene := fixture()
	var player: Dictionary = scene.colony.get_resident("player")
	var origin: Array = player.pos.duplicate()
	var started: int = scene.colony.minute
	expect(scene.sleep_ui.start(duration) and scene.elapsed == 0.0 and scene.time_speed == 1.0, label + ": starting rest discards awake elapsed time and speed")
	var real_seconds := 0.0
	var total_seconds: float = duration / 60.0
	var frame := 0
	var precise := true
	var physical := true
	while real_seconds < total_seconds - 0.00000001:
		var delta: float = minf(frames[frame % frames.size()], total_seconds - real_seconds)
		scene._process(delta)
		real_seconds += delta
		frame += 1
		var expected_minutes: int = mini(duration, floori((real_seconds + 0.00000001) * 12.0) * 5)
		precise = precise and scene.colony.minute == started + expected_minutes
		precise = precise and scene.colony.is_sleeping("player") == (expected_minutes < duration)
		physical = physical and player.pos == origin
		for resident: Dictionary in scene.colony.residents:
			physical = physical and Navigation.is_walkable(scene.position_of(resident), resident.room)
	expect(precise and scene.colony.minute == started + duration and not scene.colony.is_sleeping("player"), label + ": %dh takes exactly %.0f real seconds at every five-minute boundary" % [duration / 60,total_seconds])
	expect(physical and is_equal_approx(scene.colony.player_energy(), minf(100.0, 10.0 + duration * 0.25)), label + ": physical residents stay walkable and all actual rest intervals recover energy")
	expect(scene.elapsed == 0.0 and scene.time_speed == 1.0 and scene.provider_calls == 0 and scene.dialogue_job.is_empty() and not scene.decision_pending, label + ": wake leaves a clean normal clock without any provider call")
	scene.free()

func run() -> void:
	root.size = Vector2i(768,432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; refusing to read or write normal progress.")
		quit(1)
		return
	for action in ["city_left", "city_right", "city_up", "city_down"]:
		if InputMap.has_action(action): Input.action_release(action)
	for frequency in [10,30,60,144]:
		for duration in [60,480]:
			run_pattern(duration, [1.0 / frequency], "%d Hz" % frequency)
	for duration in [60,480]:
		run_pattern(duration, [0.011,0.047,0.131,0.004,0.207,0.029], "jitter and slow frames")
		run_pattern(duration, [duration / 60.0], "single long frame")

	var scene := fixture()
	expect(scene.sleep_ui.start(60), "pause fixture starts a real one-hour nap")
	scene._process(0.03)
	var minute: int = scene.colony.minute
	var partial: float = scene.elapsed
	var energy: float = scene.colony.player_energy()
	scene.toggle_pause()
	scene._process(20.0)
	expect(scene.colony.minute == minute and scene.elapsed == partial and scene.colony.player_energy() == energy and scene.colony.is_sleeping("player"), "pause freezes the partial sleep interval, deadline and energy during a long frame")
	scene.toggle_pause()
	scene._process(0.97)
	expect(scene.colony.minute == minute + 60 and not scene.colony.is_sleeping("player") and scene.provider_calls == 0, "resuming completes the nap after exactly one unpaused real second")
	scene.free()

	scene = fixture()
	expect(scene.sleep_ui.start(480), "menu fixture starts an eight-hour rest")
	scene._process(0.137)
	minute = scene.colony.minute
	partial = scene.elapsed
	energy = scene.colony.player_energy()
	var interval: Dictionary = scene.colony.get_resident("player").sleep.duplicate()
	scene.suspend_for_menu()
	scene._process(200.0)
	expect(scene.colony.minute == minute and scene.elapsed == partial and scene.colony.player_energy() == energy and scene.colony.get_resident("player").sleep == interval, "main menu freezes a partial rest without discarding or consuming time")
	scene.resume_from_menu()
	scene.set_process(false)
	scene._process(7.863)
	expect(scene.colony.minute == int(interval.until) and not scene.colony.is_sleeping("player") and scene.provider_calls == 0, "menu resume finishes at eight active real seconds with no provider work")
	scene.free()

	scene = fixture()
	expect(scene.sleep_ui.start(480), "oversized-frame fixture starts eight-hour sleep")
	minute = scene.colony.minute
	scene._process(20.0)
	expect(scene.colony.minute == minute + 480 and not scene.colony.is_sleeping("player") and scene.elapsed == 0.0 and scene.provider_calls == 0, "a twenty-second frame stops precisely at waking and cannot fast-forward the awake player")
	scene.use_jev = false
	for _frame in range(39): scene._process(0.1)
	expect(scene.colony.minute == minute + 480 and scene.time_speed == 1.0, "after waking, 3.9 real seconds still do not complete the normal four-second clock")
	scene._process(0.1)
	expect(scene.colony.minute == minute + 485 and is_zero_approx(scene.elapsed) and scene.provider_calls == 0, "normal time resumes at five game minutes per four seconds with no sleeping remainder")
	scene.free()
	await process_frame
	print("SLEEP TIMING: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
