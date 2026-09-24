extends RefCounted
const Layout = preload("res://scripts/world_layout.gd")
## Interior presentation only. Discoveries are still recorded after physical arrival.
const Overlay = preload("res://scripts/world_overlay.gd")
const Details = preload("res://scripts/home_details.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Navigation = preload("res://scripts/navigation.gd")
const INK := Color("303e37")
const PAPER := Color("f4edda")
var host: Control
var location_panel: Panel
var subtitle: Label
var reading_panel: Panel
var reading_title: Label
var reading_body: Label
var reading_scroll: ScrollContainer
var close_button: Button
var reading_room := ""
var _reader_height := 172.0
var current_item: Dictionary = {}
var page_index := -1
var actions_row: HBoxContainer
var page_label: Label
var previous_button: Button
var next_button: Button
var feedback: Label
var vignette: MemoryVignette

class MemoryVignette extends Control:
	var scene: Array = []
	func _draw() -> void:
		if scene.is_empty(): return
		if scene[0].has("at"):
			var origin := Vector2(floorf((size.x - 160.0) / 2.0), 0)
			for part: Dictionary in scene:
				var info: Dictionary = Sprites.frame_info(str(part.asset))
				if not info.is_empty():
					Sprites.draw_asset(self, str(part.asset), Rect2(origin + Vector2(float(part.at[0]), float(part.at[1])), info.source.size))
			return
		var total := 0.0
		for part: Dictionary in scene:
			var info: Dictionary = Sprites.frame_info(str(part.asset))
			if not info.is_empty(): total += info.source.size.x + 12
		var x: float = floorf((size.x - maxf(0, total - 12)) / 2.0)
		for part: Dictionary in scene:
			var info: Dictionary = Sprites.frame_info(str(part.asset))
			if info.is_empty(): continue
			var native_size: Vector2 = info.source.size
			Sprites.draw_asset(self, str(part.asset), Rect2(Vector2(x, size.y - native_size.y - 4).floor(), native_size))
			x += native_size.x + 12

func _init(owner: Control) -> void:
	host = owner

func build() -> void:
	location_panel = Panel.new()
	location_panel.name = "HomeLocation"
	location_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	location_panel.add_theme_stylebox_override("panel", Overlay.surface())
	host.add_child(location_panel)
	host.room_label = host.label_at(location_panel, "", Vector2(12, 3), Vector2(146, 20), 16, PAPER)
	host.room_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle = host.label_at(location_panel, "", Vector2(12, 22), Vector2(146, 18), 16, Color("c3cfb8"))
	host.exit_button = host.button_at(location_panel, "Salir", Vector2(164, 6), Vector2(48, 32), func():
		if Layout.is_outdoor(host.current_room): host.neighborhood.show_map()
		else: host.go_outside(), "Salir a la colonia. Camina hasta la puerta.")
	host.exit_button.name = "HomeExit"
	host.exit_button.accessibility_name = "Salir a la colonia"
	host.hud._style_action(host.exit_button)
	location_panel.hide()
	host.exit_button.hide()
	_build_reader()

func _build_reader() -> void:
	reading_panel = Panel.new()
	reading_panel.name = "HomeObjectReader"
	reading_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	reading_panel.add_theme_stylebox_override("panel", Overlay.surface())
	host.add_child(reading_panel)
	var margin := MarginContainer.new()
	reading_panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	stack.add_child(header)
	reading_title = _text(header, "", 16, PAPER)
	reading_title.name = "HomeObjectTitle"
	reading_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button = host.button_at(header, "×", Vector2.ZERO, Vector2(24, 24), close, "Cerrar · Esc")
	close_button.name = "CloseHomeObject"
	close_button.custom_minimum_size = Vector2(24, 24)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.accessibility_name = "Cerrar recuerdo del objeto"
	host.hud._style_action(close_button)
	reading_scroll = ScrollContainer.new()
	reading_scroll.name = "HomeObjectScroll"
	reading_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	reading_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reading_scroll.custom_minimum_size.y = 48
	stack.add_child(reading_scroll)
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 8)
	reading_scroll.add_child(gutter)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	gutter.add_child(content)
	vignette = MemoryVignette.new()
	vignette.name = "HomeMemoryVignette"
	vignette.custom_minimum_size.y = 64
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.clip_contents = true
	vignette.hide()
	content.add_child(vignette)
	reading_body = _text(content, "", 14, PAPER)
	reading_body.name = "HomeObjectDescription"
	reading_body.add_theme_constant_override("line_spacing", 4)
	feedback = _text(content, "", 14, Color("c3cfb8"))
	feedback.name = "HomeObjectFeedback"
	feedback.hide()
	actions_row = HBoxContainer.new()
	actions_row.name = "HomeObjectActions"
	actions_row.add_theme_constant_override("separation", 8)
	stack.add_child(actions_row)
	actions_row.hide()
	reading_panel.hide()

func _text(parent: Node, text: String, font_size: int = 16, color: Color = INK) -> Label:
	var label: Label = host.label_at(parent, text, Vector2.ZERO, Vector2.ZERO, font_size, color)
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_constant_override("line_spacing", 4)
	return label

