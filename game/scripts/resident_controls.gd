extends RefCounted
## Quiet pixel controls for the resident sheet, using the existing HUD atlas.
const Icons = preload("res://scripts/hud_icons.gd")
const INK := Color("303e37")
const PAPER := Color("f4edda")

static func surface(fill: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new()
	skin.bg_color = fill
	skin.anti_aliasing = false
	skin.border_color = border
	skin.set_border_width_all(1 if border.a > 0.0 else 0)
	skin.content_margin_left = 4
	skin.content_margin_right = 4
	return skin

static func style(button: Button, active: bool = false) -> void:
	button.add_theme_stylebox_override("normal", surface(INK if active else Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", surface(Color("435847") if active else Color("e0e2cc")))
	button.add_theme_stylebox_override("pressed", surface(Color("53634c")))
	button.add_theme_stylebox_override("hover_pressed", surface(Color("435847")))
	button.add_theme_stylebox_override("focus", surface(Color.TRANSPARENT, Color("a85540")))
	button.add_theme_stylebox_override("disabled", surface(Color.TRANSPARENT))
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		button.add_theme_color_override(state, PAPER if active else INK)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	button.add_theme_constant_override("h_separation", 0)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func icon_button(host: Control, parent: Control, id: String, title: String, rect: Rect2, callback: Callable, active: bool = false, description: String = "") -> Button:
	var button: Button = host.button_at(parent, "", rect.position, rect.size, callback)
	button.icon = Icons.texture(id)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.accessibility_name = title
	button.accessibility_description = description
	button.tooltip_text = title + (" · " + description if not description.is_empty() else "")
	button.set_meta("resident_icon", id)
	style(button, active)
	return button

static func tabs(host: Control) -> void:
	var strip := Panel.new()
	strip.name = "ResidentTabs"
	strip.position = Vector2(12, 38)
	strip.size = Vector2(230, 36)
	strip.add_theme_stylebox_override("panel", surface(Color("e8e6d4")))
	host.inspector.add_child(strip)
	var keys := ["historia", "recuerdos", "aspecto", "hablar"]
	var titles := ["Historia", "Memoria", "Aspecto", "Hablar"]
	var icons := ["journal", "spark", "person", "people"]
	for index in range(keys.size()):
		var key: String = keys[index]
		var active: bool = host.page == key or (key == "historia" and host.page == "agenda")
		var button := icon_button(host, strip, icons[index], titles[index], Rect2(2 + index * 57, 2, 55, 32), func():
			if key == "hablar":
				host.talk_nearby()
				return
			host.page = key
			host.build_inspector()
			# Preserve keyboard navigation when rebuilding a tab's content.
			var next: Control = host.inspector.find_child("ResidentTab" + key.capitalize(), true, false)
			if is_instance_valid(next): next.grab_focus(), active)
		button.name = "ResidentTab" + key.capitalize()
		button.toggle_mode = key != "hablar"
		button.set_pressed_no_signal(active)
		if active:
			var marker := ColorRect.new()
			marker.color = Color("d9c894")
			marker.position = Vector2(19, 29)
			marker.size = Vector2(16, 2)
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(marker)

static func action_bar(host: Control, actions: Array) -> void:
	var strip := Panel.new()
	strip.name = "ResidentActions"
	strip.position = Vector2(12, 320)
	strip.size = Vector2(230, 36)
	strip.add_theme_stylebox_override("panel", surface(Color("e8e6d4")))
	host.inspector.add_child(strip)
	var width: float = floorf(226.0 / actions.size())
	for index in range(actions.size()):
		var action: Dictionary = actions[index]
		var button := icon_button(host, strip, action.icon, action.title, Rect2(2 + index * width, 2, width - 2, 32), action.callback, bool(action.get("primary", false)), str(action.get("hint", "")))
		button.name = str(action.get("name", "ResidentAction" + str(index)))
