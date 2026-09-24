extends SceneTree
## Real journal callbacks in an isolated fresh settlement. Optional GL screenshots.
const Main = preload("res://scenes/main.tscn")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var viewport: SubViewport
var scene

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for _frame in range(4): await process_frame

func button(action: String, key := "", value := "") -> Button:
	if not is_instance_valid(scene.settlement_ui.panel): return null
	for child in scene.settlement_ui.panel.find_children("*", "Button", true, false):
		if child.get_meta("settlement_action", "") != action: continue
		if not key.is_empty() and child.get_meta(key, "") != value: continue
		return child
	return null

func press(action: String, key := "", value := "") -> bool:
	var control := button(action, key, value)
	if not is_instance_valid(control) or control.disabled:
		expect(false, "Enabled community action: " + action + " " + value)
		return false
	control.pressed.emit()
	return true

func position(id: String, point: Vector2, room: String) -> void:
	var person: Dictionary = scene.colony.get_resident(id)
	person.room = room
	person.pos = [point.x, point.y]
	person.target = person.pos.duplicate()
	person.travel_intent = ""
	person.erase("travel_route")
	scene.paths.erase(id)
	scene.colony._daily_life.forget(id)
	scene.update_room()

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../artifacts/settlement/ui")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("%dx%d-%s.png" % [viewport.size.x, viewport.size.y, name])
	expect(viewport.get_texture().get_image().save_png(path) == OK, "Capture saved: " + name)
	captures.append(path)
	print("CAPTURE " + path)

func fit() -> void:
	var panel: Panel = scene.settlement_ui.panel
	expect(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(panel.get_global_rect()), "Community panel fits " + str(viewport.size))
	var accessible := true
	var contained := true
	for control in panel.find_children("*", "Button", true, false):
		if not control.is_visible_in_tree(): continue
		accessible = accessible and not control.accessibility_name.is_empty() and not control.tooltip_text.is_empty() and control.focus_mode == Control.FOCUS_ALL
		var ancestor: Node = control.get_parent()
		var scrolling := false
		while ancestor != panel:
			if ancestor is ScrollContainer: scrolling = true
			ancestor = ancestor.get_parent()
		if not scrolling and not panel.get_global_rect().encloses(control.get_global_rect()): contained = false
	expect(accessible, "Visible actions have keyboard focus and accessible labels")
	expect(contained, "Fixed actions stay inside the panel while content can scroll")
	var learn := button("learning")
	var text_width: float = learn.get_theme_font("font").get_string_size(learn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, learn.get_theme_font_size("font_size")).x
	expect(learn.size.x >= text_width + 16, "Aprendizajes navigation remains readable, not a clipped textless strip")