func is_reading() -> bool:
	return is_instance_valid(reading_panel) and reading_panel.visible

func owns_keyboard() -> bool:
	if not is_reading() or page_index < 0: return false
	var focused: Control = host.get_viewport().gui_get_focus_owner()
	return is_instance_valid(focused) and reading_panel.is_ancestor_of(focused)

func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or not owns_keyboard(): return false
	if event.keycode not in [KEY_LEFT, KEY_RIGHT]: return false
	turn_page(-1 if event.keycode == KEY_LEFT else 1)
	return true

func refresh() -> void:
	if not is_instance_valid(location_panel): return
	var inside: bool = not Layout.is_outdoor(host.current_room)
	location_panel.show()
	host.exit_button.show()
	if inside:
		host.room_label.text = "Tu casa" if host.current_room == "player" else "Casa de " + str(host.colony.get_resident(host.current_room).name)
		subtitle.text = "Descansa y crea" if host.current_room == "player" else "De visita"
		host.exit_button.text = "Salir"
		host.exit_button.tooltip_text = "Salir a " + Layout.area_title(Layout.home_area(host.current_room))
		host.exit_button.accessibility_name = "Salir de la casa"
	else:
		host.room_label.text = Layout.area_title(host.current_room)
		host.exit_button.text = "M"
		host.exit_button.tooltip_text = "Mapa del barrio · M"
		host.exit_button.accessibility_name = "Abrir mapa del barrio"
	subtitle.visible = inside
	location_panel.tooltip_text = host.room_label.text
	if is_reading() and (reading_room != host.current_room or host.colony.is_sleeping("player")):
		close()

func layout() -> void:
	if not is_instance_valid(location_panel): return
	var extent: Vector2 = host.layout_size()
	var side_open: bool = host.inspector.visible or is_reading()
	var left: float = host.hud.stats_panel.get_rect().end.x + 12
	var right: float = extent.x - 282 if side_open else host.hud.controls_panel.position.x - 12
	var width: float = minf(224, right - left)
	var inside: bool = not Layout.is_outdoor(host.current_room)
	location_panel.size = Vector2(width, 44 if inside else 32)
	location_panel.position = Vector2(clampf((extent.x - width) / 2.0, left, right - width), 12).round()
	host.exit_button.position = Vector2(width - 60, 6) if inside else Vector2(width-32,4)
	host.exit_button.size = Vector2(48, 32) if inside else Vector2(24,24)
	host.room_label.position = Vector2(12,3) if inside else Vector2(10,8)
	host.room_label.size = Vector2(width - (80 if inside else 48),20 if inside else 16)
	host.room_label.add_theme_font_size_override("font_size",16 if inside else 14)
	subtitle.size.x = width - 80
	reading_panel.size = Vector2(254, minf(_reader_height, extent.y - 108))
	reading_panel.position = Vector2(extent.x - 270, extent.y - reading_panel.size.y - 16)

func show_item(item: Dictionary) -> void:
	# This presentation is called only once the world validates arrival.
	if str(item.get("room", "")) != host.current_room: return
	# A player can open another interface while still approaching an object.
	# Arrival must not dismiss that newer interface or steal its keyboard focus.
	if host._menu_suspended or host.inspector.visible or is_instance_valid(host.learning.panel) or is_instance_valid(host.settlement_ui.panel) or is_instance_valid(host.help_panel) or is_instance_valid(host.door_panel) or is_instance_valid(host.sleep_ui.panel): return
	reading_room = host.current_room
	current_item = item.duplicate(true)
	page_index = -1
	reading_title.text = str(item.title)
	reading_body.text = str(item.text).strip_edges()
	feedback.hide()
	vignette.hide()
	_show_visible_activity()
	_build_actions()
	reading_scroll.scroll_vertical = 0
	reading_panel.show()
	host.overlay.dismiss_toast()
	host.interaction_hover.clear()
	host.apply_responsive_layout()
	close_button.grab_focus()
	host.update_hint()
	_fit_reader.call_deferred()

func _fit_reader() -> void:
	if not is_instance_valid(host) or not host.is_inside_tree(): return
	await host.get_tree().process_frame
	if not is_instance_valid(host) or not is_reading(): return
	# Text containers have resolved their wrapped heights by this point. Short
	# observations use a smaller card; longer descriptions keep a scroll area.
	var controls_height: float = 40.0 if actions_row.visible else 0.0
	var image_height: float = 72.0 if vignette.visible else 0.0
	var feedback_height: float = feedback.get_combined_minimum_size().y + 8 if feedback.visible else 0.0
	_reader_height = clampf(36 + maxf(24, reading_title.get_combined_minimum_size().y) + reading_body.get_combined_minimum_size().y + controls_height + image_height + feedback_height, 148 if actions_row.visible else 108, 228 if page_index >= 0 else 172)
	layout()

