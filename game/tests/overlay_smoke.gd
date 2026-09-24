extends SceneTree
## Full-bleed overlays and an actual in-memory streamed encounter. No save/provider access.
const Targets = preload("res://scripts/world_interactions.gd")
const Navigation = preload("res://scripts/navigation.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void:
		provider_calls += 1
		stream_text = ""
		dialogue_request._reset_state()
		dialogue_request.busy = true
		dialogue_request.set_process(false)
	func decide_with_jev() -> void:
		provider_calls += 1

var checks := 0
var failures: Array[String] = []
var menu_requests := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures.append(description)
		push_error(description)

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

func key(viewport: SubViewport, code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)

func place_pair(scene) -> void:
	for resident: Dictionary in scene.colony.residents:
		resident.room = str(resident.id)
		resident.pos = [236.0,252.0]
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	for id in ["player", "mateo"]:
		var resident: Dictionary = scene.colony.get_resident(id)
		resident.room = "street"
		resident.pos = [264.0 if id == "player" else 280.0,180.0]
		resident.target = resident.pos.duplicate()
	scene.clear_player_intentions()
	scene.update_room()
	scene.controls_active = true
	scene.paused = true

func covered_ground(scene, panel: Control) -> Vector2:
	# Find real routable terrain beneath panel padding, without pressing a UI action.
	var bounds: Rect2 = panel.get_global_rect()
	for y in range(int(bounds.position.y)+2,int(bounds.end.y)-2,3):
		for x in range(int(bounds.position.x)+2,int(bounds.end.x)-2,3):
			var point := Vector2(x,y)
			var on_button := false
			for child in panel.find_children("*", "BaseButton", true, false):
				if child.is_visible_in_tree() and child.get_global_rect().has_point(point):
					on_button = true
					break
			if on_button or not scene.world_map_rect.has_point(point): continue
			var world: Vector2 = scene.screen_to_world(point)
			if not scene.pick_world_target(world).is_empty(): continue
			if Navigation.is_walkable(world, "street") and not Navigation.route(scene.position_of(scene.colony.get_resident("player")),world,"street").is_empty(): return point
	return Vector2.INF

func covered_target(scene, panel: Control) -> Vector2:
	# Camera framing may move a different doorway or item behind the same panel.
	for target: Dictionary in Targets._targets("street", {}):
		var rect: Rect2 = target.rect
		for y in range(int(rect.position.y), int(rect.end.y), 2):
			for x in range(int(rect.position.x), int(rect.end.x), 2):
				var point: Vector2 = scene.world_to_screen(Vector2(x, y))
				if not panel.get_global_rect().has_point(point): continue
				var on_button := false
				for child in panel.find_children("*", "BaseButton", true, false):
					if child.is_visible_in_tree() and child.get_global_rect().has_point(point): on_button = true
				if not on_button and not scene.pick_world_target(Vector2(x, y)).is_empty(): return point
	return Vector2.INF

func sse(scene, kind: String, data: Dictionary) -> void:
	scene.dialogue_request._accept_bytes(("event: " + kind + "\ndata: " + JSON.stringify(data) + "\n\n").to_utf8_buffer())

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Requires -- --ui-test; refusing to touch normal progress.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,432)
	root.add_child(viewport)
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	scene.menu_requested.connect(func(): menu_requests += 1)
	viewport.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0 # Overlay assertions do not depend on random willingness.
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_url = ""
	scene.service_token = "isolated-transport-not-sent"
	scene.overlay.dismiss_toast()
	place_pair(scene)
	expect(scene.preview_mode and not scene.inspector.visible, "the game opens into the world with no persistent inspector")
	expect(scene.world_view_rect == Rect2(Vector2.ZERO,Vector2(viewport.size)), "terrain occupies the entire gameplay viewport")
	var available := 0
	var samples := 0
	for y in range(4,viewport.size.y,8):
		for x in range(4,viewport.size.x,8):
			samples += 1
			if not scene.point_over_interface(Vector2(x,y)): available += 1
	print("VISIBLE WORLD: %.2f%%" % (100.0 * available / samples))
	expect(float(available) / samples > 0.90, "default floating controls leave over ninety percent of the viewport unobstructed")
	var dock_point := covered_ground(scene,scene.hud.dock_panel)
	expect(dock_point.is_finite() and scene.point_over_interface(dock_point), "dock padding covers reachable terrain in the fixture")
	var before_dock: Array = scene.colony.get_resident("player").target.duplicate()
	if dock_point.is_finite(): pointer(viewport,dock_point,true)
	expect(scene.colony.get_resident("player").target == before_dock and scene.interaction_hover.target.is_empty(), "floating dock padding blocks both movement clicks and world hover")
	scene.message("Un aviso breve para esta prueba.")
	expect(scene.overlay.toast.visible and scene.overlay.toast_until > Time.get_ticks_msec() and not scene.inspector.visible, "a notice appears temporarily without opening a permanent panel")
	var toast_point := covered_ground(scene,scene.overlay.toast)
	expect(toast_point.is_finite() and scene.point_over_interface(toast_point), "the temporary notice also covers real reachable terrain")
	if toast_point.is_finite(): pointer(viewport,toast_point,true)
	expect(scene.colony.get_resident("player").target == before_dock and scene.interaction_hover.target.is_empty(), "a notice cannot pass a movement click or object hover into the world")
	var history_count: int = scene.notice_history.size()
	await settle() # The notice must finish measuring its wrapped text before expiry.
	pointer(viewport,Vector2.ZERO)
	viewport.gui_release_focus()
	scene.overlay.toast_until = 1
	scene.overlay.refresh()
	expect(not scene.overlay.toast.visible and scene.notice_history.size() == history_count and scene.notice_history.back().text == "Un aviso breve para esta prueba.", "notice expiry frees the screen while retaining the entry in the optional history")
	var transform_before: Rect2 = scene.world_map_rect
	var scale_before: float = scene.world_scale
	pointer(viewport,scene.world_to_screen(Vector2(280,170)),true)
	expect(scene.inspector.visible and scene.selected_id == "mateo", "clicking a visible neighbor opens their inspector")
	expect(scene.world_map_rect.size == transform_before.size and scene.world_scale == scale_before, "the inspector may frame the people without resizing the world")
	var hidden_target: Vector2 = covered_target(scene, scene.inspector)
	expect(hidden_target.is_finite() and scene.point_over_interface(hidden_target), "a real interactive target remains covered by the visible inspector after camera framing")
	var before_target: Array = scene.colony.get_resident("player").target.duplicate()
	if hidden_target.is_finite(): pointer(viewport,hidden_target,true)
	expect(scene.pending_home.is_empty() and scene.pending_item.is_empty() and scene.colony.get_resident("player").target == before_target, "clicking the inspector cannot route to an interactive target behind it")
	expect(scene.interaction_hover.target.is_empty(), "the visible inspector also blocks object hover beneath it")
	key(viewport,KEY_ESCAPE,true)
	expect(scene.inspector.visible and menu_requests == 0, "holding Escape cannot repeatedly close overlays")
	key(viewport,KEY_ESCAPE)
	expect(not scene.inspector.visible and menu_requests == 0, "Escape closes the inspector before requesting the menu")
	key(viewport,KEY_ESCAPE)
	expect(menu_requests == 1, "a separate Escape requests the menu after overlays are dismissed")
	place_pair(scene)
	key(viewport,KEY_E)
	expect(scene.inspector.visible and scene.page == "hablar" and scene.chat_partner_id == "mateo", "keyboard interaction with a nearby neighbor opens the conversation overlay")
	scene.send_chat_text("¿Qué hacías antes de saludarme?")
	expect(scene.provider_calls == 1 and scene.chat_busy(), "the fixture begins one real streamed controller job through an in-memory boundary")
	scene.chat_input.text = "Mi siguiente pregunta todavía está aquí."
	scene.chat_input.text_changed.emit()
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_column(11)
	var draft: String = scene.chat_input.text
	var serial: int = scene.dialogue_serial
	scene.hide_inspector()
	expect(not scene.inspector.visible and not scene.typing_in_field() and str(scene.chat_drafts.get("mateo","")) == draft, "temporarily hiding a conversation retains the draft and releases editor focus")
	expect(scene.chat_busy() and scene.dialogue_serial == serial and scene.colony.conversation_holds.size() == 2, "folding the panel preserves the same voluntary encounter and reservations")
	sse(scene,"delta",{"text":"Estaba ordenando herramientas."})
	expect(not scene.inspector.visible and not scene.typing_in_field(), "streaming a hidden reply never reopens or focuses the inspector")
	sse(scene,"done",{"text":"Estaba ordenando herramientas.","source":"openai","suggestions":[]})
	await settle()
	expect(not scene.inspector.visible and not scene.typing_in_field() and scene.chat_partner_id == "mateo", "completion keeps the folded encounter hidden while retaining its session")
	expect(scene.colony.get_resident("mateo").memories.size() == 1 and scene.player_chat.messages("mateo").size() == 2, "a complete hidden reply still records the legitimate two-person exchange")
	scene.return_to_conversation()
	await settle()
	expect(scene.inspector.visible and scene.chat_input.text == draft and scene.player_chat.last_reply("mateo") == "Estaba ordenando herramientas." and not scene.chat_input.has_focus() and scene.chat_input.get_caret_column() == 11, "returning to the encounter restores its draft and received message")
	var editor_id: int = scene.chat_input.get_instance_id()
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_column(11)
	viewport.size = Vector2i(960,600)
	await settle()
	expect(scene.inspector.get_global_rect() == Rect2(690,16,254,568), "an open inspector repositions and grows with the full viewport")
	expect(scene.chat_input.get_instance_id() == editor_id and scene.chat_input.has_focus() and scene.chat_input.get_caret_column() == 11 and scene.chat_input.text == draft, "resizing an open overlay keeps the live editor, draft, focus and caret")
	scene.close_chat_panel()
	expect(not scene.inspector.visible and scene.chat_partner_id.is_empty() and scene.colony.conversation_holds.is_empty() and str(scene.chat_drafts.get("mateo","")).is_empty(), "ending the encounter explicitly hides its overlay and clears ephemeral dialogue state")
	expect(scene.provider_calls == 1 and scene.colony.minute == 480, "overlay operations never dispatch another provider request or advance this isolated world")
	scene.free()
	viewport.free()
	await process_frame
	print("OVERLAY: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
