extends RefCounted
## Lightweight floating feedback; the world keeps the same size underneath.
const PAPER := Color("f4edda")
const INK := Color("303e37")
var host: Control
var toast: Panel
var hint: Panel
var toast_until := 0
var toast_tween: Tween
var inspector_tween: Tween
var _notice_height := 92.0
var _notice_long := false
var _notice_revision := 0
var _notice_measuring := false

class Portrait extends Node2D:
	var host: Control
	func _draw() -> void:
		draw_style_box(host.sprite_box("message_panel"), Rect2(161, 84, 77, 76))
		preload("res://scripts/pixel_art.gd").draw_person(self, Vector2(199, 156), host.colony.get_resident(host.selected_id).appearance, 3)

func _init(owner: Control) -> void:
	host = owner

static func surface(light: bool = false) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.957, 0.929, 0.855, 1.0) if light else Color(0.10, 0.16, 0.13, 0.92)
	skin.border_color = Color(1, 1, 1, 0.10)
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(2)
	skin.shadow_color = Color(0, 0, 0, 0.22)
	skin.shadow_size = 3
	skin.shadow_offset = Vector2(0, 2)
	return skin

func build() -> void:
	host.inspector.add_theme_stylebox_override("panel", surface(true))
	host.inspector.hide()
	toast = Panel.new()
	toast.name = "WorldToast"
	toast.add_theme_stylebox_override("panel", surface())
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(toast)
	host.msg_scroll = ScrollContainer.new()
	host.msg_scroll.name = "NoticeScroll"
	host.msg_scroll.position = Vector2(10, 10)
	host.msg_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.msg_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	host.msg_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	host.msg_scroll.focus_mode = Control.FOCUS_ALL
	host.msg_scroll.accessibility_name = "Mensaje del juego"
	host.msg_scroll.tooltip_text = "Rueda o flechas para leer · Esc para cerrar"
	host.msg_scroll.gui_input.connect(_notice_scroll_input)
	toast.add_child(host.msg_scroll)
	var gutter := MarginContainer.new()
	gutter.mouse_filter = Control.MOUSE_FILTER_PASS
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 6)
	host.msg_scroll.add_child(gutter)
	host.log_label = Label.new()
	host.log_label.name = "NoticeText"
	host.log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.log_label.add_theme_font_size_override("font_size", 14)
	host.log_label.add_theme_color_override("font_color", PAPER)
	host.log_label.add_theme_constant_override("line_spacing", 4)
	host.log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gutter.add_child(host.log_label)
	host.feedback = host.log_label
	var close: Button = host.button_at(toast, "×", Vector2.ZERO, Vector2(24, 24), dismiss_toast, "Cerrar aviso")
	close.name = "DismissToast"
	close.accessibility_name = "Cerrar aviso"
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		var skin := StyleBoxFlat.new()
		skin.bg_color = Color(1, 1, 1, 0.10) if state in ["hover", "pressed"] else Color.TRANSPARENT
		if state == "focus":
			skin.border_color = Color("dfd3ad")
			skin.set_border_width_all(1)
		close.add_theme_stylebox_override(state, skin)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: close.add_theme_color_override(state, PAPER)
	var bar: VScrollBar = host.msg_scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 6
	for state in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var skin := StyleBoxFlat.new()
		skin.bg_color = Color(1, 1, 1, 0.12 if state == "scroll" else 0.5)
		skin.content_margin_left = 3
		skin.content_margin_right = 3
		skin.content_margin_top = 4
		skin.content_margin_bottom = 4
		bar.add_theme_stylebox_override(state, skin)
	host.provider_label = host.label_at(toast, "", Vector2.ZERO, Vector2.ZERO)
	host.provider_label.hide()
	toast.hide()
	hint = Panel.new()
	hint.name = "WorldHint"
	hint.add_theme_stylebox_override("panel", surface())
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(hint)
	host.hint_label = host.label_at(hint, "", Vector2(10, 4), Vector2(280, 16), 14, PAPER)
	host.hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.hint_label.clip_text = false
	host.hint_label.add_theme_constant_override("line_spacing", 2)
	host.hint_label.minimum_size_changed.connect(_reflow_hint)
	hint.hide()

func _reflow_hint() -> void:
	# Word wrapping resolves after width/text changes. Refit the small surface
	# when the label has its actual line height instead of keeping stale space.
	layout.call_deferred()

