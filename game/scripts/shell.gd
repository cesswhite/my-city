extends Control
## Title screen, settings and session lifecycle. The world only runs after choosing to play.
const GameScene = preload("res://scenes/main.tscn")
const Settings = preload("res://scripts/game_settings.gd")
const Store = preload("res://scripts/session_store.gd")
const INK = Color("18332b")
const PAPER = Color("f4edda")
const MUTED = Color("b5c4b6")
const FOREST = Color(0.065, 0.13, 0.105, 0.94)
var settings = Settings.new()
var store = Store.new()
var game: Control
var menu: Control
var panel: PanelContainer
var column: VBoxContainer
var card_scroll: ScrollContainer
var dimmer: ColorRect
var landscape: Node2D
var title_font: FontFile
var reading_font: FontFile
var current_page := "home"
var return_page := "home"
var status_label: Label
var primary_button: Button
var window_option: OptionButton
var vsync_option: CheckButton
var test_mode := false
var preview_mode := false
var status_text := ""
var _menu_tween: Tween
var _has_shown_page := false

class TitleLandscape extends Node2D:
	var bounds := Vector2(768, 432)
	var font: Font
	func _draw() -> void:
		var art = preload("res://scripts/sprite_art.gd")
		var ratio: float = maxf(bounds.x / 468.0, bounds.y / 244.0)
		var offset := (bounds - Vector2(468, 244) * ratio) / 2.0 - Vector2(12, 48) * ratio
		draw_set_transform(offset.round(), 0.0, Vector2.ONE * ratio)
		art.draw_world(self, font, false)
		for item in art.scenery_objects("street", {}):
			art.draw_object(self, item, font)
		draw_set_transform(Vector2.ZERO)

func _ready() -> void:
	test_mode = test_mode or "--ui-test" in OS.get_cmdline_user_args()
	preview_mode = "--preview" in OS.get_cmdline_user_args()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	get_tree().auto_accept_quit = false
	# Existing art captures can still launch the gameplay scene directly without touching a save.
	if preview_mode:
		game = GameScene.instantiate()
		add_child(game)
		return
	if not test_mode:
		var loaded: Error = settings.load_settings()
		if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
			status_text = "No se pudieron leer los ajustes. Se usan los valores iniciales."
		settings.apply()
	_build_backdrop()
	resized.connect(_layout_menu)
	show_page("home")

func _build_theme() -> void:
	reading_font = load("res://assets/fonts/PixelOperator.ttf")
	title_font = load("res://assets/fonts/PixelifySans.ttf")
	for font in [reading_font, title_font]:
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.hinting = TextServer.HINTING_NONE
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font.oversampling = 1.0
	theme = Theme.new()
	theme.default_font = reading_font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PAPER)
	theme.set_constant("line_spacing", "Label", 4)
	for type in ["Button", "OptionButton", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var id: String = {"normal": "button_normal", "hover": "button_hover", "pressed": "button_pressed", "disabled": "button_disabled", "focus": "focus_outline"}[state]
			theme.set_stylebox(state, type, _surface(id))
		for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "icon_normal_color", "icon_hover_color"]: theme.set_color(key, type, PAPER)
		theme.set_color("font_disabled_color", type, Color("80978a"))
		theme.set_color("font_pressed_color", type, PAPER)
	theme.set_stylebox("panel", "PopupMenu", _surface("panel"))
	theme.set_stylebox("hover", "PopupMenu", _surface("message_panel"))
	theme.set_color("font_color", "PopupMenu", PAPER)
	theme.set_color("font_hover_color", "PopupMenu", PAPER)
	theme.set_stylebox("scroll", "VScrollBar", _surface("scroll_track"))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "VScrollBar", _surface("scroll_thumb"))

func _surface(id: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.anti_aliasing = false
	style.bg_color = Color(0.9, 0.96, 0.88, 0.035)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 12 if side in [SIDE_LEFT, SIDE_RIGHT] else 6)
	style.set_corner_radius_all(3)
	match id:
		"panel":
			style.bg_color = FOREST
			style.set_corner_radius_all(6)
			style.shadow_color = Color(0, 0, 0, 0.28)
			style.shadow_size = 12
			style.shadow_offset = Vector2(0, 5)
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_content_margin(side, 0)
		"button_primary": style.bg_color = PAPER
		"primary_hover": style.bg_color = Color("fff8e5")
		"primary_pressed": style.bg_color = Color("d9e4c4")
		"button_hover", "message_panel": style.bg_color = Color(0.42, 0.57, 0.45, 0.28)
		"button_pressed": style.bg_color = Color(0.42, 0.57, 0.45, 0.40)
		"button_disabled": style.bg_color = Color(0.2, 0.3, 0.25, 0.12)
		"focus_outline":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("dfedca")
			style.set_border_width_all(1)
		"primary_focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = INK
			style.set_border_width_all(2)
		"scroll_track", "scroll_thumb":
			style.bg_color = Color(0.8, 0.88, 0.76, 0.08 if id == "scroll_track" else 0.5)
			for side in [SIDE_LEFT, SIDE_RIGHT]: style.set_content_margin(side, 3)
	return style

