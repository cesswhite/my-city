extends SceneTree
## Real viewport resizing and pointer input; no providers or saved progress.
const Main = preload("res://scenes/main.tscn")
const Art = preload("res://scripts/pixel_art.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if value:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error(description)

func settle() -> void:
	for _frame in range(4): await process_frame

func click(viewport: SubViewport, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)

func reset_player(scene: Control) -> void:
	scene.take_control()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	scene.controls_active = true
	scene.close_help()
	scene.close_door_panel()
	scene.learning.close()
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = "street"
	player.pos = [192,230]
	player.target = player.pos.duplicate()
	var neighbor: Dictionary = scene.colony.get_resident("lupita")
	neighbor.pos = [264,214]
	neighbor.target = neighbor.pos.duplicate()
	scene.update_room()
	scene.paused = true

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test to isolate progress and providers.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,432)
	root.add_child(viewport)
	var scene = Main.instantiate()
	viewport.add_child(scene)
	await settle()
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = ""
	scene.use_jev = false
	expect(scene.preview_mode and scene.colony.minute == 480, "responsive fixture uses isolated defaults")
	expect(scene.world_view_rect == Rect2(0,0,768,432) and not scene.inspector.visible, "the world starts edge to edge with the inspector hidden")
	for dimensions: Vector2i in [Vector2i(1024,432), Vector2i(768,576), Vector2i(960,600), Vector2i(768,432)]:
		viewport.size = dimensions
		await settle()
		var extent := Vector2(dimensions)
		var bounds := Rect2(Vector2.ZERO,extent)
		expect(scene.size == extent and scene.world_view_rect == bounds, "%s fills the available viewport" % dimensions)
		expect(scene.world_view_rect.grow(0.51).encloses(scene.world_map_rect), "%s keeps every world edge visible" % dimensions)
		expect(is_equal_approx(scene.actors.scale.x,scene.actors.scale.y) and scene.actors.scale == scene.scenery.scale, "%s keeps scenery and people in one uniform transform" % dimensions)
		var round_trip := true
		for point: Vector2 in [Vector2(12,48),Vector2(480,292),Vector2(236,210),Vector2(441,160)]:
			round_trip = round_trip and scene.screen_to_world(scene.world_to_screen(point)).distance_to(point) < 0.001
			round_trip = round_trip and (scene.actors.get_global_transform() * point).distance_to(scene.world_to_screen(point)) < 0.001
		expect(round_trip, "%s pointer inversion agrees with the rendered actor transform" % dimensions)
		var expected_scale: float = minf(extent.x / 468.0, extent.y / 244.0)
		var expected_map_size: Vector2 = Vector2(468,244) * expected_scale
		expect(is_equal_approx(scene.world_scale, expected_scale) and scene.world_map_rect == Rect2(((extent - expected_map_size) / 2.0).round(), expected_map_size), "%s fits and centers the original map without changing its aspect ratio" % dimensions)
		var before_panel: Rect2 = scene.world_map_rect
		scene.open_inspector("cesar", "historia")
		expect(scene.inspector.visible and scene.inspector.position == Vector2(extent.x-270,16) and scene.inspector.size == Vector2(254,extent.y-32), "%s inspector floats at the right with consistent margins" % dimensions)
		expect(scene.world_map_rect.size == before_panel.size and is_equal_approx(scene.world_scale, expected_scale), "%s opening an inspector preserves the world scale while framing the selected person" % dimensions)
		scene.hide_inspector()
		expect(not scene.inspector.visible and scene.world_map_rect == before_panel and is_equal_approx(scene.world_scale, expected_scale), "%s hiding an inspector restores the centered map at the same scale" % dimensions)

		reset_player(scene)
		expect(not scene.point_over_interface(scene.world_to_screen(Vector2(290,180))), "%s walking fixture is on unobstructed world terrain" % dimensions)
		click(viewport,scene.world_to_screen(Vector2(290,180)))
		var player: Dictionary = scene.colony.get_resident("player")
		expect(Vector2(player.target[0],player.target[1]).distance_to(Vector2(290,180)) < 0.01, "%s actual viewport click reaches the original navigation coordinates" % dimensions)
		reset_player(scene)
		var resident: Dictionary = scene.colony.get_resident("lupita")
		resident.room = "street"
		resident.pos = [280,180]
		resident.target = resident.pos.duplicate()
		click(viewport,scene.world_to_screen(Vector2(280,170)))
		expect(scene.selected_id == "lupita" and scene.inspector.visible, "%s pointer selects the person and opens their overlay" % dimensions)
		scene.hide_inspector()
		player.room = Layout.home_area("player")
		player.target = player.pos.duplicate()
		scene.update_room()
		expect(not scene.point_over_interface(scene.world_to_screen(Navigation.door_positions().player-Vector2(0,9))), "%s doorway fixture remains clear of floating controls" % dimensions)
		click(viewport,scene.world_to_screen(Navigation.door_positions().player-Vector2(0,9)))
		expect(scene.pending_home == "player", "%s door hotspot follows the same transform" % dimensions)
		reset_player(scene)
		if scene.world_map_rect != scene.world_view_rect:
			var before: Array = player.target.duplicate()
			click(viewport,scene.world_view_rect.position+Vector2(1,1))
			expect(player.target == before, "%s surrounding terrain cannot create a route outside the navigable map" % dimensions)
		player.room = "player"
		player.pos = [236,252]
		player.target = player.pos.duplicate()
		scene.update_room()
		var station: Dictionary = {}
		for item: Dictionary in Art.interior_items("player"):
			if item.get("station", "") == "bicycle" or item.get("id", "") == "bicycle": station = item
		click(viewport,scene.world_to_screen(station.rect.get_center()))
		expect(scene.pending_item.get("id", "") == "bicycle" and Vector2(player.target[0],player.target[1]) == station.stand_at, "%s interior hotspot still routes to its real work station" % dimensions)
		reset_player(scene)

	# Resize existing controls, rather than rebuilding and losing an active draft.
	scene.open_inspector("lupita", "hablar")
	scene.chat_input.text = "César, éste sigue siendo mi borrador."
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_column(8)
	var editor_id: int = scene.chat_input.get_instance_id()
	viewport.size = Vector2i(960,600)
	await settle()
	expect(scene.chat_input.get_instance_id() == editor_id and scene.chat_input.text == "César, éste sigue siendo mi borrador." and scene.chat_input.has_focus() and scene.chat_input.get_caret_column() == 8, "resizing preserves the same editor, draft, focus and caret")
	var inspector_extra: float = scene.inspector.size.y - 368.0
	expect(scene.chat_scroll.size.y == 184 + inspector_extra and scene.chat_input.position.y == 320 + inspector_extra and scene.chat_send.position.y == 320 + inspector_extra, "overlay height expands the transcript and anchors reply controls to the panel bottom")
	for kind in ["help", "door", "journal"]:
		if kind == "help": scene.show_help()
		elif kind == "door": scene.show_door_panel("player")
		else: scene.learning.show_journal()
		await settle()
		var panel: Control = scene.help_panel if kind == "help" else (scene.door_panel if kind == "door" else scene.learning.panel)
		var shade: Control = scene.help_backdrop if kind == "help" else (scene.door_backdrop if kind == "door" else scene.learning.modal_shade)
		var previous: Vector2 = panel.position
		viewport.size = Vector2i(1024,640)
		await settle()
		expect(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(panel.get_global_rect()) and panel.position == previous+Vector2(32,20), kind + " modal follows the viewport center when already open")
		expect(shade.get_global_rect() == Rect2(Vector2.ZERO,Vector2(viewport.size)) and scene.keyboard_blocked(), kind + " backdrop blocks the whole expanded viewport")
		reset_player(scene)
		viewport.size = Vector2i(960,600)
		await settle()
	# A journal opened on a large viewport must fit after shrinking as well.
	scene.learning.show_journal("bicicleta_de_mateo")
	await settle()
	var journal_id: int = scene.learning.panel.get_instance_id()
	var journal_focus: Control = viewport.gui_get_focus_owner()
	viewport.size = Vector2i(768,432)
	await settle()
	expect(scene.learning.panel.get_instance_id() == journal_id and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(scene.learning.panel.get_global_rect()), "shrinking a journal keeps the same panel completely inside the viewport")
	expect(is_instance_valid(journal_focus) and journal_focus.has_focus() and scene.learning.panel.is_ancestor_of(journal_focus), "shrinking the journal preserves the selected keyboard action")
	scene.learning.close()
	expect(scene.dialogue_job.is_empty() and not scene.decision_pending and scene.colony.minute == 480, "responsive interactions never query a provider or advance simulation")
	scene.free()
	viewport.free()
	print("RESPONSIVE: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
