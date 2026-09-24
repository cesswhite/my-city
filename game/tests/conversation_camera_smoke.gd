extends SceneTree
## Camera framing through real scene controls. No saved progress or providers.
const Navigation = preload("res://scripts/navigation.gd")
const Targets = preload("res://scripts/world_interactions.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func settle() -> void:
	for _frame in range(4): await process_frame

func pointer(viewport: SubViewport, at: Vector2, click: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	viewport.push_input(motion, true)
	if not click: return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)

func place_pair(scene: MainProbe, room: String, player_point: Vector2, other_point: Vector2) -> void:
	scene.player_chat.finish()
	scene.hide_inspector()
	scene.take_control()
	scene.overlay.dismiss_toast()
	scene.controls_active = true
	scene.paused = true
	for resident: Dictionary in scene.colony.residents:
		resident.room = str(resident.id)
		resident.pos = [236.0, 252.0]
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	for id: String in ["player", "mateo"]:
		var resident: Dictionary = scene.colony.get_resident(id)
		var point := player_point if id == "player" else other_point
		resident.room = room
		resident.pos = [point.x, point.y]
		resident.target = resident.pos.duplicate()
	scene.paths.clear()
	scene.update_room()

func positions(scene: MainProbe) -> Dictionary:
	var result := {}
	for resident: Dictionary in scene.colony.residents:
		result[resident.id] = {"pos":resident.pos.duplicate(), "room":resident.room, "target":resident.target.duplicate()}
	return result

func actor_screen_rect(scene: MainProbe, id: String) -> Rect2:
	var resident: Dictionary = scene.colony.get_resident(id)
	var rect: Rect2 = scene.pointer_actor_rect(resident, scene.colony.daily_state(id))
	# Use the actual actor node transform, independently of the inverse pointer helper.
	return scene.actors.get_global_transform() * rect

func clearly_visible(scene: MainProbe, id: String) -> bool:
	var bounds: Rect2 = actor_screen_rect(scene, id)
	if not bounds.has_area() or not Rect2(Vector2.ZERO, scene.size).encloses(bounds): return false
	for panel: Control in [scene.inspector, scene.hud.stats_panel, scene.hud.controls_panel, scene.hud.dock_panel]:
		if panel.is_visible_in_tree() and panel.get_global_rect().intersects(bounds): return false
	return true

func transforms_agree(scene: MainProbe) -> bool:
	for point: Vector2 in [Vector2(24,150), Vector2(236,210), Vector2(450,270)]:
		var screen: Vector2 = scene.world_to_screen(point)
		if scene.screen_to_world(screen).distance_to(point) > 0.001: return false
		for layer: Node2D in [scene.scenery, scene.actors, scene.atmosphere, scene.world_lights]:
			if (layer.get_global_transform() * point).distance_to(screen) > 0.001: return false
	return true

func centered_map(scene: MainProbe) -> bool:
	var expected := Rect2(((scene.size - scene.world_map_rect.size) / 2.0).round(), scene.world_map_rect.size)
	return scene.world_map_rect == expected

func visible_item(scene: MainProbe) -> Dictionary:
	for target: Dictionary in Targets._targets(scene.current_room, scene.home_project_state()):
		if target.kind != "item": continue
		var rect: Rect2 = target.rect
		for y in range(int(rect.position.y)+1, int(rect.end.y), 3):
			for x in range(int(rect.position.x)+1, int(rect.end.x), 3):
				var point := Vector2(x, y)
				var screen: Vector2 = scene.world_to_screen(point)
				if not scene.world_view_rect.has_point(screen) or scene.point_over_interface(screen): continue
				if scene.pick_world_target(point, scene.home_project_state()).get("key", "") == target.key:
					return {"target":target, "point":point, "screen":screen}
	return {}

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; refusing access to real saved progress.")
		quit(1)
		return
	root.size = Vector2i(768,432)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,432)
	root.add_child(viewport)
	var scene := MainProbe.new()
	scene.start_new_game = true
	scene.colony.save_path = "user://test_conversation_camera_%d.json" % OS.get_process_id()
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_url = ""
	scene.service_token = ""
	scene.use_jev = false
	scene.colony._social._willingness_roll = func(): return 1.0
	await settle()
	expect(scene.preview_mode and not scene.inspector.visible and centered_map(scene), "isolated world starts with its map centered and inspector hidden")
	var scenarios := [
		{"name":"east street", "room":"street", "player":Vector2(440,254), "other":Vector2(416,254)},
		{"name":"west street", "room":"street", "player":Vector2(36,200), "other":Vector2(60,200)},
		{"name":"interior", "room":"player", "player":Vector2(370,228), "other":Vector2(346,228)}
	]
	for dimensions: Vector2i in [Vector2i(768,432), Vector2i(960,600), Vector2i(1280,540)]:
		viewport.size = dimensions
		await settle()
		for scenario: Dictionary in scenarios:
			place_pair(scene, scenario.room, scenario.player, scenario.other)
			var label := "%d×%d %s" % [dimensions.x, dimensions.y, scenario.name]
			expect(Navigation.is_walkable(scenario.player, scenario.room) and Navigation.is_walkable(scenario.other, scenario.room), label + " fixture places both people on real walkable ground")
			var before: Dictionary = positions(scene)
			var old_scale: float = scene.world_scale
			var old_size: Vector2 = scene.world_map_rect.size
			scene.open_inspector("mateo", "historia")
			expect(clearly_visible(scene, "mateo") and clearly_visible(scene, "player"), label + " opening a nearby profile keeps both full sprites outside the inspector and HUD")
			expect(scene.world_scale == old_scale and scene.world_map_rect.size == old_size and positions(scene) == before, label + " profile framing preserves scale, positions and walking goals")
			expect(transforms_agree(scene), label + " scenery, actors, atmosphere, lighting and pointer share the current transform")
			expect(scene.start_player_conversation("mateo"), label + " legitimate nearby conversation starts without sending text")
			expect(clearly_visible(scene, "mateo") and clearly_visible(scene, "player"), label + " the active conversation keeps both people unobstructed")
			scene.open_inspector("cesar", "historia")
			expect(clearly_visible(scene, "mateo") and clearly_visible(scene, "player"), label + " an active conversation takes priority over another selected profile")
			scene.hide_inspector()
			expect(centered_map(scene) and scene.world_scale == old_scale and positions(scene) == before, label + " hiding the panel restores the centered map without moving any person")
			scene.player_chat.finish()

	# Keep a genuine encounter open during resize, including the existing draft.
	viewport.size = Vector2i(768,432)
	await settle()
	place_pair(scene, "street", Vector2(440,254), Vector2(416,254))
	scene.start_player_conversation("mateo")
	scene.chat_input.text = "Este borrador sigue conmigo."
	scene.chat_input.text_changed.emit()
	var editor_id: int = scene.chat_input.get_instance_id()
	var before_resize: Dictionary = positions(scene)
	for dimensions: Vector2i in [Vector2i(960,600), Vector2i(1280,540), Vector2i(768,432)]:
		viewport.size = dimensions
		await settle()
		expect(clearly_visible(scene,"mateo") and clearly_visible(scene,"player") and transforms_agree(scene), "%s resize reframes both interlocutors across every world layer" % dimensions)
		expect(positions(scene) == before_resize and scene.chat_input.get_instance_id() == editor_id and scene.chat_input.text == "Este borrador sigue conmigo.", "%s camera resize preserves physical state and the same draft editor" % dimensions)
	scene.close_chat_panel()

	# A visible interior item must be picked at the rendered, translated position.
	place_pair(scene,"player",Vector2(370,228),Vector2(346,228))
	scene.open_inspector("mateo","historia")
	var item: Dictionary = visible_item(scene)
	expect(not item.is_empty(), "translated interior retains a visible interactive item outside the overlays")
	if not item.is_empty():
		pointer(viewport,item.screen)
		expect(scene.interaction_hover.target.get("key", "") == item.target.key, "hover resolves the actual object at its camera-translated pixels")
		pointer(viewport,item.screen,true)
		var target: Vector2 = item.target.item.stand_at
		expect(scene.pending_item.get("id", "") == item.target.item.id and scene.colony.get_resident("player").target == [target.x,target.y], "clicking the same translated object keeps its physical interaction waypoint")

	scene.hide_inspector()
	expect(centered_map(scene) and transforms_agree(scene), "closing the final overlay restores the centered map and pointer transform")

	# Exercise production interpolation after isolated setup, without processing or saving.
	place_pair(scene,"street",Vector2(440,254),Vector2(416,254))
	var cesar: Dictionary = scene.colony.get_resident("cesar")
	cesar.room = "street"
	cesar.pos = [36.0,200.0]
	cesar.target = cesar.pos.duplicate()
	var physical_before: Dictionary = positions(scene)
	var centered: Rect2 = scene.world_map_rect
	scene.preview_mode = false
	scene.open_inspector("mateo","historia")
	expect(scene.world_map_rect == centered, "opening outside preview starts the camera transition without an instantaneous jump")
	scene.update_camera(0.06)
	var intermediate: Rect2 = scene.world_map_rect
	expect(intermediate != centered and transforms_agree(scene), "the first sixty milliseconds interpolate every world layer together")
	scene.open_inspector("cesar","historia")
	expect(scene.world_map_rect == intermediate, "retargeting during a camera transition starts from its current visible position")
	for _frame in range(4): scene.update_camera(0.06)
	expect(clearly_visible(scene,"cesar") and positions(scene) == physical_before and transforms_agree(scene), "retargeting finishes within 0.24 seconds without changing any physical position")
	var focused: Rect2 = scene.world_map_rect
	scene.hide_inspector()
	expect(scene.world_map_rect == focused, "closing outside preview begins a smooth return rather than snapping the world")
	for _frame in range(4): scene.update_camera(0.06)
	expect(centered_map(scene) and transforms_agree(scene), "the return transition restores the centered map within 0.24 seconds")
	scene.preview_mode = true
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and not scene.decision_pending and scene.colony.minute == 480, "camera interactions send no provider requests and never advance the world clock")
	scene.free()
	viewport.free()
	print("CONVERSATION CAMERA: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
