extends SceneTree
## Real Control/font metrics after layout. No save access or provider requests.
const VIEW := Rect2(0, 0, 768, 432)
const SPANISH := "¿¡áéíóúüñÁÉÍÓÚÜÑ"
var checks: int = 0
var failures: Array[String] = []
var measured_fonts: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if condition: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in range(4): await process_frame

func visible_rect(control: Control) -> Rect2:
	var result: Rect2 = control.get_global_rect().intersection(VIEW)
	var node: Node = control.get_parent()
	while is_instance_valid(node):
		if node is Control and node.clip_contents: result = result.intersection(node.get_global_rect())
		node = node.get_parent()
	return result

func leaves(parent: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in parent.get_children():
		if child is Control and not child.is_visible_in_tree(): continue
		if child is Label or child is Button or child is LineEdit or child is TextEdit:
			if visible_rect(child).has_area(): result.append(child)
		result.append_array(leaves(child))
	return result

func text_of(control: Control) -> String:
	return str(control.text).replace("\n", " / ").left(45)

func font_metrics(control: Control) -> Dictionary:
	var font: Font = control.get_theme_font("font")
	var size: int = control.get_theme_font_size("font_size")
	var word_gap: float = font.get_string_size("a a", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x - font.get_string_size("aa", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return {"font": font, "family": font.get_font_name(), "size": size, "gap": word_gap, "height": font.get_height(size)}

func text_issues(parent: Node) -> Array[String]:
	var issues: Array[String] = []
	for control in leaves(parent):
		if not control is Label and not control is Button: continue
		if control.text.is_empty(): continue
		var metrics: Dictionary = font_metrics(control)
		var font: Font = metrics.font
		var size: int = metrics.size
		var key: String = "%s:%d" % [font.get_instance_id(), size]
		if not measured_fonts.has(key):
			measured_fonts[key] = {"family": metrics.family, "size": size, "word_gap": metrics.gap, "line_height": metrics.height}
			for character in SPANISH:
				if not font.has_char(character.unicode_at(0)):
					issues.append("Missing Spanish glyph %s at %dpx" % [character, size])
		if control is Button:
			var style: StyleBox = control.get_theme_stylebox("normal")
			var available: Vector2 = control.size - style.get_minimum_size()
			var text_size: Vector2 = font.get_multiline_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
			if control.icon != null:
				available.x -= control.icon.get_width() + control.get_theme_constant("h_separation")
			if text_size.x > available.x + 0.1 or text_size.y > available.y + 0.1:
				issues.append("Button text needs %s, has %s: %s" % [text_size, available, text_of(control)])
		else:
			if control.get_visible_line_count() < control.get_line_count():
				issues.append("Label clips lines %d/%d: %s" % [control.get_visible_line_count(), control.get_line_count(), text_of(control)])
			if control.autowrap_mode == TextServer.AUTOWRAP_OFF:
				for line in control.text.split("\n"):
					if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > control.size.x + 0.1:
						issues.append("Label text exceeds its width: " + text_of(control))
			if size >= 12 and control.text.length() > 40:
				if float(metrics.gap) < 2.0 or float(metrics.gap) > 8.0:
					issues.append("Reading word space is %.2fpx: %s" % [metrics.gap, text_of(control)])
				if control.get_line_count() > 1 and control.get_theme_constant("line_spacing") < 2:
					issues.append("Reading lines need a visible gap: " + text_of(control))
	return issues

func overlap_issues(parent: Node) -> Array[String]:
	var controls: Array[Control] = leaves(parent)
	var issues: Array[String] = []
	for index in range(controls.size()):
		var control: Control = controls[index]
		var rect: Rect2 = visible_rect(control)
		if not VIEW.grow(0.1).encloses(control.get_global_rect()) and not has_scroll_ancestor(control):
			issues.append("Control leaves the viewport: " + text_of(control))
		for next in range(index + 1, controls.size()):
			var other: Control = controls[next]
			if control.is_ancestor_of(other) or other.is_ancestor_of(control): continue
			if rect.grow(-0.1).intersects(visible_rect(other).grow(-0.1)):
				issues.append("%s overlaps %s" % [text_of(control), text_of(other)])
	return issues

func has_scroll_ancestor(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while is_instance_valid(parent):
		if parent is ScrollContainer: return true
		parent = parent.get_parent()
	return false

func inspect(parent: Node, page: String) -> void:
	await settle()
	var font_errors: Array[String] = []
	for control in leaves(parent):
		var metrics: Dictionary = font_metrics(control)
		if int(metrics.size) < 16 or (int(metrics.size) == 16 and not str(metrics.family).to_lower().contains("operator")):
			font_errors.append("%s at %dpx: %s" % [metrics.family, metrics.size, text_of(control)])
	expect(font_errors.is_empty(), page + " uses native 16px reading text and larger display titles: " + "; ".join(font_errors))
	var text_errors: Array[String] = text_issues(parent)
	expect(text_errors.is_empty(), page + " text fits its real font and padding: " + "; ".join(text_errors))
	var overlaps: Array[String] = overlap_issues(parent)
	expect(overlaps.is_empty(), page + " controls remain separate after fonts resolve: " + "; ".join(overlaps))
	var scroll_errors: Array[String] = []
	for scroll in parent.find_children("*", "ScrollContainer", true, false):
		if not scroll.is_visible_in_tree() or not visible_rect(scroll).has_area(): continue
		var bar: VScrollBar = scroll.get_v_scroll_bar()
		if bar.max_value > bar.page + 0.1:
			if not bar.is_visible_in_tree() or bar.size.x < 6 or visible_rect(bar).size.x < 6:
				scroll_errors.append("Overflow needs a visible scrollbar at least 6px wide: " + str(scroll.get_path()))
	expect(scroll_errors.is_empty(), page + " overflow has a visible scrollbar: " + "; ".join(scroll_errors))

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test to avoid real save access.")
		quit(1)
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_token = ""
	scene.use_jev = false
	scene.paused = true
	await settle()
	expect(scene.preview_mode and scene.colony.minute == 480, "typography fixture starts with isolated defaults")
	var player: Dictionary = scene.colony.get_resident("player")
	var person: Dictionary = scene.colony.get_resident("lupita")
	player.name = "María José"
	player.room = "street"
	player.pos = [264.0, 178.0]
	player.target = player.pos.duplicate()
	person.room = "street"
	person.pos = [280.0, 178.0]
	person.target = person.pos.duplicate()
	person.biography = "Creció con su mamá y su papá. Le gusta reunir a los vecinos y aprender sobre el huerto. ¿Qué historias compartirán mañana?"
	for page in ["historia", "aspecto", "agenda", "recuerdos"]:
		scene.open_inspector("player" if page == "aspecto" else "lupita", page)
		await inspect(scene, page)
	for index in range(5):
		scene.colony.record_dialogue("player", "lupita", "¿Qué te gustaría aprender?", "Me gustaría cultivar hierbas y compartir una taza de té con mis vecinos.", "Fixture local de tipografía")
	scene.selected_id = "lupita"
	scene.start_player_conversation("lupita")
	scene.page = "hablar"
	scene.build_inspector()
	await settle()
	var draft: String = "Sí, me gustaría aprender.\n¿Qué necesito llevar, Inés?"
	scene.chat_input.text = draft
	scene.chat_input.grab_focus()
	scene.chat_input.set_caret_line(1)
	scene.chat_input.set_caret_column(8)
	scene.dialogue_job = {"a": "player", "b": "lupita", "first": "¿Podemos hablar del huerto?", "phase": "reply", "manual_session": true, "serial": 9001}
	scene.stream_text = ""
	scene._dialogue_delta("Sí, podemos aprender a cuidar las plantas.")
	scene.build_inspector()
	await inspect(scene, "chat with active draft")
	expect(scene.chat_input.text == draft and scene.chat_drafts.lupita == draft, "streaming and rebuilding preserve the unsent Spanish draft exactly")
	expect(scene.chat_input.has_focus() and scene.chat_input.get_caret_line() == 1 and scene.chat_input.get_caret_column() == 8, "rebuilding preserves active caret and typing focus")
	expect(scene.chat_input.get_line_height() > 0 and scene.typing_in_field(), "active multiline editor has usable line metrics and blocks game keys")
	scene.end_player_conversation()
	scene.show_help()
	await inspect(scene.help_panel, "help")
	scene.close_help()
	scene.learning.show_journal("bicicleta_de_mateo")
	await inspect(scene.learning.panel, "journal")
	scene.learning.show_shop()
	await inspect(scene.learning.panel, "shop")
	scene.learning.close()
	expect(scene.dialogue_job.is_empty() and not scene.decision_pending and scene.visit_job.is_empty(), "font and layout checks schedule no provider work")
	print("FONT METRICS: " + JSON.stringify(measured_fonts.values()))
	scene.free()
	await process_frame
	print("TYPOGRAPHY: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
