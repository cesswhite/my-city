extends RefCounted
const Layout = preload("res://scripts/world_layout.gd")
## Compact actions and live player indicators. Readouts never award progress.
const Icons = preload("res://scripts/hud_icons.gd")
const INK = Color("f4edda")
const MUTED = Color("c3cfb8")
const PAPER = Color("f4edda")
const STATS_SIZE := Vector2(232, 32)
const CONTROLS_SIZE := Vector2(196, 36)
const DOCK_SIZE := Vector2(68, 36)
const BUTTON_SIZE := Vector2(28, 28)
const DOCK_ACTIONS: Array[String] = ["journal", "bicycle"]
var stats_panel: Panel
var controls_panel: Panel
var dock_panel: Panel
var styles: Dictionary = {}
var host: Control
var buttons: Dictionary = {}
var energy_bar: ProgressBar
var energy_value: Label
var energy_group: Control
var coin_value: Label
var coin_group: Control
var mode_group: Control
var mode_icon: TextureRect
var mode_sleep_label: Label
var learning_value: Label
var learning_group: Control
var hovered: Control
var focused: Control

func _init(owner: Control) -> void:
	host = owner

func _help(control: Control) -> void:
	control.mouse_entered.connect(func():
		hovered = control
		host.update_hint())
	control.mouse_exited.connect(func():
		if hovered == control: hovered = null
		host.update_hint())
	control.focus_entered.connect(func():
		focused = control
		host.update_hint())
	control.focus_exited.connect(func():
		if focused == control: focused = null
		host.update_hint())

func context_hint() -> String:
	var control: Control = hovered if is_instance_valid(hovered) else focused
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return ""
	return str(control.get_meta("hud_hint", ""))

func _description(control: Control, title: String, hint: String) -> void:
	control.accessibility_name = title
	control.accessibility_description = hint
	control.tooltip_text = title + ". " + hint
	control.set_meta("hud_hint", title + " · " + hint)

func _surface(fill: Color, border: Color = Color.TRANSPARENT, shadow: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.anti_aliasing = false
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	if shadow:
		style.shadow_color = Color(0.05, 0.09, 0.06, 0.22)
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, 2)
	return style

func _styles() -> void:
	if not styles.is_empty(): return
	styles.panel = _surface(Color(0.13, 0.21, 0.17, 0.91), Color(0.73, 0.79, 0.62, 0.3), true)
	styles.normal = _surface(Color(0.55, 0.66, 0.48, 0.05))
	styles.hover = _surface(Color(0.37, 0.47, 0.32, 0.78))
	styles.pressed = _surface(Color(0.23, 0.33, 0.25, 0.95))
	styles.active = _surface(Color(0.46, 0.56, 0.36, 0.84))
	styles.disabled = _surface(Color(0.55, 0.66, 0.48, 0.02))
	styles.focus = _surface(Color.TRANSPARENT, Color("e1c98c"))

func _style_action(button: Button, active: bool = false) -> void:
	_styles()
	button.add_theme_stylebox_override("normal", styles.active if active else styles.normal)
	for state in ["hover", "pressed", "disabled", "focus"]: button.add_theme_stylebox_override(state, styles[state])
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(color, PAPER)
	button.add_theme_color_override("font_disabled_color", Color("91a28a"))
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
	button.add_theme_font_size_override("font_size", 16)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.size = BUTTON_SIZE

func _panel(name: String, dimensions: Vector2) -> Panel:
	_styles()
	var panel := Panel.new()
	panel.name = name
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", styles.panel)
	host.add_child(panel)
	return panel

func _icon_button(parent: Control, id: String, title: String, point: Vector2, action: Callable, hint: String) -> Button:
	var button: Button = host.button_at(parent, "", point, BUTTON_SIZE, action)
	button.name = "Hud" + id.capitalize().replace(" ", "")
	button.icon = Icons.texture(id)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("h_separation", 0)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("hud_icon", id)
	_style_action(button)
	_description(button, title, hint)
	_help(button)
	buttons[id] = button
	return button

func _group(parent: Control, name: String, point: Vector2, dimensions: Vector2) -> Control:
	var group := Control.new()
	group.name = name
	group.position = point
	group.size = dimensions
	group.mouse_filter = Control.MOUSE_FILTER_STOP
	group.focus_mode = Control.FOCUS_ALL
	parent.add_child(group)
	_help(group)
	return group

func _icon(parent: Control, id: String, point: Vector2) -> void:
	var icon := TextureRect.new()
	icon.texture = Icons.texture(id)
	icon.position = point
	icon.size = Vector2(16, 16)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)

