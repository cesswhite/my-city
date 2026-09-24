extends SceneTree
## Layout regression checks after Godot has resolved fonts and minimum sizes.
## Run with -- --ui-test; no provider requests and no user save access.
const VIEWPORT_RECT := Rect2(0, 0, 768, 432)
const WORLD_RECT := Rect2(12, 48, 468, 244)
const MESSAGE_PANEL := Rect2(12, 348, 468, 72)

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in range(4):
		await process_frame

func controls_in(parent: Node, skip_scroll_contents: bool = true) -> Array[Control]:
	var result: Array[Control] = []
	for child in parent.get_children():
		if not child is Control or not child.is_visible_in_tree():
			continue
		if child is Label and child.text.is_empty():
			continue
		if child is Label or child is BaseButton or child is LineEdit or child is TextEdit or child is ScrollContainer:
			result.append(child)
		if child is ScrollContainer and skip_scroll_contents:
			continue
		result.append_array(controls_in(child, skip_scroll_contents))
	return result

func description_of(control: Control) -> String:
	if control is Label or control is BaseButton:
		return str(control.text).replace("\n", " ").left(35)
	return control.get_class()

func geometry_issues(controls: Array[Control], bounds: Rect2, check_overlap: bool = true) -> Array[String]:
	var issues: Array[String] = []
	for index in range(controls.size()):
		var control: Control = controls[index]
		var rect: Rect2 = control.get_global_rect()
		if not bounds.grow(0.1).encloses(rect):
			issues.append("%s leaves bounds: %s" % [description_of(control), rect])
		if not check_overlap:
			continue
		for other_index in range(index + 1, controls.size()):
			var other: Control = controls[other_index]
			# Wrapped suggestion captions intentionally occupy their parent button.
			# Keep checking containment, but do not mistake composition for overlap.
			if control.is_ancestor_of(other):
				if control is BaseButton and not rect.grow(0.1).encloses(other.get_global_rect()):
					issues.append("caption leaves button: " + description_of(other))
				continue
			if other.is_ancestor_of(control):
				if other is BaseButton and not other.get_global_rect().grow(0.1).encloses(rect):
					issues.append("caption leaves button: " + description_of(control))
				continue
			if rect.grow(-0.1).intersects(other.get_global_rect().grow(-0.1)):
				issues.append("%s overlaps %s" % [description_of(control), description_of(other)])
	return issues

func ancestor_scroll(node: Node) -> ScrollContainer:
	var parent: Node = node.get_parent()
	while is_instance_valid(parent):
		if parent is ScrollContainer:
			return parent
		parent = parent.get_parent()
	return null

