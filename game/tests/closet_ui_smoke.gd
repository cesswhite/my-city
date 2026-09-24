extends SceneTree
## Physical closet customization and the compact HUD. No saves or provider work.
## Add --capture to the usual -- --ui-test with a graphical renderer.
const Layout = preload("res://scripts/world_layout.gd")
const Targets = preload("res://scripts/world_interactions.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Seats = preload("res://scripts/seating.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var samples := 0
var invalid_samples := 0
var captures := 0
var capture_enabled := false
var save_path := "user://unused_closet_ui_%d.json" % OS.get_process_id()
var directory := ""

func _initialize() -> void: call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in range(5): await process_frame

func pointer(viewport: SubViewport, point: Vector2, pressed: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion,true)
	if not pressed: return
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	viewport.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)

func key(viewport: SubViewport, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)

func position(scene: MainProbe, room: String, point: Vector2) -> void:
	scene.clear_player_intentions()
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = room
	player.pos = [point.x,point.y]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	scene.update_room()
	scene.overlay.dismiss_toast()
	scene.interaction_hover.clear()

func fixture(viewport: SubViewport) -> MainProbe:
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = save_path
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = ""
	scene.service_url = ""
	scene.controls_active = true
	scene.paused = true
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = Layout.data().home_rest.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	position(scene,"street",Vector2(264,180))
	scene.hide_inspector()
	scene.refresh_status()
	return scene

func capture(viewport: SubViewport, scene: MainProbe, name: String) -> void:
	if not capture_enabled: return
	scene.actors.queue_redraw()
	await settle()
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	if picture == null or picture.is_empty() or picture.get_size() != viewport.size or picture.save_png(directory.path_join(name+".png")) != OK:
		failures.append("Could not capture " + name)
		push_error("Could not capture " + name)
	else:
		captures += 1
		print("CAPTURE: " + directory.path_join(name+".png"))

func closet_target(scene: MainProbe) -> Dictionary:
	for target: Dictionary in Targets._targets("player",scene.home_project_state()):
		if target.get("key","") == "player:item:closet": return target
	return {}

func walk(scene: MainProbe) -> void:
	var player: Dictionary = scene.colony.get_resident("player")
	for _frame in range(900):
		scene.move_resident(player,1.0/30.0)
		scene.resolve_player_arrival()
		scene.update_room()
		samples += 1
		if not Navigation.is_walkable(scene.position_of(player),player.room): invalid_samples += 1
		if scene.pending_item.is_empty() and not scene.pending_exit: break

func separated(scene: MainProbe, viewport: SubViewport, description: String) -> void:
	var panels: Array[Control] = [scene.hud.dock_panel,scene.hud.stats_panel,scene.hud.controls_panel,scene.overlay.toast,scene.overlay.hint,scene.inspector,scene.home_ui.reading_panel]
	var extent := Rect2(Vector2.ZERO,Vector2(viewport.size))
	var okay := true
	for i in range(panels.size()):
		if not panels[i].is_visible_in_tree(): continue
		var rect: Rect2 = panels[i].get_global_rect()
		if not extent.encloses(rect): okay = false
		for j in range(i+1,panels.size()):
			if panels[j].is_visible_in_tree() and rect.intersects(panels[j].get_global_rect()): okay = false
	expect(okay,description)

