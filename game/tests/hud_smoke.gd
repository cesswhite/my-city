extends SceneTree
## Real HUD callbacks and verified local world actions. No providers or save access.
const Main = preload("res://scenes/main.tscn")
const Layout = preload("res://scripts/world_layout.gd")
const Icons = preload("res://scripts/hud_icons.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in range(4): await process_frame

func click(viewport: SubViewport, button: Button) -> void:
	click_at(viewport, button.get_global_rect().get_center())

func click_at(viewport: SubViewport, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)

func place(world, id: String, room: String, point: Array) -> void:
	var resident: Dictionary = world.get_resident(id)
	resident.room = room
	resident.pos = point.duplicate()
	resident.target = point.duplicate()
	resident.travel_intent = ""

func icons_stay_textless(scene) -> bool:
	for button: Button in scene.hud.buttons.values():
		if not button.text.is_empty(): return false
	return true

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test to keep this fixture isolated.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768, 432)
	root.add_child(viewport)
	var scene = Main.instantiate()
	viewport.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0 # HUD actions use deterministic chat availability.
	await settle()
	scene.set_process(false)
	scene.service_token = ""
	scene.use_jev = false
	scene.save_allowed = false
	# --ui-test returns before the normal final refresh; synchronize fixture state.
	scene.refresh_status()
	scene.overlay.dismiss_toast()
	var hud = scene.hud
	var world = scene.colony
	var player: Dictionary = world.get_resident("player")
	expect(scene.preview_mode and scene.paused and world.minute == 480, "HUD fixture uses defaults without loading the player's progress")
	expect(hud.buttons.size() == 7 and icons_stay_textless(scene), "seven compact icon actions remain separate from speed")
	expect(hud.dock_panel.size == Vector2(68,36) and hud.dock_panel.position == Vector2(12,384) and hud.dock_panel.get_children().filter(func(child): return child is Button).size() == 2, "lower-left dock contains only the two everyday actions")
	expect(not hud.buttons.has("person") and not hud.buttons.has("home") and not hud.buttons.has("clock") and hud.buttons.journal.get_parent() == hud.dock_panel and hud.buttons.bicycle.get_parent() == hud.dock_panel, "person, home and history actions are absent from the reduced dock")
	expect(hud.controls_panel.size == Vector2(196,36) and hud.buttons.spark.get_parent() == hud.controls_panel and hud.buttons.spark.position == scene.pause_button.position + Vector2(32,0), "AI sits immediately beside pause in the six-control upper panel")
	expect(hud.energy_bar.size == Vector2(28, 3) and hud.energy_group.get_global_rect().encloses(hud.energy_bar.get_global_rect()) and hud.stats_panel.get_global_rect().encloses(hud.energy_group.get_global_rect()), "small energy gauge remains inside the floating statistics group")
	expect(not hud.learning_value.visible and hud.learning_group == hud.buttons.journal, "verified learning remains in the journal tooltip without a permanent counter")
	for id: String in hud.buttons:
		var button: Button = hud.buttons[id]
		expect(button.size == Vector2(28, 28) and button.icon != null and button.icon.get_size() == Vector2(16, 16), id + " has a native 16px icon inside its 28px click target")
		expect(not button.accessibility_name.is_empty() and not button.accessibility_description.is_empty() and button.tooltip_text.contains(button.accessibility_name) and button.focus_mode == Control.FOCUS_ALL, id + " retains its accessible name, explanation and keyboard focus")
		button.grab_focus()
		await process_frame
		expect(hud.context_hint().contains(button.accessibility_name), id + " exposes contextual help on keyboard focus")
	var protected_target: Array = player.target.duplicate()
	for panel: Panel in [hud.stats_panel, hud.controls_panel, hud.dock_panel]:
		var padding: Vector2 = panel.get_global_rect().position + Vector2(2, 2)
		expect(panel.mouse_filter == Control.MOUSE_FILTER_STOP and hud.pointer_over(padding), panel.name + " blocks pointer input across its surface and padding")
		click_at(viewport, padding)
	expect(player.target == protected_target, "clicks between HUD controls cannot create a world route")
	expect(scene.pause_button.accessibility_name == "Continuar", "paused scene announces the available continue action")
	click(viewport, scene.pause_button)
	expect(not scene.paused and scene.pause_button.accessibility_name == "Pausar" and scene.pause_button.icon == Icons.texture("pause"), "pointer click resumes the world and updates the pause glyph and name")
	click(viewport, scene.pause_button)
	expect(scene.paused and scene.pause_button.icon == Icons.texture("play"), "second pointer click pauses once and exposes play")
	for expected_speed in [2, 4, 1]:
		click(viewport, scene.speed_button)
		expect(scene.time_speed == expected_speed and scene.speed_button.text == "%d×" % expected_speed and scene.speed_button.accessibility_name.contains("%d×" % expected_speed), "speed cycles to %d× with matching visible and accessible state" % expected_speed)
	click(viewport, scene.autonomy_button)
	expect(world.player_autonomy and scene.autonomy_button.accessibility_name == "Tomar control" and scene.autonomy_button.icon == Icons.texture("hand"), "autonomy action enables routines and exposes taking control")
	click(viewport, scene.autonomy_button)
	expect(not world.player_autonomy and scene.time_speed == 1.0 and scene.autonomy_button.accessibility_name == "Vivir solo" and icons_stay_textless(scene), "taking control restores manual speed without putting labels back on icons")
	scene.paused = true
	scene.open_inspector("player", "aspecto")
	expect(scene.inspector.visible and not hud.controls_panel.visible, "opening a profile still clears competing upper controls")
	click(viewport, hud.buttons.journal)
	expect(is_instance_valid(scene.settlement_ui.panel) and scene.keyboard_blocked(), "journal icon opens the town modal and blocks world input")
	scene.settlement_ui.close()
	await settle()
	scene.hide_inspector()
	await settle()
	expect(hud.controls_panel.visible, "closing inspector restores the upper controls")
	click(viewport, hud.buttons.menu)
	expect(is_instance_valid(scene.help_panel) and scene.keyboard_blocked(), "standalone menu icon opens help without passing its click to the world")
	scene.close_help()
	await settle()
	click(viewport, hud.buttons.save)
	expect(scene.log_label.text.contains("vista previa") and not scene.save_allowed, "save icon obeys the preview guard")
	click(viewport, hud.buttons.spark)
	expect(not scene.use_jev and not scene.decision_pending and scene.ai_button.accessibility_name == "Activar IA", "missing service token never claims the AI is enabled")
	hud.refresh_stats()
	expect(hud.coin_value.text == "20" and hud.learning_value.text == "0/3", "initial money and demonstrated learning reflect the isolated world")
	var before: Dictionary = world.progression_state()
	var energy_before: float = world.player_energy()
	for _read in range(20): hud.refresh_stats()
	expect(world.progression_state() == before and world.player_energy() == energy_before, "rendering statistics awards no progress and consumes no energy")
	# Follow the complete bicycle chain through the world API, never fake a completed quest.
	place(world, "player", "street", world.PLACES.taller)
	place(world, "mateo", "street", world.PLACES.taller)
	expect(world.start_apprenticeship("bicicleta_de_mateo").ok, "mentor accepts the real bicycle errand")
	hud.refresh_stats()
	expect(hud.learning_value.text == "0/3", "accepting an errand does not count as demonstrated learning")
	var shop: Vector2 = Layout.stand_at("shop", "street")
	place(world, "player", "street", [shop.x, shop.y])
	expect(world.buy_item("aceite").ok, "purchase validates the actual shop location and requested item")
	hud.refresh_stats()
	expect(hud.coin_value.text == "15" and hud.coin_group.accessibility_name == "15 monedas", "purchase immediately lowers visible and accessible coin balances")
	place(world, "player", "street", world.PLACES.taller)
	expect(world.deliver_apprenticeship("bicicleta_de_mateo").ok, "delivery consumes materials and provides instructions and kit")
	hud.refresh_stats()
	expect(world.quest_status("bicicleta_de_mateo").status == "learned" and hud.learning_value.text == "0/3", "instructions retained in memory still do not count as demonstrated")
	var station: Vector2 = Layout.stand_at("bicycle", "player")
	place(world, "player", "player", [station.x, station.y])
	scene.update_room()
	expect(scene.bike_button.disabled and scene.bike_button.tooltip_text.contains("solo en la calle") and hud.dock_panel.size == Vector2(68,36), "home keeps the tiny two-action dock and explains why the bicycle is disabled")
	expect(world.perform_procedure("reparar_bicicleta").ok, "first practice step is verified at the home work station")
	hud.refresh_stats()
	expect(hud.learning_value.text == "0/3", "partial practice does not inflate the learning counter")
	for _step in range(3): expect(world.perform_procedure("reparar_bicicleta").ok, "next ordered practice step is verified")
	hud.refresh_stats()
	expect(world.progression_state().procedures.reparar_bicicleta.world_verified and hud.learning_value.text == "1/3" and hud.learning_group.accessibility_description.contains("demostrados"), "only the final verified procedure increments demonstrated learning in the diary tooltip")
	place(world, "player", "street", [280, 180])
	scene.update_room()
	expect(not scene.bike_button.disabled, "returning to the street restores the bicycle action")
	click(viewport, hud.buttons.bicycle)
	expect(scene.riding_bicycle and scene.bike_button.accessibility_name == "Bajar de la bici" and icons_stay_textless(scene), "repaired bicycle action mounts and announces dismount without restoring text")
	place(world, "mateo", "street", [288, 180])
	expect(scene.player_chat.start("mateo"), "opening an actual chat reserves the nearby pair without a provider request")
	expect(not scene.riding_bicycle and scene.bike_button.text.is_empty() and scene.bike_button.accessibility_name == "Montar en bici", "chat dismount keeps the bicycle icon textless with its current accessible action")
	scene.player_chat.finish()
	# The energy gauge follows local ticks, including real stationary rest by the bed.
	player.energy = 20.0
	world.tick(false)
	hud.refresh_stats()
	expect(hud.energy_bar.value == world.player_energy() and hud.energy_value.text == "%d%%" % roundi(world.player_energy()), "awake tick updates both the precise gauge and rounded energy text")
	var bed: Vector2 = Layout.stand_at("bed", "player")
	place(world, "player", "player", [bed.x, bed.y])
	world.tick(false)
	var rested_from: float = world.player_energy()
	world.tick(false)
	hud.refresh_stats()
	expect(world.player_energy() > rested_from and hud.energy_bar.value == world.player_energy(), "stationary rest in the actual home restores energy on simulation ticks")
	scene.update_room()
	# Insets and alignment remain real at wide and tall viewport sizes.
	for dimensions: Vector2i in [Vector2i(768,432), Vector2i(1024,432), Vector2i(768,576), Vector2i(960,600)]:
		viewport.size = dimensions
		await settle()
		scene.hide_inspector()
		await settle()
		expect(hud.dock_panel.position == Vector2(12, dimensions.y - 48) and hud.dock_panel.size == Vector2(68,36), "%s preserves the same lower-left two-action dock" % dimensions)
		var hud_controls: Array[Control] = []
		for button: Button in hud.buttons.values(): hud_controls.append(button)
		hud_controls.append_array([scene.speed_button, hud.energy_group, hud.coin_group, scene.clock_label, hud.mode_group])
		var safe := true
		for control: Control in hud_controls:
			safe = safe and control.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(control.get_global_rect())
			for other: Control in hud_controls:
				if control != other and control.get_global_rect().intersects(other.get_global_rect()): safe = false
		expect(safe, "%s keeps floating action targets and readouts separate and inside the viewport" % dimensions)
		var occupied := 0.0
		var panels: Array[Panel] = [hud.stats_panel, hud.controls_panel, hud.dock_panel]
		var groups_separate := true
		for panel: Panel in panels:
			occupied += panel.size.x * panel.size.y
			for other: Panel in panels:
				if panel != other and panel.get_global_rect().intersects(other.get_global_rect()): groups_separate = false
		expect(groups_separate and occupied < dimensions.x * dimensions.y * 0.1 and not hud.pointer_over(Vector2(dimensions) / 2.0), "floating HUD leaves over ninety percent of %s free of permanent UI" % dimensions)
		scene.open_inspector("player", "aspecto")
		await settle()
		expect(not hud.controls_panel.visible and not hud.stats_panel.get_global_rect().intersects(scene.inspector.get_global_rect()) and not hud.dock_panel.get_global_rect().intersects(scene.inspector.get_global_rect()), "opening inspector at %s keeps the remaining floating HUD clear" % dimensions)
		expect(not hud.pointer_over(hud.controls_panel.get_global_rect().get_center()), "hidden upper controls do not reserve a pointer-blocking rectangle")
	expect(icons_stay_textless(scene) and scene.dialogue_job.is_empty() and not scene.decision_pending and not scene.dialogue_request.busy and not scene.request.is_processing(), "all transitions finish with textless icons and no provider work")
	scene.free()
	viewport.free()
	print("HUD: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