func layout() -> void:
	var dimensions: Vector2 = host.layout_size()
	host.inspector.position = Vector2(dimensions.x - 270, 16)
	host.inspector.size = Vector2(254, dimensions.y - 32)
	var reader_open: bool = is_instance_valid(host.home_ui) and host.home_ui.is_reading()
	_layout_notice(dimensions, reader_open)
	var right: float = host.inspector.position.x - 12 if host.inspector.visible else dimensions.x - 12
	if reader_open: right = minf(right, host.home_ui.reading_panel.position.x - 12)
	var hint_width: float = clampf(host.ui_font.get_string_size(host.hint_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20, 60, minf(300, right - 100))
	host.hint_label.size.x = hint_width - 20
	var text_height: float = host.hint_label.get_combined_minimum_size().y
	host.hint_label.size.y = text_height
	hint.size = Vector2(hint_width, maxf(24, text_height + 8))
	hint.position = Vector2(right - hint.size.x, dimensions.y - hint.size.y - 12).round()
	if is_instance_valid(host.world_labels): host.world_labels.queue_redraw()

func _local_rect(control: Control) -> Rect2:
	return host.get_global_transform().affine_inverse() * control.get_global_rect()

func _layout_notice(dimensions: Vector2, reader_open: bool) -> void:
	toast.size = Vector2(240, _notice_height)
	var right: float = dimensions.x - 12
	if host.inspector.visible: right = host.inspector.position.x - 12
	# A short reader leaves room below it. A tall one shares the left world area.
	if reader_open and host.home_ui.reading_panel.get_rect().end.y + 8 > dimensions.y - 12 - _notice_height:
		right = minf(right, host.home_ui.reading_panel.position.x - 12)
	var proposed := Rect2(Vector2(right - toast.size.x, dimensions.y - 12 - toast.size.y), toast.size)
	var obstacles: Array[Control] = []
	if is_instance_valid(host.hud.dock_panel): obstacles.append(host.hud.dock_panel)
	if is_instance_valid(host.sleep_ui) and is_instance_valid(host.sleep_ui.banner): obstacles.append(host.sleep_ui.banner)
	# Keep the right edge; lift only when the footer occupies the same pixels.
	for _pass in range(obstacles.size()):
		for obstacle: Control in obstacles:
			if not obstacle.is_visible_in_tree(): continue
			var occupied: Rect2 = _local_rect(obstacle).grow(8)
			if proposed.intersects(occupied): proposed.position.y = occupied.position.y - proposed.size.y
	toast.position = proposed.position.round()
	host.msg_scroll.size = Vector2(toast.size.x - 44, toast.size.y - 20)
	toast.get_node("DismissToast").position = Vector2(toast.size.x - 30, 4)

func portrait() -> void:
	var view := Portrait.new()
	view.host = host
	host.inspector.add_child(view)

func show_inspector() -> void:
	if is_instance_valid(inspector_tween): inspector_tween.kill()
	var was_visible: bool = host.inspector.visible
	host.inspector.show()
	host.inspector.modulate.a = 1.0
	if not was_visible and not host.preview_mode:
		host.inspector.modulate.a = 0.0
		inspector_tween = host.create_tween()
		inspector_tween.tween_property(host.inspector, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	host.apply_responsive_layout()

func hide_inspector() -> void:
	if is_instance_valid(inspector_tween): inspector_tween.kill()
	host.inspector.hide()
	host.inspector.modulate.a = 1.0
	host.apply_responsive_layout()

func show_notice() -> void:
	if is_instance_valid(toast_tween): toast_tween.kill()
	hint.hide()
	_notice_revision += 1
	_notice_height = 92
	_notice_long = false
	_notice_measuring = true
	toast_until = Time.get_ticks_msec() + 5500
	toast.modulate.a = 1.0
	toast.show()
	layout()
	_fit_notice.call_deferred(_notice_revision)

func _fit_notice(revision: int) -> void:
	if not is_instance_valid(host) or not host.is_inside_tree() or revision != _notice_revision: return
	# The callback disconnects with its owner if a scene closes before layout finishes.
	if not host.get_tree().process_frame.is_connected(_measure_notice):
		host.get_tree().process_frame.connect(_measure_notice, CONNECT_ONE_SHOT)

func _measure_notice() -> void:
	if not is_instance_valid(toast) or not toast.visible: return
	var content_height: float = host.log_label.get_combined_minimum_size().y
	_notice_height = clampf(content_height + 20, 40, 92)
	_notice_long = content_height > _notice_height - 20
	_notice_measuring = false
	layout()

func notice_has_focus() -> bool:
	if not is_instance_valid(toast) or not toast.visible: return false
	var focused: Control = host.get_viewport().gui_get_focus_owner()
	return is_instance_valid(focused) and (focused == toast or toast.is_ancestor_of(focused))

func _notice_scroll_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	var step: int = 24
	match event.keycode:
		KEY_DOWN: host.msg_scroll.scroll_vertical += step
		KEY_UP: host.msg_scroll.scroll_vertical -= step
		KEY_PAGEDOWN: host.msg_scroll.scroll_vertical += int(host.msg_scroll.size.y) - 8
		KEY_PAGEUP: host.msg_scroll.scroll_vertical -= int(host.msg_scroll.size.y) - 8
		KEY_HOME: host.msg_scroll.scroll_vertical = 0
		KEY_END: host.msg_scroll.scroll_vertical = int(host.msg_scroll.get_v_scroll_bar().max_value)
		_: return
	host.msg_scroll.accept_event()

func dismiss_toast() -> void:
	if notice_has_focus(): host.get_viewport().gui_release_focus()
	_notice_revision += 1
	_notice_measuring = false
	toast_until = 0
	if is_instance_valid(toast_tween): toast_tween.kill()
	toast.hide()
	host.update_hint()

func refresh() -> void:
	if toast.visible:
		var hovered: bool = toast.get_global_rect().has_point(host.get_global_mouse_position())
		if hovered or notice_has_focus() or _notice_long or _notice_measuring:
			if is_instance_valid(toast_tween): toast_tween.kill()
			toast.modulate.a = 1.0
			toast_until = Time.get_ticks_msec() + 5500
			return
	if toast.visible and toast_until > 0 and Time.get_ticks_msec() >= toast_until:
		toast_until = 0
		if host.preview_mode:
			toast.hide()
		else:
			toast_tween = host.create_tween()
			toast_tween.tween_property(toast, "modulate:a", 0.0, 0.18)
			toast_tween.tween_callback(toast.hide)
			host.update_hint()

func show_hint(text: String) -> void:
	host.hint_label.text = text
	hint.visible = not text.is_empty() and not toast.visible and not host._menu_suspended
	layout()

func pointer_over(at: Vector2) -> bool:
	return host.inspector.visible and host.inspector.get_rect().has_point(at) or toast.visible and toast.get_rect().has_point(at)
