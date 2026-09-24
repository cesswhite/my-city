extends SceneTree
## Real viewport keyboard delivery. Isolated defaults, no save or provider access.
const Layout = preload("res://scripts/world_layout.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var knocks: Array[String] = []
	var provider_calls := 0
	func knock_home(home_id: String) -> void: knocks.append(home_id)
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var capture_enabled := false

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func settle() -> void:
	for _frame in range(4): await process_frame

func key(viewport: SubViewport, code: Key, pressed: bool, repeated: bool = false, shifted: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = repeated
	event.shift_pressed = shifted
	viewport.push_input(event, true)

func tap(viewport: SubViewport, code: Key, shifted: bool = false) -> void:
	key(viewport, code, true, false, shifted)
	key(viewport, code, false, false, shifted)

func centered(panel: Control, viewport: SubViewport) -> bool:
	return panel.get_global_rect().get_center().distance_to(Vector2(viewport.size) / 2.0) < 0.001

func door_buttons(scene: MainProbe) -> Array[Button]:
	var result: Array[Button] = []
	for child in scene.door_panel.get_children():
		if child is Button: result.append(child)
	return result

func capture(viewport: SubViewport, name: String) -> void:
	if not capture_enabled: return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/modal-keyboard")
	DirAccess.make_dir_recursive_absolute(folder)
	var image: Image = viewport.get_texture().get_image()
	expect(not image.is_empty() and image.get_size() == viewport.size and image.save_png(folder.path_join(name + ".png")) == OK, "capture " + name + " exports at the actual viewport size")

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; refusing to read or save real progress.")
		quit(1)
		return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name() == "headless":
		push_error("--capture requires a graphical renderer.")
		quit(1)
		return
	root.size = Vector2i(768, 432)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768, 432)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := MainProbe.new()
	scene.start_new_game = true
	scene.colony.save_path = "user://test_modal_keyboard_%d.json" % OS.get_process_id()
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = ""
	scene.service_url = ""
	scene.use_jev = false
	scene.paused = false
	scene.controls_active = true
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	await settle()
	var player: Dictionary = scene.colony.get_resident("player")
	var point: Vector2 = Layout.door_positions().lupita
	player.room = "street"
	player.pos = [point.x, point.y]
	player.target = player.pos.duplicate()
	var owner: Dictionary = scene.colony.get_resident("lupita")
	owner.room = "lupita"
	owner.pos = [236.0, 252.0]
	owner.target = owner.pos.duplicate()
	scene.update_room()
	var original_position: Array = player.pos.duplicate()
	var original_memories: int = player.memories.size()
	expect(scene.preview_mode and scene.colony.minute == 480 and not scene.save_allowed, "fixture is isolated before any modal interaction")
	for dimensions: Vector2i in [Vector2i(768,432), Vector2i(960,600), Vector2i(1280,540)]:
		viewport.size = dimensions
		await settle()
		scene.show_door_panel("lupita")
		await settle()
		var label := "%d×%d" % [dimensions.x, dimensions.y]
		var buttons := door_buttons(scene)
		expect(centered(scene.door_panel, viewport), label + " door is geometrically centered")
		expect(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(scene.door_panel.get_global_rect()) and scene.door_backdrop.get_global_rect() == Rect2(Vector2.ZERO, Vector2(dimensions)), label + " door and backdrop fit the viewport")
		expect(buttons.size() == 2, label + " door has exactly two choices")
		if buttons.size() != 2: break
		var primary: Button = buttons[0]
		var back: Button = buttons[1]
		expect(primary.has_focus() and primary.text == "Tocar la puerta" and back.text == "Volver", label + " opens with the primary door action focused")
		await capture(viewport, label + "-primary")
		var moved := false
		for direction in [{"key":KEY_RIGHT,"action":"city_right","target":back}, {"key":KEY_LEFT,"action":"city_left","target":primary}, {"key":KEY_DOWN,"action":"city_down","target":back}, {"key":KEY_UP,"action":"city_up","target":primary}]:
			key(viewport, direction.key, true)
			# Keep the actual movement action held while the same key navigates GUI focus.
			Input.action_press(direction.action)
			scene.elapsed = 0.0
			scene._process(0.05)
			moved = moved or player.pos != original_position
			Input.action_release(direction.action)
			key(viewport, direction.key, false)
			expect(direction.target.has_focus(), label + " " + OS.get_keycode_string(direction.key) + " selects the other modal choice")
		expect(not moved and player.target == player.pos and not scene.keyboard_walking, label + " arrow navigation never moves the player")
		tap(viewport, KEY_TAB)
		expect(back.has_focus(), label + " Tab selects the secondary choice")
		tap(viewport, KEY_TAB)
		expect(primary.has_focus(), label + " Tab wraps inside the modal")
		tap(viewport, KEY_TAB, true)
		expect(back.has_focus(), label + " Shift-Tab wraps without escaping to the HUD")
		await capture(viewport, label + "-secondary")
		tap(viewport, KEY_TAB)
		var previous_knocks: int = scene.knocks.size()
		key(viewport, KEY_ENTER, true)
		key(viewport, KEY_ENTER, true, true)
		key(viewport, KEY_ENTER, true, true)
		key(viewport, KEY_ENTER, false)
		expect(scene.knocks.size() == previous_knocks + 1 and scene.knocks[-1] == "lupita" and is_instance_valid(scene.door_panel), label + " Enter activates only the focused primary once, ignoring key repeat")
		tap(viewport, KEY_RIGHT)
		tap(viewport, KEY_ENTER)
		expect(not is_instance_valid(scene.door_panel) and scene.knocks.size() == previous_knocks + 1, label + " Enter on Volver closes without knocking")
		scene.show_door_panel("lupita")
		await settle()
		expect(door_buttons(scene)[0].has_focus(), label + " reopening resets focus to the primary action")
		tap(viewport, KEY_ESCAPE)
		expect(not is_instance_valid(scene.door_panel), label + " Escape closes the door modal")
		scene.show_help()
		await settle()
		expect(centered(scene.help_panel, viewport), label + " help remains centered")
		scene.close_help()
		scene.learning.show_journal()
		await settle()
		expect(centered(scene.learning.panel, viewport), label + " learning journal remains centered")
		scene.learning.close()
		await settle()
	viewport.size = Vector2i(768,432)
	await settle()
	scene.show_door_panel("lupita")
	await settle()
	tap(viewport, KEY_RIGHT)
	var active_panel: int = scene.door_panel.get_instance_id()
	viewport.size = Vector2i(960,600)
	await settle()
	expect(centered(scene.door_panel, viewport) and scene.door_panel.get_instance_id() == active_panel and door_buttons(scene)[1].has_focus(), "resizing an open door centers the same panel and preserves the selected choice")
	scene.close_door_panel()
	expect(player.pos == original_position and player.target == player.pos and scene.colony.minute == 480, "all modal keyboard interactions preserve player position and the game clock")
	expect(scene.provider_calls == 0 and scene.visit_job.is_empty() and scene.dialogue_job.is_empty() and not scene.decision_pending and player.memories.size() == original_memories, "modal tests create no provider calls, dialogue jobs or memories")
	scene.free()
	viewport.free()
	print("MODAL KEYBOARD: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