func find_scroll(parent: Node) -> ScrollContainer:
	for child in parent.get_children():
		if child is ScrollContainer:
			return child
		var nested: ScrollContainer = find_scroll(child)
		if is_instance_valid(nested):
			return nested
	return null

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test so this fixture cannot access real progress.")
		quit(1)
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.colony._social._willingness_roll = func(): return 1.0
	await settle()
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	expect(scene.preview_mode and scene.paused and scene.colony.minute == 480, "layout fixture is isolated from saves and providers")
	expect(scene.inspector.get_global_rect() == Rect2(498, 48, 254, 368), "inspector retains its fixed viewport region")
	var header: Array[Control] = []
	var toolbar: Array[Control] = []
	for control in controls_in(scene):
		if control.get_global_rect().position.y < 48:
			header.append(control)
		if control is BaseButton and control.get_parent() == scene and control.position.y >= 292 and control.position.y < 348:
			toolbar.append(control)
	var issues := geometry_issues(header, Rect2(12, 0, 744, 44))
	expect(issues.is_empty(), "header labels and buttons have resolved sizes without overlap: " + "; ".join(issues))
	issues = geometry_issues(toolbar, Rect2(12, 292, 468, 56))
	expect(toolbar.size() >= 5 and issues.is_empty(), "world toolbar fits between map and message panel: " + "; ".join(issues))
	for button in toolbar:
		expect(not WORLD_RECT.intersects(button.get_global_rect()) and not MESSAGE_PANEL.intersects(button.get_global_rect()), "toolbar control stays outside map and messages: " + description_of(button))

	# Multiline and unbroken text must grow inside the scroll, never the HUD.
	var msg_scroll: ScrollContainer = scene.get("msg_scroll")
	expect(is_instance_valid(msg_scroll), "messages have a dedicated ScrollContainer")
	if not is_instance_valid(msg_scroll):
		scene.free()
		quit(1)
		return
	var original_scroll_rect: Rect2 = msg_scroll.get_global_rect()
	expect(original_scroll_rect == Rect2(24, 374, 444, 42), "message viewport leaves room for two native-size reading lines")
	var long_message := "LAYOUT-MESSAGE-ONLY\n" + "Una historia larga con acentos: César, Inés y Lupita recuerdan el café.\n".repeat(18) + "fin_".repeat(50)
	scene.message(long_message)
	await settle()
	expect(scene.log_label.text.contains(long_message), "long feedback retains the complete message for reading")
	expect(ancestor_scroll(scene.log_label) == msg_scroll and msg_scroll.clip_contents, "feedback is clipped by its message scroll viewport")
	expect(msg_scroll.get_global_rect() == original_scroll_rect and MESSAGE_PANEL.encloses(msg_scroll.get_global_rect()), "multiline minimum size cannot enlarge the message panel")
	expect(msg_scroll.get_v_scroll_bar().max_value > msg_scroll.get_v_scroll_bar().page, "long feedback can be read by scrolling")
	var readable_width: float = msg_scroll.size.x - msg_scroll.get_v_scroll_bar().size.x
	expect(scene.log_label.size.x <= readable_width + 0.1, "long words wrap before the visible message scrollbar instead of clipping sideways")
	msg_scroll.scroll_vertical = 10000
	await settle()
	expect(msg_scroll.scroll_vertical > 0 and msg_scroll.get_global_rect() == original_scroll_rect, "reading the end of feedback leaves toolbar geometry unchanged")
	var misplaced_copies := 0
	for control in controls_in(scene, false):
		if control is Label and control.text.contains("LAYOUT-MESSAGE-ONLY") and ancestor_scroll(control) != msg_scroll:
			misplaced_copies += 1
	expect(misplaced_copies == 0, "full feedback has no duplicate label across the map or toolbar")
	for button in toolbar:
		expect(not msg_scroll.get_global_rect().intersects(button.get_global_rect()), "long feedback cannot overlap toolbar control: " + description_of(button))

	# Use actual long resident content, then allow each page's containers to settle.
	var player: Dictionary = scene.colony.get_resident("player")
	player.name = "Estrellita del Valle"
	player.biography = "Nació junto al mercado y aprendió de las historias de sus vecinos. ".repeat(20)
	player.goal = "Aprender, recordar y compartir conocimientos con el barrio. ".repeat(12)
	player.activity = "Está escuchando una historia especialmente larga en el café. ".repeat(5)
	for index in range(30):
		scene.colony._remember(player, scene.colony._memory("fixture", ["player"], "Recuerdo %d. " % index + "Una conversación extensa que permanece dentro del cuaderno. ".repeat(10), "prueba de geometría"))
	# Old complete exchanges remain memories; a new encounter must not print them.
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	var original_mateo_pos: Array = mateo.pos.duplicate()
	mateo.pos = player.pos.duplicate()
	var recorded_history := true
	for index in range(6):
		recorded_history = scene.colony.record_dialogue("player", "mateo", "Pregunta anterior %d" % index, "CHAT-OLD-LAYOUT. Una respuesta anterior queda guardada en los recuerdos.", "prueba de geometría") and recorded_history
	expect(recorded_history, "chat layout fixture retains real earlier pair exchanges in memory")
	mateo.pos = original_mateo_pos
	for resident_id in ["player", "mateo"]:
		for page_name in ["historia", "recuerdos", "aspecto", "hablar", "agenda"]:
			scene.selected_id = resident_id
			scene.page = page_name
			scene.build_inspector()
			await settle()
			issues = geometry_issues(controls_in(scene.inspector), scene.inspector.get_global_rect())
			expect(issues.is_empty(), "%s/%s stays inside inspector without overlap: %s" % [resident_id, page_name, "; ".join(issues)])
			if resident_id == "player" and page_name in ["historia", "recuerdos", "hablar"]:
				var content_scroll: ScrollContainer = find_scroll(scene.inspector)
				expect(is_instance_valid(content_scroll) and content_scroll.clip_contents, page_name + " contains long resident text in a clipping scroll")
			if resident_id == "mateo" and page_name == "hablar":
				expect(not scene.chat_output.text.contains("CHAT-OLD-LAYOUT") and scene.chat_transcript_for("mateo").is_empty(), "opening chat does not repeat persistent conversation memories")
				mateo.pos = player.pos.duplicate()
				expect(scene.start_player_conversation("mateo"), "layout starts a new nearby encounter without requesting a provider")
				await settle()
				expect(scene.player_chat.messages("mateo").is_empty(), "new session starts with no old message bubbles")
				var memory_count: int = player.memories.size()
				for index in range(8):
					var job: Dictionary = {"a": "player", "b": "mateo", "first": "Pregunta actual %d para comprobar la lectura de esta charla." % index, "phase": "reply", "manual_session": true, "serial": scene.dialogue_serial}
					scene.player_chat.completed(job, "CHAT-SESSION-LAYOUT %d. Esta respuesta pertenece únicamente a nuestra conversación actual y debe poder leerse al desplazar el panel." % index, "prueba de geometría")
				await settle()
				expect(scene.player_chat.session_exchanges == 8 and player.memories.size() == memory_count + 8, "each complete current exchange enters both session display and persistent memory")
				expect(scene.chat_output.text.contains("CHAT-SESSION-LAYOUT 7") and not scene.chat_transcript_for("mateo").contains("CHAT-OLD-LAYOUT"), "only current encounter messages appear in the transcript")
				expect(scene.chat_scroll.clip_contents and scene.chat_scroll.get_v_scroll_bar().max_value > scene.chat_scroll.get_v_scroll_bar().page, "multiple current exchanges scroll inside the clipped chat viewport")
				issues = geometry_issues(controls_in(scene.inspector), scene.inspector.get_global_rect())
				expect(issues.is_empty(), "message bubbles and wrapped suggestions preserve inspector geometry: " + "; ".join(issues))
				scene.chat_scroll.scroll_vertical = 10000
				await settle()
				expect(scene.chat_scroll.scroll_vertical > 0, "the end of the current conversation remains reachable")
				scene.end_player_conversation()
				expect(scene.start_player_conversation("mateo"), "completed encounter can be reopened")
				await settle()
				expect(scene.player_chat.messages("mateo").is_empty() and scene.chat_transcript_for("mateo").is_empty() and player.memories.size() == memory_count + 8, "reopening clears visible chat while preserving all completed memories")
				scene.end_player_conversation()
				mateo.pos = original_mateo_pos

	scene.learning.last_message = "Resultado extenso: " + "El vecino explica cómo continuar sin perder tu progreso.\n".repeat(15)
	scene.learning.show_journal()
	await settle()
	issues = geometry_issues(controls_in(scene.learning.panel), scene.learning.panel.get_global_rect())
	expect(VIEWPORT_RECT.encloses(scene.learning.panel.get_global_rect()) and issues.is_empty(), "journal and long outcome remain inside their modal: " + "; ".join(issues))
	scene.learning.show_shop()
	await settle()
	issues = geometry_issues(controls_in(scene.learning.panel), scene.learning.panel.get_global_rect())
	expect(VIEWPORT_RECT.encloses(scene.learning.panel.get_global_rect()) and issues.is_empty(), "shop and long outcome remain inside their modal: " + "; ".join(issues))
	scene.learning.close()

	scene.get_viewport().gui_release_focus()
	scene.take_control()
	player.pos = [280.0, 180.0]
	player.target = player.pos.duplicate()
	scene.paused = false
	scene.show_help()
	await settle()
	var help_panel: Control = scene.get("help_panel")
	issues = geometry_issues(controls_in(help_panel), help_panel.get_global_rect())
	expect(is_instance_valid(help_panel) and VIEWPORT_RECT.encloses(help_panel.get_global_rect()) and issues.is_empty(), "help modal and its content fit the viewport: " + "; ".join(issues))
	var before: Vector2 = scene.position_of(player)
	Input.action_press("city_right")
	scene._process(0.1)
	Input.action_release("city_right")
	expect(scene.keyboard_blocked() and scene.position_of(player) == before, "help blocks real held movement")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(316, 180)
	scene._gui_input(click)
	expect(player.target == player.pos, "help blocks a world click from creating a route")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	scene._input(escape)
	await settle()
	expect(not is_instance_valid(scene.get("help_panel")) and not scene.keyboard_blocked(), "Escape closes help and releases its control block")
	scene.show_history()
	await settle()
	help_panel = scene.get("help_panel")
	issues = geometry_issues(controls_in(help_panel), help_panel.get_global_rect())
	expect(is_instance_valid(find_scroll(help_panel)) and VIEWPORT_RECT.encloses(help_panel.get_global_rect()) and issues.is_empty(), "message history provides a scroll inside the modal bounds: " + "; ".join(issues))
	scene._input(escape)
	await settle()
	expect(not is_instance_valid(scene.get("help_panel")), "Escape also closes message history")
	expect(scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not scene.decision_pending, "layout interactions made no provider request")
	scene.free()
	await process_frame
	print("LAYOUT: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