func build_header() -> void:
	stats_panel = _panel("HudStats", STATS_SIZE)
	stats_panel.add_theme_stylebox_override("panel", _surface(Color(0.10, 0.17, 0.13, 0.92), Color.TRANSPARENT, true))
	mode_group = _group(stats_panel, "HudMode", Vector2(6, 4), Vector2(20, 24))
	_icon(mode_group, "hand", Vector2(2, 4))
	mode_icon = mode_group.get_child(0) as TextureRect
	mode_sleep_label = host.label_at(mode_group, "Zz", Vector2(0, 4), Vector2(20, 16), 14, PAPER)
	mode_sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_sleep_label.hide()
	host.clock_label = host.label_at(stats_panel, "", Vector2(30, 8), Vector2(82, 16), 14, PAPER)
	host.clock_label.clip_text = true
	host.clock_label.mouse_filter = Control.MOUSE_FILTER_STOP
	host.clock_label.focus_mode = Control.FOCUS_ALL
	_help(host.clock_label)
	energy_group = _group(stats_panel, "HudEnergy", Vector2(120, 4), Vector2(48, 24))
	_icon(energy_group, "energy", Vector2(0, 4))
	energy_value = host.label_at(energy_group, "100%", Vector2(18, 3), Vector2(28, 16), 14, PAPER)
	energy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	energy_bar = ProgressBar.new()
	energy_bar.name = "EnergyBar"
	energy_bar.position = Vector2(18, 20)
	energy_bar.show_percentage = false
	energy_bar.step = 0.0
	energy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("14291e")
	energy_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("b3c995")
	energy_bar.add_theme_stylebox_override("fill", fill)
	energy_group.add_child(energy_bar)
	# Set geometry after the styles remove the default theme's minimum height.
	energy_bar.size = Vector2(28, 3)
	coin_group = _group(stats_panel, "HudCoins", Vector2(176, 8), Vector2(48, 16))
	_icon(coin_group, "coin", Vector2.ZERO)
	coin_value = host.label_at(coin_group, "", Vector2(20, 0), Vector2(28, 16), 14, PAPER)
	coin_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_panel = _panel("HudControls", CONTROLS_SIZE)
	host.speed_button = host.button_at(controls_panel, "1×", Vector2(4, 4), BUTTON_SIZE, host.cycle_time_speed)
	host.speed_button.name = "HudSpeed"
	_style_action(host.speed_button)
	host.speed_button.focus_mode = Control.FOCUS_ALL
	_help(host.speed_button)
	host.pause_button = _icon_button(controls_panel, "pause", "Pausar", Vector2(36, 4), host.toggle_pause, "Espacio")
	host.ai_button = _icon_button(controls_panel, "spark", "Activar IA", Vector2(68, 4), host.toggle_ai, "Decisiones autónomas de los vecinos")
	host.autonomy_button = _icon_button(controls_panel, "eye", "Vivir solo", Vector2(100, 4), host.toggle_autonomy, "Observar la vida de tu personaje")
	_icon_button(controls_panel, "save", "Guardar partida", Vector2(132, 4), host.save_now, "Conservar tu progreso")
	_icon_button(controls_panel, "menu", "Menú" if host.managed_by_shell else "Ayuda", Vector2(164, 4), func():
		if host.managed_by_shell: host.menu_requested.emit()
		else: host.show_help(), "Esc" if host.managed_by_shell else "Controles y primeros pasos")
	layout(host.get_viewport_rect().size, false)

func build_toolbar() -> void:
	dock_panel = _panel("HudDock", DOCK_SIZE)
	_icon_button(dock_panel, "journal", "Diario", Vector2(4, 4), func(): host.settlement_ui.show_overview(), "Pueblo, trabajos y aprendizajes")
	host.bike_button = _icon_button(dock_panel, "bicycle", "Bicicleta", Vector2(36, 4), host.toggle_bicycle, "Mateo puede enseñarte a repararla")
	# The journal's optional count remains available in its tooltip.
	learning_group = buttons.journal
	learning_value = host.label_at(learning_group, "0/3", Vector2.ZERO, Vector2(28, 16), 16, PAPER)
	learning_value.hide()
	layout(host.get_viewport_rect().size, false)

func layout(dimensions: Vector2, inspector_open: bool) -> void:
	if not dimensions.is_finite(): return
	var available: Vector2 = dimensions.max(Vector2(320, 180))
	var home_ui = host.get("home_ui")
	var reading: bool = not Layout.is_outdoor(host.current_room) and home_ui != null and home_ui.is_reading()
	if is_instance_valid(stats_panel): stats_panel.position = Vector2(12, 12)
	if is_instance_valid(controls_panel):
		controls_panel.position = Vector2(available.x - CONTROLS_SIZE.x - 12, 12).round()
		controls_panel.visible = not inspector_open and not reading
	if is_instance_valid(dock_panel):
		# Two everyday actions stay at the same unobtrusive corner in every room.
		dock_panel.size = DOCK_SIZE
		dock_panel.position = Vector2(12, available.y - DOCK_SIZE.y - 12).round()
		for index in DOCK_ACTIONS.size():
			var button: Button = buttons.get(DOCK_ACTIONS[index])
			if is_instance_valid(button): button.position = Vector2(4 + index * 32, 4)
	_sync_bicycle()