func hud_case(scene: MainProbe, viewport: SubViewport, prefix: String) -> void:
	var actions: Array[String] = []
	for child in scene.hud.dock_panel.get_children():
		if child is Button and child.is_visible_in_tree(): actions.append(str(child.get_meta("hud_icon","")))
	expect(actions == ["journal","bicycle"],prefix+"the lower menu has exactly Diario and Bicicleta")
	var dock: Rect2 = scene.hud.dock_panel.get_global_rect()
	expect(dock.position.x == 12 and dock.end.y == viewport.size.y-12 and dock.size.x <= 72 and dock.size.y <= 40,prefix+"the small dock stays at the lower left")
	var ai: Button = scene.hud.buttons.spark
	expect(ai.get_parent() == scene.hud.controls_panel and ai.get_global_rect().position.y < 50 and absf(ai.get_global_rect().position.x-scene.pause_button.get_global_rect().position.x) <= 36,prefix+"AI is a top control next to pause")
	var accessible := true
	for button: Button in [scene.hud.buttons.journal,scene.hud.buttons.bicycle,ai]:
		accessible = accessible and button.text.is_empty() and button.icon != null and button.focus_mode == Control.FOCUS_ALL and not button.accessibility_name.is_empty() and not button.tooltip_text.is_empty()
	expect(accessible,prefix+"compact action icons retain names, focus and tooltips")
	await capture(viewport,scene,prefix+"street")
	var bank := {}
	for seat: Dictionary in Seats.seats():
		var at: Vector2 = scene.world_to_screen(seat.rect.get_center())
		if seat.title == "Banco" and not scene.point_over_interface(at) and scene.world_view_rect.has_point(at):
			bank = seat
			break
	expect(not bank.is_empty(),prefix+"a real visible bank is available for pointer input")
	if bank.is_empty(): return
	var baseline: String = JSON.stringify(scene.colony.residents)
	pointer(viewport,scene.world_to_screen(bank.rect.get_center()))
	await settle()
	var hint: Rect2 = scene.overlay.hint.get_global_rect()
	expect(scene.interaction_hover.target.get("kind","") == "seat" and scene.hint_label.text.contains("Sentarte") and hint.end.x == viewport.size.x-12 and hint.end.y == viewport.size.y-12,prefix+"bank hover places its interaction label at the lower right")
	expect(scene.hint_label.get_line_count() == 1 and hint.size.y <= 32,prefix+"a one-line interaction hint stays compact after its text wraps")
	expect(JSON.stringify(scene.colony.residents) == baseline and scene.seating.pending_id.is_empty(),prefix+"hover gives feedback without sitting or changing the world")
	separated(scene,viewport,prefix+"bank hint remains clear of the two-action dock")
	await capture(viewport,scene,prefix+"bank-hover")
	var long_hint := "Clic: Revisar · Estación de trabajo para preparar y ordenar los materiales que reuniste en la colonia"
	scene.overlay.show_hint(long_hint)
	await settle()
	expect(scene.hint_label.text == long_hint and scene.hint_label.get_line_count() > 1 and scene.hint_label.get_visible_line_count() == scene.hint_label.get_line_count() and scene.overlay.hint.get_global_rect().encloses(scene.hint_label.get_global_rect()),prefix+"long interaction labels wrap completely inside their fitted panel")
	scene.message("Un aviso breve mientras recorres la colonia.")
	await settle()
	separated(scene,viewport,prefix+"notice and hover feedback never cover each other")
	scene.open_inspector("cesar","historia")
	await settle()
	separated(scene,viewport,prefix+"notice and profile stay clear of the minimal HUD")
	scene.hide_inspector()
	scene.overlay.dismiss_toast()

func editable_name(scene: MainProbe) -> LineEdit:
	for child in scene.inspector.find_children("*","LineEdit",true,false):
		if child.is_visible_in_tree() and child.editable: return child
	return null