func _button(text: String, action: Callable, hint: String) -> Button:
	var button: Button = host.button_at(actions_row, text, Vector2.ZERO, Vector2(32, 28), action, hint)
	button.custom_minimum_size = Vector2(32, 28)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = hint
	host.hud._style_action(button)
	button.add_theme_font_size_override("font_size", 14)
	return button

func _show_visible_activity() -> void:
	if reading_room == "player" or str(current_item.get("prop_key", "")) != "project": return
	var owner: Dictionary = host.colony.get_resident(reading_room)
	var player: Dictionary = host.colony.get_resident("player")
	if owner.is_empty() or owner.get("room", "") != reading_room or host.colony.is_sleeping(reading_room): return
	var from: Vector2 = host.position_of(player)
	var to: Vector2 = host.position_of(owner)
	if from.distance_to(to) > 52 or not Navigation._clear_segment(from, to, reading_room): return
	var activity: String = str(owner.get("activity", "")).strip_edges()
	if activity.is_empty(): return
	feedback.text = str(owner.name) + " · " + activity
	feedback.show()

func _build_actions() -> void:
	for child: Node in actions_row.get_children():
		actions_row.remove_child(child)
		child.queue_free()
	actions_row.hide()
	if not bool(current_item.get("environment", false)): return
	var pages: Array = current_item.get("pages", [])
	if page_index >= 0:
		previous_button = _button("‹", func(): turn_page(-1), "Página anterior")
		previous_button.disabled = page_index == 0
		page_label = _text(actions_row, "%d / %d" % [page_index + 1, pages.size()], 14, Color("c3cfb8"))
		page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		page_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		page_label.accessibility_name = "Página %d de %d" % [page_index + 1, pages.size()]
		next_button = _button("›", func(): turn_page(1), "Página siguiente")
		next_button.disabled = page_index >= pages.size() - 1
		actions_row.show()
		return
	for action: Dictionary in current_item.get("actions", []):
		var id: String = str(action.id)
		var label: String = str(action.label)
		if id == "curtains":
			var home: Dictionary = host.colony.environment.view().get("households", {}).get(reading_room, {})
			label = "Abrir cortinas" if bool(home.get("curtains", {}).get(str(current_item.prop_key), false)) else "Cerrar cortinas"
		var button := _button(label, func(): activate_action(id), label)
		button.set_meta("house_action", id)
		actions_row.show()

func _still_near() -> bool:
	if not is_reading() or reading_room != host.current_room or host.colony.is_sleeping("player") or host._menu_suspended: return false
	if not current_item.get("stand_at") is Vector2: return false
	return host.position_of(host.colony.get_resident("player")).distance_to(current_item.stand_at) <= 18.0

func activate_action(action: String) -> void:
	if not _still_near():
		close()
		return
	if action in ["album", "details"]:
		if not current_item.get("pages", []).is_empty(): _show_page(0)
		return
	var result: Dictionary = host.colony.environment.house_action(reading_room, str(current_item.prop_key), action)
	feedback.text = str(result.get("message", ""))
	feedback.visible = not feedback.text.is_empty()
	_build_actions()
	for child: Node in actions_row.get_children():
		if child is Button and child.get_meta("house_action", "") == action:
			child.grab_focus()
			break
	# A curtain changes both scenery and its light immediately, including when
	# the simulation is paused and no normal process frame will refresh them.
	host.update_room()
	if is_instance_valid(host.actors): host.actors.queue_redraw()
	_fit_reader.call_deferred()

func turn_page(direction: int) -> void:
	if not _still_near():
		close()
		return
	var next: int = page_index + direction
	if next >= 0 and next < current_item.get("pages", []).size(): _show_page(next)

func _show_page(index: int) -> void:
	var page: Dictionary = current_item.pages[index]
	var result: Dictionary = host.colony.environment.house_action(reading_room, str(current_item.prop_key), "page:" + str(page.id))
	if not bool(result.get("ok", false)):
		feedback.text = str(result.get("message", "No puedes leer esta página ahora."))
		feedback.show()
		_fit_reader.call_deferred()
		return
	page_index = index
	reading_title.text = str(page.title)
	reading_body.text = str(page.text)
	feedback.hide()
	vignette.scene = page.get("scene", [])
	vignette.visible = not vignette.scene.is_empty()
	vignette.queue_redraw()
	reading_scroll.scroll_vertical = 0
	_build_actions()
	# Rebuilding controls preserves a usable focus target at both ends of an album.
	if not next_button.disabled: next_button.grab_focus()
	elif not previous_button.disabled: previous_button.grab_focus()
	else: close_button.grab_focus()
	_fit_reader.call_deferred()

func close() -> void:
	if not is_reading(): return
	var focused: Control = host.get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and reading_panel.is_ancestor_of(focused): host.get_viewport().gui_release_focus()
	reading_panel.hide()
	reading_room = ""
	current_item.clear()
	page_index = -1
	host.apply_responsive_layout()
	host.update_hint()

func pointer_over(at: Vector2) -> bool:
	for panel: Panel in [location_panel, reading_panel]:
		if is_instance_valid(panel) and panel.is_visible_in_tree() and panel.get_global_rect().has_point(host.get_global_transform() * at):
			return true
	return false
