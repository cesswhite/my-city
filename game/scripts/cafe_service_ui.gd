extends RefCounted
## Seated café service. Payment and consumption are validated by Colony.
const Sprites = preload("res://scripts/sprite_art.gd")
const Overlay = preload("res://scripts/world_overlay.gd")
var host: Control
var panel: Panel
var action_button: Button
var note: Label
var _locked_until := 0
var _notice := ""
var _notice_until := 0
var _seat_id := ""
var _signature: Array = []

func _init(owner: Control) -> void:
	host = owner

func build() -> void:
	panel = Panel.new()
	panel.name = "CafeActions"
	panel.add_theme_stylebox_override("panel", Overlay.surface())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(panel)
	action_button = host.button_at(panel, "", Vector2(8, 6), Vector2(240, 30), activate)
	action_button.name = "CoffeeAction"
	action_button.focus_mode = Control.FOCUS_ALL
	action_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host.style_button(action_button, true)
	note = host.label_at(panel, "", Vector2(8, 37), Vector2(240, 16), 16, Color("f4edda"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.clip_text = true
	panel.hide()
	layout()

func is_cafe_seat() -> bool:
	return host.seating.is_seated() and str(host.seating.active_seat().get("prop_key", "")).begins_with("cafe_table_")

func available() -> bool:
	return is_cafe_seat() and not host.keyboard_blocked() and not host._menu_suspended and not host.inspector.visible and host.is_visible_in_tree()

func layout() -> void:
	if not is_instance_valid(panel): return
	var dimensions: Vector2 = host.layout_size()
	panel.size = Vector2(256, 58)
	panel.position = Vector2((dimensions.x - panel.size.x) / 2, dimensions.y - 154).round()
	if is_instance_valid(host.overlay.toast) and host.overlay.toast.visible and panel.get_rect().intersects(host.overlay.toast.get_rect()):
		panel.position.y = host.overlay.toast.position.y - panel.size.y - 8

func refresh() -> void:
	if not is_instance_valid(panel): return
	var show: bool = available()
	if not show:
		var focused: Control = host.get_viewport().gui_get_focus_owner()
		if panel.visible and is_instance_valid(focused) and panel.is_ancestor_of(focused): host.get_viewport().gui_release_focus()
		panel.hide()
		_signature.clear()
		return
	var id: String = host.seating.active_id
	if _seat_id != id:
		_seat_id = id
		_notice = ""
	var offer: Dictionary = host.colony.coffee_offer(id)
	var locked: bool = Time.get_ticks_msec() < _locked_until
	var notice: String = _notice if Time.get_ticks_msec() < _notice_until else ""
	var signature: Array = [id, offer, locked, notice]
	if signature != _signature:
		_signature = signature.duplicate(true)
		action_button.text = "Beber café" if offer.has_coffee else "Pedir café · %d monedas" % int(offer.price)
		action_button.disabled = not offer.ok or locked
		var benefit: String = "+%d%% de energía" % int(offer.energy_gain)
		action_button.tooltip_text = ("Beber tu taza, sin otro cobro" if offer.has_coffee else "Pedir y pagar %d monedas" % int(offer.price)) + " · " + benefit + " al beber · C"
		if not notice.is_empty(): note.text = notice
		elif not offer.ok:
			note.text = "Te faltan %d monedas" % maxi(0, int(offer.price) - int(offer.coins)) if not offer.has_coffee and int(offer.coins) < int(offer.price) else str(offer.message)
		else: note.text = benefit + (" · C para beber" if offer.has_coffee else " · C para pedir")
		note.tooltip_text = note.text
	panel.show()
	layout()

func activate() -> void:
	if not available() or Time.get_ticks_msec() < _locked_until: return
	var id: String = host.seating.active_id
	var offer: Dictionary = host.colony.coffee_offer(id)
	if not offer.ok:
		refresh()
		return
	# Capture the intended action before mutation. A second click cannot become a sip.
	_locked_until = Time.get_ticks_msec() + 450
	var result: Dictionary = host.colony.drink_coffee(id) if offer.has_coffee else host.colony.order_coffee(id)
	_notice = ("Disfrutaste tu café" if offer.has_coffee else "Café servido") if result.ok else str(result.message)
	if result.ok and offer.has_coffee:
		var restored: float = float(result.get("energy_gained", 0.0))
		_notice = "Café tomado · +%s%% de energía" % String.num(restored, 2).trim_suffix("00").trim_suffix("0").trim_suffix(".") if restored > 0.0 else "Café tomado · Energía al máximo"
	_notice_until = Time.get_ticks_msec() + 2600
	if result.ok:
		host.colony.get_resident("player").activity = "Tomando café" if offer.has_coffee else "Sentado · Café servido"
		# This action already has concise feedback here; do not duplicate a world log.
		if not host.colony.events.is_empty(): host.seen_world_events[host.colony.events.back()] = true
	host.get_viewport().gui_release_focus()
	host.refresh_status()
	host.actors.queue_redraw()
	refresh()

func pointer_over(at: Vector2) -> bool:
	return is_instance_valid(panel) and panel.visible and panel.get_rect().has_point(at)

func draw_on_table(canvas: CanvasItem, object: Dictionary) -> void:
	if object.get("id", "") != "cafe_table" or not is_cafe_seat(): return
	var seat: Dictionary = host.seating.active_seat()
	if object.key != seat.prop_key or not host.colony.coffee_offer(seat.id).has_coffee: return
	# Native five-pixel cup from the existing tea set; no resampling or new art.
	var frame: Dictionary = Sprites.frame_info("tea_set")
	var source := Rect2(frame.source.position + Vector2(0, 8), Vector2(5, 5))
	canvas.draw_texture_rect_region(frame.texture, Rect2(object.rect.position + Vector2(13, 5), Vector2(5, 5)), source)