func complete_nearby(task: String) -> void:
	var spec: Dictionary = scene.colony.settlement.task_spec(task)
	position("player", Layout.point(spec.at) + Vector2(-20, 0), str(spec.room))
	var before: Dictionary = scene.colony.progression_state().inventory.duplicate(true)
	scene.settlement_ui.selected_worker = "player"
	scene.settlement_ui.show_task(task)
	if not press("start"): return
	expect(scene.colony.settlement_jobs.busy("player") and not is_instance_valid(scene.settlement_ui.panel) and not is_instance_valid(scene.settlement_ui.modal_shade), "Starting work closes the entire community modal")
	expect(scene.colony.progression_state().inventory == before, "Planning a gathering trip grants no resources")
	for _frame in range(300):
		scene.move_resident(scene.colony.get_resident("player"), 1.0 / 30.0)
		scene.resolve_player_arrival()
		scene.colony.settlement_jobs.tick(0.5)
		if not scene.colony.settlement_jobs.busy("player"): break
	expect(not scene.colony.settlement_jobs.busy("player"), "Physical work finishes after arrival: " + task)
	for resource: String in spec.outputs:
		expect(int(scene.colony.progression_state().inventory.get(resource, 0)) == int(before.get(resource, 0)) + int(spec.outputs[resource]), "Verified work grants catalog output once: " + resource)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ui-test" not in args or "--settlement-start" not in args:
		push_error("Use -- --ui-test --settlement-start; no user save or providers allowed.")
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(768, 432)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = Main.instantiate()
	scene.managed_by_shell = true
	scene.start_new_game = true
	var isolated_path := "user://test_settlement_ui_%d.json" % OS.get_process_id()
	scene.colony.save_path = isolated_path
	viewport.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = ""
	scene.service_url = ""
	scene.use_jev = false
	scene.colony.settlement_jobs.autonomous_enabled = false
	scene.paused = true
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	await settle()
	expect(scene.preview_mode and not FileAccess.file_exists(isolated_path), "Fresh fixture is isolated and has no persisted save")
	expect(scene.colony.active_residents().size() == 3, "New community contains only player, Inés and Lupita")
	var apprenticeships: Array = scene.colony.available_apprenticeships()
	expect(apprenticeships.size() == 1 and apprenticeships[0].mentor_id == "ines", "Absent mentors do not offer apprenticeships")
	var before := JSON.stringify(scene.colony.settlement.snapshot())
	var wallet_before := JSON.stringify(scene.colony.progression_state())
	scene.hud.buttons.journal.pressed.emit()
	expect(is_instance_valid(scene.settlement_ui.panel) and scene.settlement_ui.tab == "town", "Diary dock opens the community overview")
	for size: Vector2i in [Vector2i(768,432),Vector2i(960,540)]:
		viewport.size = size
		await settle()
		for section in ["town","resources","projects","jobs","orders"]:
			scene.settlement_ui.show_overview(section)
			await settle()
			fit()
			await capture(section)
	expect(JSON.stringify(scene.colony.settlement.snapshot()) == before and JSON.stringify(scene.colony.progression_state()) == wallet_before, "Browsing every journal section does not alter resources, commitments or population")
	scene.settlement_ui.show_task("build:workbench")
	expect(is_instance_valid(button("start")) and button("start").disabled, "Missing building materials explain and disable commitment")
	var worker_picker: OptionButton = scene.settlement_ui.panel.find_child("SettlementWorker", true, false)
	var choices: Array[String] = []
	for index in range(worker_picker.item_count): choices.append(str(worker_picker.get_item_metadata(index)))
	expect(choices.size() == 3 and "mateo" not in choices and "alma" not in choices and "cesar" not in choices, "Worker selection contains only present residents")
	await capture("workbench-requirements")
	scene.settlement_ui.show_person("ines")
	expect(JSON.stringify(scene.colony.settlement.snapshot()) == before, "Inspecting voluntary jobs does not count as a work request")
	scene.settlement_ui.show_market()
	expect(is_instance_valid(button("shop")) and button("sell").disabled, "Distant market provides travel and prevents remote sale")
	scene.settlement_ui.show_overview("orders")
	expect(is_instance_valid(button("requester")), "Distant order provides a route to its actual requester")
	press("learning")
	expect(not is_instance_valid(scene.settlement_ui.panel) and is_instance_valid(scene.learning.panel), "Aprendizajes replaces the town modal instead of stacking overlays")
	var town_button: Button
	for child in scene.learning.panel.find_children("*", "Button", true, false):
		if child.get_meta("journal_action", "") == "town": town_button = child
	expect(is_instance_valid(town_button), "Learning journal has a visible route back to Pueblo")
	if is_instance_valid(town_button): town_button.pressed.emit()
	expect(is_instance_valid(scene.settlement_ui.panel) and not is_instance_valid(scene.learning.panel), "Returning to town removes the learning shade")
	await settle()
	var previous_focus: Control = viewport.gui_get_focus_owner()
	var tab_key := InputEventKey.new()
	tab_key.pressed = true
	tab_key.keycode = KEY_TAB
	viewport.push_input(tab_key)
	await process_frame
	var next_focus: Control = viewport.gui_get_focus_owner()
	expect(is_instance_valid(previous_focus) and is_instance_valid(next_focus) and previous_focus != next_focus and scene.settlement_ui.panel.is_ancestor_of(next_focus), "Tab advances between enabled controls without leaving the journal")
	tab_key.shift_pressed = true
	viewport.push_input(tab_key)
	await process_frame
	expect(viewport.gui_get_focus_owner() == previous_focus, "Shift-Tab returns to the previous journal control")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	scene._input(key)
	expect(not is_instance_valid(scene.settlement_ui.panel) and not is_instance_valid(scene.settlement_ui.modal_shade), "Escape removes the community modal and its mouse interception")
	# Real UI plan/cancel reserves stock, then returns it without minting goods.
	scene.settlement_ui.selected_worker = "player"
	scene.settlement_ui.show_task("gather:fallen_branches")
	if press("start"):
		expect(scene.colony.settlement_jobs.busy("player"), "UI confirmation creates one local work commitment")
		scene.settlement_ui.show_overview("jobs")
		await capture("active-job")
		press("cancel", "worker_id", "player")
		expect(not scene.colony.settlement_jobs.busy("player") and JSON.stringify(scene.colony.progression_state()) == wallet_before, "Cancel before work returns stock and creates no output or wallet changes")
	complete_nearby("gather:fallen_branches")
	complete_nearby("gather:loose_stones")
	scene.settlement_ui.show_task("build:workbench")
	expect(not button("start").disabled, "Gathered resources enable the first construction")
	await capture("workbench-ready")
	# Sale and order run real atomic world actions at their physical service points.
	var shop: Dictionary = scene.colony._progression.catalog.shop
	position("player", Layout.point(shop.pos), str(shop.room))
	scene.settlement_ui.show_market()
	var coins: int = scene.colony.progression_state().coins
	press("sell", "item_id", "piedra")
	expect(scene.colony.progression_state().coins == coins + 1 and int(scene.colony.progression_state().inventory.get("piedra", 0)) == 1, "Market button exchanges exactly one resource at the real store")
	complete_nearby("gather:wild_fibers")
	position("lupita", Vector2(234,208), "street")
	position("player", Vector2(252,208), "street")
	scene.settlement_ui.show_overview("orders")
	coins = scene.colony.progression_state().coins
	press("deliver", "order_id", "welcome_supplies")
	expect(scene.colony.progression_state().coins == coins + 6 and int(scene.colony.progression_state().inventory.get("madera", 0)) == 0, "Nearby order delivery consumes materials once and pays the catalog reward")
	expect(button("deliver", "order_id", "welcome_supplies").disabled, "Daily fulfilled order cannot pay twice")
	scene.settlement_ui.close()
	scene.open_inspector("lupita", "historia")
	var work_action: Button = scene.inspector.find_child("ResidentWork", true, false)
	expect(is_instance_valid(work_action) and work_action.accessibility_name == "Pedir ayuda", "Resident profile exposes an accessible voluntary work action")
	if is_instance_valid(work_action): work_action.pressed.emit()
	expect(is_instance_valid(scene.settlement_ui.panel) and scene.settlement_ui.selected_worker == "lupita", "Resident work action opens that resident's own choices")
	expect(scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not scene.decision_pending and not FileAccess.file_exists(isolated_path), "All community UI flows avoid providers and persistent user data")
	scene.free()
	viewport.free()
	await process_frame
	print("SETTLEMENT UI: %d/%d; %d captures" % [checks - failures.size(), checks, captures.size()])
	quit(0 if failures.is_empty() else 1)