func _sync_bicycle() -> void:
	if not is_instance_valid(host.bike_button): return
	var indoors: bool = not Layout.is_outdoor(host.current_room)
	host.bike_button.disabled = indoors
	host.bike_button.text = ""
	if indoors:
		_description(host.bike_button, "Bicicleta", "Disponible solo en la calle")
	else:
		_description(host.bike_button, "Bajar de la bici" if host.riding_bicycle else "Montar en bici", "Recorrer la colonia" if host.colony.can_ride_bicycle() else "Aprende a repararla con Mateo")
	_style_action(host.bike_button, host.riding_bicycle)

func pointer_over(at: Vector2) -> bool:
	if not at.is_finite(): return false
	for panel: Panel in [stats_panel, controls_panel, dock_panel]:
		if is_instance_valid(panel) and panel.is_visible_in_tree() and panel.get_global_rect().has_point(at): return true
	return false

func sync_actions() -> void:
	if not is_instance_valid(host.pause_button): return
	host.pause_button.text = ""
	host.pause_button.icon = Icons.texture("play" if host.paused else "pause")
	_description(host.pause_button, "Continuar" if host.paused else "Pausar", "Espacio")
	_style_action(host.pause_button, host.paused)
	host.autonomy_button.text = ""
	host.autonomy_button.icon = Icons.texture("hand" if host.colony.player_autonomy else "eye")
	_description(host.autonomy_button, "Tomar control" if host.colony.player_autonomy else "Vivir solo", "WASD también devuelve el control" if host.colony.player_autonomy else "Observar la vida de tu personaje")
	_style_action(host.autonomy_button, host.colony.player_autonomy)
	_sync_bicycle()
	host.ai_button.text = ""
	_description(host.ai_button, "Desactivar IA" if host.use_jev else "Activar IA", "Decisiones autónomas de los vecinos")
	_style_action(host.ai_button, host.use_jev)
	_description(host.speed_button, "Velocidad %d×" % int(host.time_speed), "Cambiar a 1×, 2× o 4×")
	host.speed_button.disabled = host.colony.is_sleeping("player")
	host.speed_button.text = "Zz" if host.colony.is_sleeping("player") else "%d×" % int(host.time_speed)
	if host.colony.is_exhausted():
		_description(host.speed_button, "Descansando por agotamiento", "El descanso dura ocho segundos reales")
	elif host.colony.is_sleeping("player"):
		_description(host.speed_button, "Una hora de sueño por segundo", "Despierta para cambiar la velocidad")

func refresh_stats() -> void:
	if not is_instance_valid(energy_value): return
	var weather: Dictionary = host.colony.weather_state()
	_description(host.clock_label, host.clock_label.text, "%d °C · %s · %s" % [roundi(weather.temperature_c), str(weather.feeling).capitalize(), weather.period])
	var sleeping: bool = host.colony.is_sleeping("player") and not host.paused
	var mode: String = "En pausa" if host.paused else "Descansando por agotamiento" if host.colony.is_exhausted() else "Durmiendo" if sleeping else "Observando" if host.colony.player_autonomy else "Control manual"
	mode_icon.texture = Icons.texture("pause" if host.paused else "eye" if host.colony.player_autonomy else "hand")
	mode_icon.visible = not sleeping
	mode_sleep_label.visible = sleeping
	var mode_hint: String = "Espacio para continuar" if host.paused else "Recuperando energía" if sleeping else "WASD para tomar control" if host.colony.player_autonomy else "WASD o flechas para caminar"
	_description(mode_group, mode, mode_hint)
	var energy: float = host.colony.player_energy()
	energy_bar.value = energy
	energy_value.text = "%d%%" % roundi(energy)
	var fill: StyleBoxFlat = energy_bar.get_theme_stylebox("fill")
	fill.bg_color = Color("e29a76") if energy <= 25 else Color("b3c995")
	_description(energy_group, "Energía %d%%" % roundi(energy), "Usa tu cama para dormir y recuperar energía")
	energy_group.set_meta("hud_hint", "Energía %d%% · Usa tu cama para dormir y recuperarla" % roundi(energy))
	var state: Dictionary = host.colony.progression_state()
	var coins: int = int(state.coins)
	coin_value.text = _compact_coins(coins)
	_description(coin_group, "%d monedas" % coins, "Disponibles para comprar materiales")
	var demonstrated := 0
	for procedure: Dictionary in state.procedures.values():
		if procedure.get("status", "") == "demostrada" and procedure.get("world_verified", false): demonstrated += 1
	var total: int = host.colony.available_apprenticeships().size()
	learning_value.text = "%d/%d" % [demonstrated, total]
	_description(learning_group, "Diario", "Pueblo, trabajos y aprendizajes · %d de %d demostrados" % [demonstrated, total])

func _compact_coins(coins: int) -> String:
	if coins < 1000: return str(coins)
	if coins < 10000: return "%.1fk" % (floorf(coins / 100.0) / 10.0)
	if coins < 1000000: return "%dk" % (coins / 1000)
	return "%dM" % (coins / 1000000)