func _build_backdrop() -> void:
	menu = Control.new()
	menu.name = "MainMenu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu)
	landscape = TitleLandscape.new()
	landscape.font = title_font
	menu.add_child(landscape)
	dimmer = ColorRect.new()
	dimmer.name = "MenuDimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(dimmer)
	panel = PanelContainer.new()
	panel.name = "MenuPanel"
	panel.add_theme_stylebox_override("panel", _surface("panel"))
	menu.add_child(panel)
	panel.resized.connect(_position_panel)
	card_scroll = ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.follow_focus = true
	panel.add_child(card_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	card_scroll.add_child(margin)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	column.minimum_size_changed.connect(_layout_menu)

func _clear_page() -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	primary_button = null
	status_label = null
	window_option = null
	vsync_option = null

func _text(text: String, size_px: int = 16, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	if size_px >= 24: label.add_theme_font_override("font", title_font)
	column.add_child(label)
	return label

func _space(height: int = 6) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = height
	column.add_child(space)

func _button(text: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.name = text.validate_node_name()
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	column.add_child(button)
	if primary:
		button.add_theme_stylebox_override("normal", _surface("button_primary"))
		button.add_theme_stylebox_override("hover", _surface("primary_hover"))
		button.add_theme_stylebox_override("pressed", _surface("primary_pressed"))
		button.add_theme_stylebox_override("focus", _surface("primary_focus"))
		for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]: button.add_theme_color_override(key, INK)
		primary_button = button
	return button

func show_page(page: String) -> void:
	var was_hidden: bool = not menu.visible
	current_page = page
	menu.show()
	var use_world: bool = is_instance_valid(game) and (page == "pause" or (page in ["settings", "controls", "new"] and return_page == "pause"))
	landscape.visible = not use_world
	dimmer.color = Color(0.03, 0.07, 0.05, 0.22 if use_world else 0.34)
	if is_instance_valid(game): game.visible = use_world
	_clear_page()
	match page:
		"home": _home_page()
		"pause": _pause_page()
		"settings": _settings_page()
		"controls": _controls_page()
		"new": _new_page()
	status_label = _text(status_text, 16, Color("f3d7a6"))
	status_label.visible = not status_text.is_empty()
	card_scroll.scroll_vertical = 0
	_layout_menu()
	_layout_menu.call_deferred()
	_focus_primary.call_deferred()
	_fade_in(was_hidden)
	_has_shown_page = true

func _stop_transition() -> void:
	if is_instance_valid(_menu_tween): _menu_tween.kill()
	panel.modulate.a = 1.0
	dimmer.modulate.a = 1.0

func _fade_in(include_backdrop: bool) -> void:
	_stop_transition()
	if not _has_shown_page or test_mode or DisplayServer.get_name() == "headless": return
	panel.modulate.a = 0.0
	_menu_tween = create_tween().set_parallel(true)
	_menu_tween.tween_property(panel, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if include_backdrop:
		dimmer.modulate.a = 0.0
		_menu_tween.tween_property(dimmer, "modulate:a", 1.0, 0.15)

func _focus_primary() -> void:
	if is_instance_valid(menu) and menu.visible and is_instance_valid(primary_button) and primary_button.is_inside_tree():
		primary_button.grab_focus()

func _home_page() -> void:
	_text("Mi Colonia", 32)
	_space(12)
	if is_instance_valid(game) or store.has_save():
		_button("Continuar partida", continue_game, true)
		_button("Nueva partida", request_new_game)
	else:
		_button("Iniciar partida", request_new_game, true)
	_button("Ajustes", func(): open_subpage("settings"))
	_button("Controles", func(): open_subpage("controls"))
	_button("Salir del juego", quit_game)

func _pause_page() -> void:
	_text("En pausa", 28)
	_space(12)
	_button("Volver a la partida", continue_game, true)
	_button("Guardar partida", save_current)
	_button("Ajustes", func(): open_subpage("settings"))
	_button("Controles", func(): open_subpage("controls"))
	_button("Menú principal", return_home)
	_button("Salir del juego", quit_game)

func open_subpage(page: String) -> void:
	return_page = current_page
	status_text = ""
	show_page(page)

func _settings_page() -> void:
	_text("Ajustes", 28)
	_text("Se guardan al elegirlos.", 16, MUTED)
	_space()
	_text("Modo de pantalla")
	window_option = OptionButton.new()
	window_option.name = "WindowMode"
	window_option.custom_minimum_size.y = 40
	window_option.tooltip_text = "F11 también cambia entre pantalla completa y ventana."
	window_option.add_item("Pantalla completa")
	window_option.add_item("Ventana")
	window_option.select(0 if settings.fullscreen else 1)
	window_option.item_selected.connect(func(index: int):
		settings.set_fullscreen(index == 0)
		_apply_settings())
	column.add_child(window_option)
	_space()
	vsync_option = CheckButton.new()
	vsync_option.name = "VSync"
	vsync_option.text = "Sincronización vertical"
	vsync_option.custom_minimum_size.y = 40
	vsync_option.button_pressed = settings.vsync
	vsync_option.toggled.connect(func(enabled: bool):
		settings.set_vsync(enabled)
		_apply_settings())
	column.add_child(vsync_option)
	_text("Evita cortes en la imagen al moverte.", 16, MUTED)
	_space(12)
	_button("Volver", back, true)

func _controls_page() -> void:
	_text("Controles", 28)
	_space()
	for line in ["WASD / flechas · Caminar", "E · Hablar, entrar o interactuar", "C · Pedir o beber café, sentado", "Espacio · Pausar el mundo", "Esc · Cerrar un panel / abrir el menú", "F11 · Pantalla completa o ventana", "Enter · Enviar tu mensaje"]:
		_text(line)
	_space()
	_button("Volver", back, true)

func _new_page() -> void:
	_text("Una nueva historia", 28)
	_text("Empezarás desde cero con otro personaje y una nueva colonia.")
	_space()
	_text("Tu partida actual quedará respaldada antes de iniciar la nueva.", 16, MUTED)
	_space(12)
	_button("Conservar mi partida", back, true)
	_button("Empezar de nuevo", confirm_new_game)

func back() -> void:
	status_text = ""
	show_page(return_page)

func _layout_menu() -> void:
	if not is_instance_valid(menu): return
	var bounds := get_viewport_rect().size
	landscape.bounds = bounds
	landscape.queue_redraw()
	var width: float = minf(336.0 if current_page in ["settings", "controls", "new"] else 288.0, bounds.x - 32.0)
	panel.custom_minimum_size.x = width
	panel.size = Vector2(width, minf(column.get_combined_minimum_size().y + 40.0, bounds.y - 32.0))
	_position_panel()

func _position_panel() -> void:
	if not is_instance_valid(panel): return
	var bounds := get_viewport_rect().size
	var centered: bool = current_page != "home"
	panel.position = Vector2(roundf((bounds.x - panel.size.x) / 2.0) if centered else 32.0, maxf(16.0, roundf((bounds.y - panel.size.y) / 2.0)))

func _set_status(text: String) -> void:
	status_text = text
	if is_instance_valid(status_label):
		status_label.text = text
		status_label.visible = not text.is_empty()
	_layout_menu.call_deferred()

func _apply_settings() -> void:
	settings.apply()
	if settings.save_settings() != OK:
		_set_status("No se pudieron guardar los ajustes. Se conservarán durante esta sesión.")
	else: _set_status("")

func continue_game() -> void:
	if is_instance_valid(game):
		_stop_transition()
		menu.hide()
		game.resume_from_menu()
		return
	if not store.validate_save():
		_set_status(store.last_error + " Puedes iniciar una nueva y conservar un respaldo.")
		return
	_start_game(false)

func request_new_game() -> void:
	status_text = ""
	if store.has_save() or is_instance_valid(game):
		return_page = current_page
		show_page("new")
	else: confirm_new_game()

func confirm_new_game() -> void:
	if not _persist_game(): return
	if not store.new_game():
		_set_status(store.last_error)
		return
	if is_instance_valid(game):
		remove_child(game)
		game.queue_free()
		game = null
	_start_game(true)

func _start_game(_customize: bool) -> void:
	game = GameScene.instantiate()
	game.managed_by_shell = true
	game.colony.save_path = store.save_path
	game.menu_requested.connect(open_pause_menu)
	add_child(game)
	move_child(menu, get_child_count() - 1)
	if not game.save_allowed:
		var error: String = game.colony.last_error
		remove_child(game)
		game.queue_free()
		game = null
		_set_status(error)
		return
	menu.hide()
	_stop_transition()
	game.paused = false
	game.refresh_status()
	status_text = ""

func open_pause_menu() -> void:
	if not is_instance_valid(game) or menu.visible: return
	game.suspend_for_menu()
	status_text = ""
	show_page("pause")

func _persist_game() -> bool:
	if not is_instance_valid(game): return true
	if not game.save_allowed:
		_set_status("No se puede guardar esta partida. Se conserva el archivo anterior.")
		return false
	if not game.colony.save_game():
		_set_status("No se pudo guardar. " + game.colony.last_error)
		return false
	return true

func save_current() -> void:
	if _persist_game(): _set_status("Partida guardada.")

func return_home() -> void:
	if not _persist_game(): return
	status_text = ""
	show_page("home")

func quit_game() -> void:
	if is_instance_valid(game) and not menu.visible: open_pause_menu()
	if _persist_game(): get_tree().quit()

func _input(event: InputEvent) -> void:
	if preview_mode or not event is InputEventKey or not event.pressed or event.echo: return
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed: return
	if event.keycode == KEY_F11 or event.physical_keycode == KEY_F11:
		settings.set_fullscreen(not settings.fullscreen)
		_apply_settings()
		if is_instance_valid(window_option): window_option.select(0 if settings.fullscreen else 1)
		get_viewport().set_input_as_handled()
	elif menu.visible and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		if current_page in ["settings", "controls", "new"]: back()
		elif is_instance_valid(game): continue_game()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not preview_mode:
		quit_game()