func closet_case(scene: MainProbe, viewport: SubViewport, prefix: String) -> void:
	position(scene,"player",Layout.point(Layout.data().entry))
	await settle()
	var target := closet_target(scene)
	expect(not target.is_empty() and target.action == "personalizar",prefix+"the physical cabinet resolves to the player's closet")
	if target.is_empty(): return
	var player: Dictionary = scene.colony.get_resident("player")
	var before: Dictionary = player.appearance.duplicate(true)
	var name_before: String = player.name
	var memories: int = player.memories.size()
	expect(not scene.can_edit_appearance("player") and not scene.can_edit_appearance("cesar"),prefix+"appearance editing requires the player's own nearby closet")
	scene.open_inspector("player","aspecto")
	expect(editable_name(scene) == null,prefix+"the remote appearance page is read-only")
	scene.change_look(scene.APPEARANCE[0],1)
	expect(player.appearance == before,prefix+"a remote appearance callback cannot change the character")
	scene.hide_inspector()
	key(viewport,KEY_E)
	expect(not scene.inspector.visible,prefix+"E from the entry cannot open the distant closet")
	# The entry is deliberately near the exit; E may validly return outside.
	position(scene,"player",Layout.point(Layout.data().entry))
	pointer(viewport,scene.world_to_screen(target.rect.get_center()))
	await capture(viewport,scene,prefix+"closet")
	pointer(viewport,scene.world_to_screen(target.rect.get_center()),true)
	expect(scene.pending_item.get("id","") == "closet" and not scene.inspector.visible and player.appearance == before and player.memories.size() == memories,prefix+"clicking the distant closet schedules approach without editing or reading")
	walk(scene)
	await settle()
	expect(scene.inspector.visible and scene.page == "aspecto" and scene.selected_id == "player" and scene.position_of(player).distance_to(target.item.stand_at) < 5,prefix+"only physical arrival opens the editable appearance page")
	expect(scene.can_edit_appearance("player") and not scene.home_ui.is_reading() and player.memories.size() == memories,prefix+"the closet offers customization rather than an object-memory reader")
	var field := editable_name(scene)
	expect(is_instance_valid(field),prefix+"the name field is editable at the closet")
	if is_instance_valid(field):
		field.text = "Íñigo de la Colonia"
		field.text_changed.emit(field.text)
	expect(player.name == "Íñigo de la Colonia",prefix+"editing the real name control changes only the player")
	var spec: Array = scene.APPEARANCE[0]
	var next: Button
	for child in scene.inspector.find_children("*","Button",true,false):
		if child.tooltip_text == "Siguiente: " + str(spec[1]).to_lower(): next = child
	expect(is_instance_valid(next),prefix+"appearance choices expose a named next action")
	if is_instance_valid(next): pointer(viewport,next.get_global_rect().get_center(),true)
	await settle()
	expect(player.appearance[spec[0]] == posmod(int(before[spec[0]])+1,spec[2].size()),prefix+"the visible appearance action changes the selected feature")
	await capture(viewport,scene,prefix+"customize")
	key(viewport,KEY_ESCAPE)
	expect(not scene.inspector.visible and not scene.keyboard_blocked(),prefix+"Escape closes customization and restores game control")
	position(scene,"player",target.item.stand_at+Vector2(0,12))
	key(viewport,KEY_E)
	expect(scene.pending_item.get("id","") == "closet" and not scene.inspector.visible,prefix+"nearby E still starts a physical approach to the closet")
	walk(scene)
	expect(scene.inspector.visible and scene.page == "aspecto",prefix+"keyboard arrival opens the same customization page")
	var before_movement: Vector2 = scene.position_of(player)
	scene.move_player_keyboard(Vector2.DOWN,0.1)
	expect(scene.position_of(player) != before_movement and not scene.inspector.visible and not scene.keyboard_blocked(),prefix+"manual movement leaves customization and returns control to the world")
	position(scene,"player",Layout.point(Layout.data().entry))
	var changed: Dictionary = player.appearance.duplicate(true)
	scene.change_look(spec,1)
	expect(not scene.can_edit_appearance("player") and player.appearance == changed,prefix+"leaving the closet revokes appearance changes")
	# The reader and notification remain usable with the new small dock.
	scene.home_ui.show_item({"room":"player","title":"Una postal de bienvenida","text":"Puedes conocer a tus vecinos y aprender a tu ritmo."})
	scene.message("La descripción queda abierta mientras decides qué hacer.")
	await settle()
	separated(scene,viewport,prefix+"reader and notice avoid each other and the small dock")
	scene.home_ui.close()
	scene.overlay.dismiss_toast()
	scene.go_outside()
	walk(scene)
	expect(player.room == Layout.home_area("player") and scene.position_of(player).distance_to(Layout.door_positions().player) < 5,prefix+"leaving the house still follows the physical exit")
	expect(player.name != name_before and player.appearance == changed,prefix+"closing and leaving retain the chosen in-memory appearance")

func ai_defaults(scene: MainProbe) -> void:
	scene.service_token = "fixture-local-token-never-sent"
	scene.preview_mode = true
	scene.apply_ai_startup_default()
	expect(not scene.use_jev,"isolated previews keep AI disabled even with a synthetic token")
	scene.preview_mode = false
	scene.apply_ai_startup_default()
	expect(scene.use_jev,"normal startup enables AI when the local service is configured")
	scene.service_token = ""
	scene.apply_ai_startup_default()
	expect(not scene.use_jev,"normal startup without a token remains local")
	scene.preview_mode = true
	scene.apply_ai_startup_default()
	expect(scene.provider_calls == 0 and not scene.decision_pending and scene.dialogue_job.is_empty(),"configuration defaults never dispatch a provider request")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ui-test" not in args:
		push_error("Requires -- --ui-test; real progress must remain untouched.")
		quit(1)
		return
	capture_enabled = "--capture" in args
	if capture_enabled and DisplayServer.get_name() == "headless":
		push_error("Captures require a graphical renderer.")
		quit(1)
		return
	directory = ProjectSettings.globalize_path("res://../artifacts/closet-ui")
	if capture_enabled: DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for size: Vector2i in [Vector2i(768,432),Vector2i(960,540)]:
		viewport.size = size
		var scene := fixture(viewport)
		await settle()
		expect(scene.preview_mode and not scene.use_jev and not scene.save_allowed,"the fixture starts isolated with all provider decisions disabled")
		var prefix := "%dx%d-" % [size.x,size.y]
		await hud_case(scene,viewport,prefix)
		await closet_case(scene,viewport,prefix)
		if size.x == 768: ai_defaults(scene)
		expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not FileAccess.file_exists(save_path),prefix+"the flow creates no provider job or saved progress")
		scene.free()
		await process_frame
	expect(invalid_samples == 0,"all %d physical approach and exit samples remain walkable" % samples)
	viewport.free()
	await process_frame
	print("CLOSET UI: %d/%d checks passed; %d movement samples; %d captures" % [checks-failures.size(),checks,samples,captures])
	quit(0 if failures.is_empty() else 1)
