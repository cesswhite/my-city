extends Control

signal menu_requested

const Colony = preload("res://scripts/colony.gd")
const Art = preload("res://scripts/pixel_art.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const DialogueStream = preload("res://scripts/dialogue_stream.gd")
const Navigation = preload("res://scripts/navigation.gd")
const WorldLayout = preload("res://scripts/world_layout.gd")
const SettlementUI = preload("res://scripts/settlement_ui.gd")
const LearningUI = preload("res://scripts/learning_ui.gd")
const ResidentUI = preload("res://scripts/resident_ui.gd")
const ResidentControls = preload("res://scripts/resident_controls.gd")
const PlayerChat = preload("res://scripts/player_chat.gd")
const GameHUD = preload("res://scripts/game_hud.gd")
const SleepUI = preload("res://scripts/sleep_ui.gd")
const ActivityVisuals = preload("res://scripts/activity_visuals.gd")
const AmbientThoughts = preload("res://scripts/ambient_thoughts.gd")
const WorldInteractions = preload("res://scripts/world_interactions.gd")
const InteractionHover = preload("res://scripts/interaction_hover.gd")
const InteractionGlow = preload("res://scripts/interaction_glow.gd")
const WorldOverlay = preload("res://scripts/world_overlay.gd")
const NeighborhoodUI = preload("res://scripts/neighborhood_ui.gd")
const HomeUI = preload("res://scripts/home_ui.gd")
const AmbientEnvironment = preload("res://scripts/ambient_environment.gd")
const WorldLighting = preload("res://scripts/world_lighting.gd")
const Seats = preload("res://scripts/seating.gd")
const PlayerSeating = preload("res://scripts/player_seating.gd")
const CafeServiceUI = preload("res://scripts/cafe_service_ui.gd")
const ConversationCamera = preload("res://scripts/conversation_camera.gd")
const SocialEncounters = preload("res://scripts/social_encounters.gd")
const CrowdMotion = preload("res://scripts/crowd_motion.gd")
const INK = Color("303e37")
const PAPER = Color("f4edda")
const MUTED = Color("535f50")
const ACCENT = Color("b9684f")
const BASE_VIEWPORT := Vector2(768, 432)
const WORLD_RECT := Rect2(12, 48, 468, 244)
const WORLD_TICK_SECONDS := 4.0
const SLEEP_MINUTES_PER_SECOND := 60.0
const SLEEP_SPEED := SLEEP_MINUTES_PER_SECOND * WORLD_TICK_SECONDS / 5.0
const PLAYER_WALK_SPEED := 48.0
const NEIGHBOR_WALK_SPEED := 30.0
const BICYCLE_SPEED := 120.0
const APPEARANCE = [
	["skin", "Piel", ["Marfil", "Arena", "Miel", "Cobre", "Cacao", "Ébano"]],
	["hair_style", "Peinado", ["Corto", "Rizado", "Largo", "Rapado"]],
	["hair", "Cabello", ["Oscuro", "Castaño", "Cobrizo", "Rubio", "Gris", "Blanco"]],
	["eyes", "Ojos", ["Café", "Miel", "Verde", "Azul", "Gris"]],
	["beard", "Barba", ["Sin barba", "Bigote", "Completa"]],
	["hat", "Sombrero", ["Ninguno", "Paja", "Gorro", "Gorra"]],
	["shirt", "Camisa", ["Teja", "Salvia", "Mostaza", "Azul", "Rosa", "Crema"]],
	["pants", "Pantalón", ["Marino", "Tierra", "Oliva", "Avellana", "Arena"]]
]

class Scenery extends Node2D:
	var font: Font
	var room = "street"
	var interior_state: Dictionary = {}
	func _draw() -> void:
		if WorldLayout.is_outdoor(room):
			preload("res://scripts/pixel_art.gd").draw_world(self, font, false, room, interior_state)
		else:
			preload("res://scripts/pixel_art.gd").draw_interior(self, font, room, interior_state, false)
			WorldLighting.draw_fixtures(self, room)

class WorldActors extends Node2D:
	var host: Control
	func _draw() -> void:
		host.draw_world_actors(self)

class WorldLabels extends Node2D:
	var host: Control
	func _draw() -> void:
		host.draw_world_labels(self)

class WorldAtmosphere extends Node2D:
	var host: Control
	func _draw() -> void:
		host.environment.draw_foreground(self, host.current_room)

class WorldLights extends Node2D:
	var host: Control
	func _draw() -> void:
		WorldLighting.draw(self, host.current_room, host.visual_minute(), host.environment_seconds, host.home_project_state())

class WorldSurround extends Node2D:
	var host: Control
	func _draw() -> void:
		host.draw_world_surround(self)

var colony = Colony.new()
var settlement_ui: RefCounted
var _settlement_revision := -1
var _settlement_minute := -1
var pixel_font: FontFile
var ui_font: FontFile
var selected_id = "cesar"
var page = "historia"
var elapsed = 0.0
var paused = false
var inspector: Control
var log_label: Label
var clock_label: Label
var provider_label: Label
var feedback: Label
var request: HTTPRequest
var use_jev = false
var decision_pending = false
var deciding_id = ""
var decision_index = 0
var last_provider = "LOCAL · sin IA"
var preview_mode = false
var save_allowed = true
var managed_by_shell = false
var start_new_game = false
var _menu_suspended = false
var _menu_was_paused = false
var _exhaustion_handled := false
var service_url = "http://127.0.0.1:8787"
var service_token = ""
var dialogue_request: Node
var dialogue_job: Dictionary = {}
var dialogue_text = "Acércate a un vecino y cuéntale algo. La conversación usará sus propios recuerdos."
var chat_input: TextEdit
var chat_output: Label
var chat_scroll: ScrollContainer
var chat_send: Button
var chat_partner_id: String = ""
var player_chat: RefCounted
var hud: RefCounted
var sleep_ui: RefCounted
var ambient_thoughts: RefCounted
var stream_prefix = ""
var stream_text = ""
var last_timing = ""
var activity_label: Label
var gathering = 0.0
var decision_after: Dictionary = {}
var scenery: Node2D
var actors: Node2D
var world_labels: Node2D
var atmosphere: Node2D
var world_lights: Node2D
var environment = AmbientEnvironment.new()
var environment_seconds := 0.0
var facing: Dictionary = {}
var paths: Dictionary = {}
var pending_home = ""
var pending_exit = false
var current_room = "street"
var neighborhood: RefCounted
var room_label: Label
var exit_button: Button
var door_panel: Panel
var door_text: Label
var door_primary: Button
var door_return: Button
var visit_request: HTTPRequest
var visit_job: Dictionary = {}
var pending_item: Dictionary = {}
var pending_shop = false
var riding_bicycle = false
var bike_button: Button
var learning: RefCounted
var pending_mentor = ""
var follow_elapsed = 0.0
var inspector_resident = ""
var inspector_page = ""
var chat_drafts: Dictionary = {}
var memory_scroll: Dictionary = {}
var autonomy_button: Button
var speed_button: Button
var pause_button: Button
var time_speed = 1.0
var controls_active = true
var keyboard_walking = false
var _environment_revision: int = -1
var control_epoch = 0
var deciding_epoch = 0
var ai_cooldown = 0.0
var dialogue_serial = 0
var resident_ui: RefCounted
var hint_label: Label
var ai_button: Button
var msg_scroll: ScrollContainer
var help_panel: Panel
var help_backdrop: ColorRect
var door_backdrop: ColorRect
var help_was_paused = false
var notice_history: Array[Dictionary] = []
var seen_world_events: Dictionary = {}
var hint_elapsed = 0.0
var world_clip: Control
var world_surround: Node2D
var world_view_rect := WORLD_RECT
var world_map_rect := WORLD_RECT
var world_scale: float = 1.0
var conversation_camera: RefCounted
var encounters: RefCounted
var crowd: RefCounted
var _hud_layout: Array[Dictionary] = []
var _layout_ready: bool = false
var interaction_hover: RefCounted
var seating: RefCounted
var cafe_service: RefCounted
var overlay: RefCounted
var home_ui: RefCounted
var inspector_carets: Dictionary = {}
var _pointer_actor_images: Dictionary = {}
var _pointer_actor_bounds: Dictionary = {}

func _ready() -> void:
	configure_keyboard()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_font = load("res://assets/fonts/PixelifySans.ttf")
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	pixel_font.oversampling = 1.0
	# Pixel Operator is drawn on a 16 px grid. Keep reading text at its native
	# size; arbitrary small sizes merge strokes and make Spanish accents muddy.
	ui_font = load("res://assets/fonts/PixelOperator.ttf")
	ui_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	ui_font.hinting = TextServer.HINTING_NONE
	ui_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	ui_font.oversampling = 1.0
	var ui_theme = Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 16
	ui_theme.set_constant("line_spacing", "Label", 4)
	ui_theme.set_constant("line_spacing", "TextEdit", 4)
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_color("font_hover_color", "Button", INK)
	ui_theme.set_color("font_focus_color", "Button", INK)
	ui_theme.set_color("font_pressed_color", "Button", PAPER)
	ui_theme.set_color("font_disabled_color", "Button", Color("666d5d"))
	ui_theme.set_stylebox("panel", "TooltipPanel", sprite_box("tooltip"))
	ui_theme.set_color("font_color", "TooltipLabel", PAPER)
	ui_theme.set_font_size("font_size", "TooltipLabel", 16)
	ui_theme.set_stylebox("scroll", "VScrollBar", sprite_box("scroll_track"))
	ui_theme.set_stylebox("grabber", "VScrollBar", sprite_box("scroll_thumb"))
	ui_theme.set_stylebox("grabber_highlight", "VScrollBar", sprite_box("scroll_active"))
	ui_theme.set_stylebox("grabber_pressed", "VScrollBar", sprite_box("scroll_active"))
	ui_theme.set_stylebox("normal", "Button", box(PAPER, Color("c4c6a8")))
	ui_theme.set_stylebox("hover", "Button", box(Color("e4e6cc"), INK))
	ui_theme.set_stylebox("pressed", "Button", box(INK, INK))
	ui_theme.set_stylebox("disabled", "Button", sprite_box("button_disabled"))
	ui_theme.set_stylebox("focus", "Button", box(Color.TRANSPARENT, ACCENT, 2))
	ui_theme.set_color("font_color", "LineEdit", INK)
	ui_theme.set_color("caret_color", "LineEdit", INK)
	ui_theme.set_stylebox("normal", "LineEdit", sprite_box("input"))
	theme = ui_theme
	preview_mode = "--preview" in OS.get_cmdline_user_args() or "--ui-test" in OS.get_cmdline_user_args()
	# A new session rebuilds its own growth geometry before sharing any routes.
	Navigation.set_environment_obstacles({})
	colony.setup(not preview_mode and not start_new_game, preview_mode and "--settlement-start" not in OS.get_cmdline_user_args())
	if not colony.is_present(selected_id): selected_id = "lupita"
	seating = PlayerSeating.new(self)
	cafe_service = CafeServiceUI.new(self)
	crowd = CrowdMotion.new(self)
	ambient_thoughts = AmbientThoughts.new(colony)
	# Loaded memories inform the neighbors without replaying old conversations in notices.
	for entry in colony.events: seen_world_events[entry] = true
	# New buildings may cover a position from an older save. Reconcile only on load.
	for resident in colony.active_residents():
		var recovered: Vector2 = Navigation.recover_position(position_of(resident), resident.get("room", "street"))
		if recovered != position_of(resident):
			resident.pos = [recovered.x, recovered.y]
			resident.target = resident.pos.duplicate()
		elif not Navigation.is_walkable(Vector2(resident.target[0], resident.target[1]), resident.get("room", "street")):
			resident.target = resident.pos.duplicate()
	if not colony.last_error.is_empty():
		save_allowed = false
	scenery = Scenery.new()
	scenery.font = pixel_font
	world_clip = Control.new()
	world_clip.position = Vector2(12, 48)
	world_clip.size = Vector2(468, 244)
	world_clip.clip_contents = true
	world_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_clip)
	world_surround = WorldSurround.new()
	world_surround.host = self
	world_clip.add_child(world_surround)
	scenery.position = Vector2(-12, -48)
	world_clip.add_child(scenery)
	actors = WorldActors.new()
	actors.host = self
	actors.position = Vector2(-12, -48)
	world_clip.add_child(actors)
	atmosphere = WorldAtmosphere.new()
	atmosphere.host = self
	world_clip.add_child(atmosphere)
	world_lights = WorldLights.new()
	world_lights.host = self
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	world_lights.material = glow_material
	world_clip.add_child(world_lights)
	world_labels = WorldLabels.new()
	world_labels.host = self
	world_clip.add_child(world_labels)
	learning = LearningUI.new(self)
	settlement_ui = SettlementUI.new(self)
	resident_ui = ResidentUI.new(self)
	player_chat = PlayerChat.new(self)
	sleep_ui = SleepUI.new(self)
	overlay = WorldOverlay.new(self)
	home_ui = HomeUI.new(self)
	neighborhood = NeighborhoodUI.new(self)
	interaction_hover = InteractionHover.new(self)
	conversation_camera = ConversationCamera.new(self)
	encounters = SocialEncounters.new(self)
	mouse_exited.connect(interaction_hover.clear)
	build_ui()
	_capture_hud_layout()
	_layout_ready = true
	get_viewport().size_changed.connect(apply_responsive_layout)
	child_entered_tree.connect(_layout_child_added)
	apply_responsive_layout()
	request = HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	request.request_completed.connect(_decision_received)
	visit_request = HTTPRequest.new()
	visit_request.timeout = 8.0
	add_child(visit_request)
	visit_request.request_completed.connect(_visit_received)
	dialogue_request = DialogueStream.new()
	add_child(dialogue_request)
	dialogue_request.delta.connect(_dialogue_delta)
	dialogue_request.completed.connect(_dialogue_completed)
	dialogue_request.failed.connect(_dialogue_failed)
	service_token = OS.get_environment("MY_CITY_DEV_TOKEN")
	var configured_url = OS.get_environment("MY_CITY_API_URL").trim_suffix("/")
	if configured_url.begins_with("https://") or configured_url.begins_with("http://127.0.0.1:"):
		service_url = configured_url
	apply_ai_startup_default()
	if not colony.last_error.is_empty():
		message(colony.last_error)
	if not Sprites.is_ready():
		message("Faltan sprites. Revisa game/assets/sprites/manifest.json.")
		push_error("; ".join(Sprites.validation_errors()))
	update_room()
	set_process(true)
	get_tree().auto_accept_quit = false
	if preview_mode:
		paused = true
		if "--ui-test" in OS.get_cmdline_user_args():
			return
		if "--appearance" in OS.get_cmdline_user_args():
			selected_id = "player"
			page = "aspecto"
			build_inspector()
		if "--interior" in OS.get_cmdline_user_args():
			colony.get_resident("player").room = "cesar"
			colony.get_resident("player").pos = [236.0, 252.0]
			colony.get_resident("player").target = [236.0, 252.0]
			update_room()
		if "--player-home" in OS.get_cmdline_user_args():
			colony.get_resident("player").room = "player"
			colony.get_resident("player").pos = [236.0, 252.0]
			colony.get_resident("player").target = [236.0, 252.0]
			update_room()
		if "--journal" in OS.get_cmdline_user_args():
			learning.show_journal()
		if "--autonomy" in OS.get_cmdline_user_args():
			selected_id = "player"
			page = "historia"
			toggle_autonomy()
			build_inspector()
		refresh_status()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture = OS.get_environment("MY_CITY_CAPTURE")
		if not capture.is_empty():
			get_viewport().get_texture().get_image().save_png(capture)
			get_tree().quit()

var sprite_styles: Dictionary = {}

func sprite_box(id: String) -> StyleBoxTexture:
	if sprite_styles.has(id): return sprite_styles[id]
	var style = StyleBoxTexture.new()
	var info: Dictionary = Sprites.frame_info("ui_" + id)
	if not info.is_empty(): style.texture = info.texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 2)
		style.set_content_margin(side, 0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	if id in ["input", "input_focus", "tooltip"]:
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
	if id in ["scroll_track", "scroll_thumb", "scroll_active"]:
		# A zero minimum width hides the bar even when there is more to read.
		style.content_margin_left = 3
		style.content_margin_right = 3
	sprite_styles[id] = style
	return style

func box(fill: Color, _border: Color, _width: int = 1) -> StyleBoxTexture:
	if fill.a < 0.1: return sprite_box("focus_outline")
	if fill.get_luminance() < 0.38: return sprite_box("button_primary")
	if fill.get_luminance() < 0.65: return sprite_box("scroll_thumb")
	if fill.g > fill.r: return sprite_box("message_panel")
	return sprite_box("button_normal")

func label_at(parent: Node, text: String, at: Vector2, size: Vector2, font_size: int = 16, color: Color = INK) -> Label:
	var label = Label.new()
	label.clip_text = true
	label.text = text
	label.position = at
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 18:
		label.add_theme_font_override("font", pixel_font)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.size = size
	return label

func button_at(parent: Node, text: String, at: Vector2, size: Vector2, action: Callable, hint: String = "") -> Button:
	var button = Button.new()
	button.text = text
	button.clip_text = true
	button.position = at
	button.size = size
	button.tooltip_text = hint
	button.pressed.connect(action)
	parent.add_child(button)
	button.size = size
	return button

func style_button(button: Button, primary: bool = false) -> void:
	button.add_theme_stylebox_override("normal", sprite_box("button_primary" if primary else "button_normal"))
	button.add_theme_stylebox_override("hover", sprite_box("button_pressed" if primary else "button_hover"))
	button.add_theme_stylebox_override("pressed", sprite_box("button_pressed"))
	button.add_theme_color_override("font_color", PAPER if primary else INK)
	button.add_theme_color_override("font_focus_color", PAPER if primary else INK)
	button.add_theme_color_override("font_hover_color", PAPER if primary else INK)
	button.add_theme_color_override("font_pressed_color", PAPER)

func build_ui() -> void:
	hud = GameHUD.new(self)
	hud.build_header()
	inspector = Panel.new()
	inspector.name = "ResidentOverlay"
	inspector.position = Vector2(498, 16)
	inspector.size = Vector2(254, 400)
	inspector.clip_contents = true
	inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(inspector)
	hud.build_toolbar()
	overlay.build()
	cafe_service.build()
	home_ui.build()
	build_inspector()
	refresh_status()
	message("WASD para caminar. Haz clic en un vecino o en un objeto que brille.")

func layout_size() -> Vector2:
	return get_viewport_rect().size.max(BASE_VIEWPORT)

func _capture_hud_layout() -> void:
	_hud_layout.clear()
	for child in get_children():
		if not child is Control or child == world_clip or child == inspector:
			continue
		var item := {"control": child, "rect": Rect2(child.position, child.size)}
		if child.has_meta("hud_anchor"): item.hud_anchor = child.get_meta("hud_anchor")
		_hud_layout.append(item)

func apply_responsive_layout() -> void:
	if not _layout_ready: return
	var dimensions: Vector2 = layout_size()
	var resized: bool = world_view_rect.size != dimensions
	world_view_rect = Rect2(Vector2.ZERO, dimensions)
	world_scale = minf(dimensions.x / WORLD_RECT.size.x, dimensions.y / WORLD_RECT.size.y)
	world_clip.position = Vector2.ZERO
	world_clip.size = dimensions
	overlay.layout()
	cafe_service.layout()
	hud.layout(dimensions, inspector.visible)
	home_ui.layout()
	_layout_inspector()
	_layout_modals()
	update_camera(0.0, resized)
	interaction_hover.refresh()
	queue_redraw()

func camera_safe_rect() -> Rect2:
	return conversation_camera.safe_rect()

func update_camera(delta: float = 0.0, immediate: bool = false) -> void:
	if not _layout_ready: return
	var map_size: Vector2 = WORLD_RECT.size * world_scale
	var base_rect := Rect2(((layout_size() - map_size) / 2.0).round(), map_size)
	var next_rect := Rect2(base_rect.position + conversation_camera.advance(delta, base_rect, immediate or preview_mode), map_size)
	if next_rect == world_map_rect and scenery.scale == Vector2.ONE * world_scale: return
	world_map_rect = next_rect
	for layer: Node2D in [scenery, actors, atmosphere, world_lights]:
		layer.scale = Vector2.ONE * world_scale
		layer.position = world_map_rect.position - WORLD_RECT.position * world_scale
	world_surround.queue_redraw()
	world_labels.queue_redraw()
	interaction_hover.refresh()

func _layout_inspector() -> void:
	if not is_instance_valid(inspector): return
	var extra_height: float = inspector.size.y - 368.0
	for child in inspector.get_children():
		if not child is Control: continue
		if not child.has_meta("responsive_base_rect"):
			child.set_meta("responsive_base_rect", Rect2(child.position, child.size))
		var base: Rect2 = child.get_meta("responsive_base_rect")
		var rect: Rect2 = base
		if child is ScrollContainer:
			rect.size.y += extra_height
		elif (page == "hablar" and child.get_meta("chat_bottom", false)) or (page != "hablar" and base.position.y >= 270):
			rect.position.y += extra_height
		child.position = rect.position
		child.size = rect.size

func _layout_child_added(_child: Node) -> void:
	# Journal panels belong to their backdrop; defer until the whole modal exists.
	_layout_modals.call_deferred()

func _layout_modals() -> void:
	if is_instance_valid(settlement_ui): settlement_ui.layout()
	if is_instance_valid(sleep_ui): sleep_ui.layout()
	var panels: Array = [help_panel, door_panel]
	var shades: Array = [help_backdrop, door_backdrop]
	if is_instance_valid(learning):
		learning.layout()
		panels.append(learning.panel)
		shades.append(learning.modal_shade)
	for shade in shades:
		if is_instance_valid(shade) and not shade.is_queued_for_deletion():
			if shade.anchor_left == shade.anchor_right and shade.anchor_top == shade.anchor_bottom:
				shade.size = layout_size()
	for panel in panels:
		if not is_instance_valid(panel) or panel.is_queued_for_deletion(): continue
		panel.position = ((layout_size() - panel.size) / 2.0).round()

func world_to_screen(point: Vector2) -> Vector2:
	return world_map_rect.position + (point - WORLD_RECT.position) * world_scale

func screen_to_world(point: Vector2) -> Vector2:
	return WORLD_RECT.position + (point - world_map_rect.position) / world_scale

func draw_world_surround(canvas: CanvasItem) -> void:
	var info: Dictionary = Sprites.frame_info("tile_grass" if WorldLayout.is_outdoor(current_room) else "tile_wall")
	if info.is_empty(): return
	var tile_size: Vector2 = info.source.size * world_scale
	var origin: Vector2 = world_map_rect.position - world_view_rect.position
	var first: Vector2 = origin + ((-origin) / tile_size).floor() * tile_size
	var tint := Color(str(WorldLayout.section(current_room).get("grass_tint", "ffffff"))) if WorldLayout.is_outdoor(current_room) else Color("65736b")
	for row in range(ceili((world_view_rect.size.y - first.y) / tile_size.y)):
		for column in range(ceili((world_view_rect.size.x - first.x) / tile_size.x)):
			canvas.draw_texture_rect_region(info.texture, Rect2(first + Vector2(column, row) * tile_size, tile_size), info.source, tint)

func toggle_ai() -> void:
	if service_token.is_empty():
		message("Para activar la IA, abre Start-AI.command y vuelve a iniciar el juego con Play.command.")
		return
	use_jev = not use_jev
	last_provider = "JEV · por conectar" if use_jev else "LOCAL · sin IA"
	if not use_jev:
		request.cancel_request()
		decision_pending = false
	message("IA activada. Los vecinos podrán decidir y conversar mediante el servicio configurado." if use_jev else "Modo local activo. Los vecinos siguen sus horarios con las reglas del juego.")
	refresh_status()

func apply_ai_startup_default() -> void:
	# Real sessions start ready to use their configured service. Preview/test
	# worlds remain offline even when launched from an authenticated environment.
	use_jev = not preview_mode and not service_token.is_empty()
	last_provider = "IA · lista" if use_jev else "LOCAL · sin IA"
	if is_instance_valid(hud): hud.sync_actions()

func open_inspector(id: String = "", tab: String = "") -> void:
	if not id.is_empty() and not colony.is_present(id): return
	home_ui.close()
	if not id.is_empty(): selected_id = id
	if not tab.is_empty(): page = tab
	overlay.show_inspector()
	build_inspector()
	if page == "hablar" and is_instance_valid(chat_input) and inspector_carets.has(selected_id):
		var caret: Vector2i = inspector_carets[selected_id]
		chat_input.set_caret_line(caret.x)
		chat_input.set_caret_column(caret.y)
	interaction_hover.refresh()

func hide_inspector() -> void:
	if not inspector.visible: return
	if inspector_page == "hablar" and is_instance_valid(chat_input):
		chat_drafts[inspector_resident] = chat_input.text
		inspector_carets[inspector_resident] = Vector2i(chat_input.get_caret_line(), chat_input.get_caret_column())
		if is_instance_valid(chat_scroll): player_chat.scroll_positions[inspector_resident] = chat_scroll.scroll_vertical
	var focused: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and inspector.is_ancestor_of(focused): get_viewport().gui_release_focus()
	overlay.hide_inspector()
	interaction_hover.clear()

func point_over_interface(at: Vector2) -> bool:
	if is_instance_valid(settlement_ui) and is_instance_valid(settlement_ui.panel): return true
	return is_instance_valid(hud) and hud.pointer_over(at) or is_instance_valid(overlay) and overlay.pointer_over(at) or is_instance_valid(cafe_service) and cafe_service.pointer_over(at) or is_instance_valid(home_ui) and home_ui.pointer_over(at)

func build_inspector() -> void:
	var restore_typing: bool = inspector.visible and inspector_page == "hablar" and inspector_resident == selected_id and page == "hablar" and is_instance_valid(chat_input) and chat_input.has_focus()
	var caret_line: int = chat_input.get_caret_line() if restore_typing else 0
	var caret_column: int = chat_input.get_caret_column() if restore_typing else 0
	if inspector_page == "hablar" and is_instance_valid(chat_scroll):
		player_chat.scroll_positions[inspector_resident] = chat_scroll.scroll_vertical
		var bar = chat_scroll.get_v_scroll_bar()
		player_chat.scroll_follow[inspector_resident] = bar.value >= bar.max_value - bar.page - 4
	if inspector_page == "hablar" and is_instance_valid(chat_input):
		chat_drafts[inspector_resident] = chat_input.text
	if inspector_page == "recuerdos":
		for child in inspector.get_children():
			if child is ScrollContainer: memory_scroll[inspector_resident] = child.scroll_vertical
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	var resident: Dictionary = colony.get_resident(selected_id)
	if resident.is_empty():
		return
	inspector_resident = selected_id
	inspector_page = page
	var title: String = "Tu clóset" if page == "aspecto" and can_edit_appearance(selected_id) else str(resident.name)
	var resident_name = label_at(inspector, title, Vector2(12, 8), Vector2(148, 24), 20)
	resident_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	resident_name.tooltip_text = str(resident.name)
	resident_name.mouse_filter = Control.MOUSE_FILTER_PASS
	if page == "hablar":
		var close_chat := button_at(inspector, "×", Vector2(218, 2), Vector2(28, 28), close_chat_panel, "Terminar conversación")
		close_chat.accessibility_name = "Terminar conversación"
	else:
		var previous = button_at(inspector, "<", Vector2(164, 4), Vector2(24, 30), func(): cycle_person(-1), "Vecino anterior")
		previous.accessibility_name = "Vecino anterior"
		ResidentControls.style(previous)
		var next = button_at(inspector, ">", Vector2(190, 4), Vector2(24, 30), func(): cycle_person(1), "Siguiente vecino")
		next.accessibility_name = "Siguiente vecino"
		ResidentControls.style(next)
		var close_profile = button_at(inspector, "×", Vector2(218, 4), Vector2(26, 26), hide_inspector, "Cerrar panel · Esc")
		close_profile.accessibility_name = "Cerrar panel"
		ResidentControls.style(close_profile)
		ResidentControls.tabs(self)
	match page:
		"aspecto":
			build_appearance(resident)
			overlay.portrait()
		"recuerdos": build_memories(resident)
		"hablar": build_chat(resident)
		"agenda": build_schedule(resident)
		_: build_story(resident)
	if page == "hablar":
		if restore_typing and is_instance_valid(chat_input):
			chat_input.grab_focus()
			chat_input.set_caret_line(caret_line)
			chat_input.set_caret_column(caret_column)
		chat_scroll.get_v_scroll_bar().changed.connect(_chat_range_changed.bind(selected_id, chat_scroll.get_instance_id()))
		restore_chat_scroll.call_deferred(selected_id, int(player_chat.scroll_positions.get(selected_id, 0)), bool(player_chat.scroll_follow.get(selected_id, true)))
	_layout_inspector()
	update_camera()
	queue_redraw()
	if is_instance_valid(actors): actors.queue_redraw()
	if is_instance_valid(world_labels): world_labels.queue_redraw()

func paragraph(parent: Node, text: String, y: float, height: float, font_size: int = 16) -> Label:
	var label = label_at(parent, text, Vector2(12, y), Vector2(230, height), font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(230, height)
	return label

func build_story(resident: Dictionary) -> void:
	resident_ui.build_story(resident)

func build_schedule(resident: Dictionary) -> void:
	resident_ui.build_schedule(resident)

func build_memories(resident: Dictionary) -> void:
	resident_ui.build_memories(resident)

func memory_text(memory: Dictionary) -> String:
	return str(memory.get("time", "")) + " · " + str(memory.get("origin", "")) + "\n" + str(memory.get("content", ""))

func add_memory_text(parent: Node, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.custom_minimum_size.x = 214
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)
	return label

func build_chat(resident: Dictionary) -> void:
	resident_ui.build_chat(resident)

func build_appearance(resident: Dictionary) -> void:
	resident_ui.build_appearance(resident)

func change_look(spec: Array, direction: int) -> void:
	if not can_edit_appearance(selected_id): return
	var resident: Dictionary = colony.get_resident(selected_id)
	resident.appearance[spec[0]] = posmod(int(resident.appearance.get(spec[0], 0)) + direction, spec[2].size())
	build_inspector()

func can_edit_appearance(resident_id: String) -> bool:
	if resident_id != "player" or current_room != "player" or colony.player_autonomy or colony.is_sleeping("player"): return false
	var player: Dictionary = colony.get_resident("player")
	var closet: Dictionary = WorldLayout.interaction("closet", "player")
	return player.get("room", "street") == "player" and not closet.is_empty() and position_of(player).distance_to(closet.stand_at) <= 20

func cycle_person(direction: int) -> void:
	var people: Array = colony.active_residents()
	var current: int = people.find(colony.get_resident(selected_id))
	selected_id = people[posmod(current + direction, people.size())].id
	build_inspector()

func talk_nearby() -> void:
	if not chat_partner_id.is_empty():
		return_to_conversation()
		return
	var id: String = selected_id
	if id == "player":
		var distance: float = 45.0
		for other in colony.active_residents():
			if not player_chat.nearby(other.id): continue
			var candidate: float = position_of(other).distance_to(position_of(colony.get_resident("player")))
			if candidate < distance:
				id = other.id
				distance = candidate
	if id == "player":
		message("Acércate a un vecino o selecciónalo en el mapa para hablar.")
		return
	selected_id = id
	page = "hablar"
	if player_chat.nearby(id): start_player_conversation(id)
	open_inspector(id, "hablar")

func configure_keyboard() -> void:
	var bindings = {"city_left": [KEY_A, KEY_LEFT], "city_right": [KEY_D, KEY_RIGHT],
		"city_up": [KEY_W, KEY_UP], "city_down": [KEY_S, KEY_DOWN], "city_interact": [KEY_E], "city_cafe": [KEY_C], "city_pause": [KEY_SPACE]}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for code in bindings[action]:
			var key = InputEventKey.new()
			key.physical_keycode = code
			if not InputMap.action_has_event(action, key): InputMap.action_add_event(action, key)

func typing_in_field() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func keyboard_blocked() -> bool:
	return colony.is_exhausted() or not controls_active or typing_in_field() or overlay.notice_has_focus() or (is_instance_valid(home_ui) and home_ui.owns_keyboard()) or is_instance_valid(door_panel) or is_instance_valid(learning.panel) or (is_instance_valid(settlement_ui) and is_instance_valid(settlement_ui.panel)) or is_instance_valid(help_panel) or is_instance_valid(sleep_ui.panel)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_instance_valid(interaction_hover):
		interaction_hover.update(event.position)
	if _menu_suspended or not event is InputEventKey or not event.pressed or event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
		return
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		if event.echo: return
		if is_instance_valid(settlement_ui.panel): settlement_ui.close()
		elif is_instance_valid(help_panel): close_help()
		elif is_instance_valid(sleep_ui.panel): sleep_ui.close()
		elif is_instance_valid(learning.panel): learning.close()
		elif is_instance_valid(door_panel): close_door_panel()
		elif home_ui.is_reading(): home_ui.close()
		elif overlay.notice_has_focus(): overlay.dismiss_toast()
		elif typing_in_field(): get_viewport().gui_release_focus()
		elif inspector.visible:
			if page == "hablar": close_chat_panel()
			else: hide_inspector()
		elif managed_by_shell: menu_requested.emit()
		else: get_viewport().gui_release_focus()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(chat_input) and chat_input.has_focus() and page == "hablar" and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not event.shift_pressed:
		if not event.echo: send_player_dialogue()
		get_viewport().set_input_as_handled()
		return
	if not typing_in_field() and not event.echo and event.keycode == KEY_M and not is_instance_valid(door_panel) and not is_instance_valid(learning.panel) and not is_instance_valid(settlement_ui.panel) and not is_instance_valid(sleep_ui.panel):
		neighborhood.show_map()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(home_ui) and home_ui.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	if keyboard_blocked(): return
	if event.is_action_pressed("city_cafe"):
		if not event.echo: cafe_service.activate()
		get_viewport().set_input_as_handled()
		return
	for action in ["city_left", "city_right", "city_up", "city_down"]:
		if event.is_action_pressed(action, true):
			if not event.echo: take_control()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("city_interact"):
		interact_nearby()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("city_pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()

func clear_player_intentions() -> void:
	if colony.settlement_jobs.busy("player"): colony.settlement_jobs.cancel("player")
	colony.cancel_travel("player")
	if is_instance_valid(home_ui): home_ui.close()
	if is_instance_valid(seating): seating.stand()
	pending_home = ""
	pending_exit = false
	pending_shop = false
	pending_mentor = ""
	pending_item.clear()
	paths.erase("player")
	var player: Dictionary = colony.get_resident("player")
	player.target = player.pos.duplicate()
	player.travel_intent = ""

func cancel_player_ai() -> void:
	if encounters != null: encounters.cancel_for("player")
	if is_instance_valid(player_chat): player_chat.finish("")
	if decision_pending and deciding_id == "player":
		request.cancel_request()
		decision_pending = false
	if not dialogue_job.is_empty() and "player" in [dialogue_job.a, dialogue_job.b]:
		dialogue_request.cancel()
		release_conversation(false)
		dialogue_job.clear()
		dialogue_text = "Tomaste el control; la conversación se interrumpió sin guardar texto parcial."
		if page == "hablar": build_inspector()
	if not visit_job.is_empty():
		visit_request.cancel_request()
		visit_job.clear()

func suspend_for_menu() -> void:
	if encounters != null: encounters.cancel()
	if ambient_thoughts != null: ambient_thoughts.silence()
	if _menu_suspended: return
	interaction_hover.clear()
	_menu_was_paused = paused
	_menu_suspended = true
	# End reservations before clearing jobs so each neighbor recovers its current route.
	if inspector_page == "hablar" and is_instance_valid(chat_input) and not inspector_resident.is_empty():
		player_chat.clear_prepared(inspector_resident)
	if is_instance_valid(player_chat): player_chat.finish("")
	if not dialogue_job.is_empty(): release_conversation(false)
	control_epoch += 1
	dialogue_serial += 1
	decision_pending = false
	deciding_id = ""
	if is_instance_valid(request): request.cancel_request()
	if is_instance_valid(visit_request): visit_request.cancel_request()
	if is_instance_valid(dialogue_request): dialogue_request.cancel()
	dialogue_job.clear()
	visit_job.clear()
	colony.conversation_holds.clear()
	stream_text = ""
	stream_prefix = ""
	if is_instance_valid(door_text): door_text.text = "La visita se interrumpió al volver al menú. Puedes tocar de nuevo."
	keyboard_walking = false
	for action in ["city_left", "city_right", "city_up", "city_down", "city_interact", "city_pause"]:
		if InputMap.has_action(action): Input.action_release(action)
	get_viewport().gui_release_focus()
	paused = true
	controls_active = false
	set_process(false)
	set_process_input(false)
	hide()

func resume_from_menu() -> void:
	if not _menu_suspended: return
	_menu_suspended = false
	paused = _menu_was_paused
	controls_active = get_window().has_focus()
	show()
	set_process_input(true)
	set_process(true)
	refresh_status()

func take_control() -> void:
	if sync_exhaustion(): return
	control_epoch += 1
	if colony.wake_resident("player"): elapsed = 0.0
	if colony.player_autonomy: colony.set_player_autonomy(false)
	cancel_player_ai()
	clear_player_intentions()
	time_speed = 1.0
	if is_instance_valid(speed_button): speed_button.text = "1×"
	refresh_status()

func toggle_autonomy() -> void:
	if sync_exhaustion(): return
	if colony.is_sleeping("player"): sleep_ui.wake()
	if colony.player_autonomy:
		take_control()
		message("Tienes el control. Camina con WASD o flechas y usa E para interactuar.")
	else:
		control_epoch += 1
		cancel_player_ai()
		clear_player_intentions()
		close_door_panel()
		learning.close()
		colony.set_player_autonomy(true)
		paused = false
		riding_bicycle = false
		message("Tu personaje vive por su cuenta. Observa sus encuentros; WASD o flechas te devuelven el control.")
	refresh_status()

func toggle_pause() -> void:
	paused = not paused
	refresh_status()

func cycle_time_speed() -> void:
	if colony.is_sleeping("player"): return
	time_speed = {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}.get(time_speed, 1.0)
	speed_button.text = "%d×" % int(time_speed)
	refresh_status()

func move_player_keyboard(direction: Vector2, delta: float) -> bool:
	if sync_exhaustion(): return false
	if paused or keyboard_blocked() or not direction.is_finite() or direction.is_zero_approx(): return false
	if seating.is_seated() or not seating.pending_id.is_empty(): seating.stand()
	if colony.is_sleeping("player"): take_control()
	if colony.settlement_jobs.busy("player") or not chat_partner_id.is_empty() or colony.player_autonomy or not pending_home.is_empty() or pending_exit or pending_shop or not pending_mentor.is_empty() or not pending_item.is_empty():
		take_control()
	var player: Dictionary = colony.get_resident("player")
	if not dialogue_job.is_empty() and "player" in [dialogue_job.a, dialogue_job.b]: cancel_player_ai()
	var before = position_of(player)
	var speed: float = resident_walk_speed(player)
	var pos: Vector2 = crowd.manual_step(player, direction, clampf(delta, 0.0, 0.1) * speed)
	if before.distance_to(pos) > 0.001:
		facing["player"] = pos - before
		home_ui.close()
		if inspector.visible: hide_inspector()
	player.pos = [pos.x, pos.y]
	_record_environment_movement(str(player.room), before, pos)
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	player.activity = "Recorriendo la colonia" if WorldLayout.is_outdoor(player.room) else "Explorando la casa"
	paths.erase("player")
	keyboard_walking = before.distance_to(pos) > 0.001
	colony.cancel_travel("player")
	if WorldLayout.is_outdoor(player.room):
		var edge: Dictionary = WorldLayout.edge_exit(player.room, pos, direction)
		if not edge.is_empty() and colony.cross_exit("player", str(edge.id)):
			paths.erase("player")
			update_room()
	return true

func interact_nearby() -> void:
	if sync_exhaustion(): return
	if keyboard_blocked(): return
	if seating.is_seated():
		seating.stand()
		return
	if colony.is_sleeping("player"):
		sleep_ui.wake()
		return
	take_control()
	var player: Dictionary = colony.get_resident("player")
	var pos = position_of(player)
	var detail: Dictionary = _near_environment_target(pos)
	if not detail.is_empty():
		activate_world_interaction(detail)
		return
	if WorldLayout.is_outdoor(current_room):
		for target in WorldInteractions._targets(current_room,home_project_state()):
			if target.get("kind","") == "settlement" and pos.distance_to(target.rect.get_center()) < 30:
				activate_world_interaction(target)
				return
		for home in Navigation.door_positions():
			if WorldLayout.home_area(home) != current_room or not colony.home_available(home): continue
			if pos.distance_to(Navigation.door_positions()[home]) < 20:
				show_door_panel(home)
				return
		if current_room == WorldLayout.place_area("tienda") and pos.distance_to(WorldLayout.stand_at("shop", current_room)) < 20:
			learning.show_shop()
			return
		for item in Art.street_items(current_room, home_project_state()):
			if item.get("type", "") == "shop" or pos.distance_to(item.stand_at) >= 20: continue
			activate_world_interaction({"kind":"item", "item":item})
			return
		var seat: Dictionary = Seats.nearest(pos, 16.0, current_room)
		if not seat.is_empty():
			seating.request(str(seat.id))
			return
	else:
		if pos.distance_to(WorldLayout.point(WorldLayout.data().exit)) < 16:
			if colony.leave_home("player"):
				paths.erase("player")
				update_room()
			return
		for item in Art.interior_items(current_room):
			if pos.distance_to(item.stand_at) < 20:
				hide_inspector()
				pending_item = item.duplicate()
				pending_item.room = current_room
				player.target = [item.stand_at.x, item.stand_at.y]
				paused = false
				return
	var nearest = ""
	var distance = 40.0
	for person in colony.active_residents():
		if person.id == "player" or person.room != player.room: continue
		var d = pos.distance_to(position_of(person))
		if d < distance:
			distance = d
			nearest = person.id
	if not nearest.is_empty():
		selected_id = nearest
		page = "hablar"
		start_player_conversation(nearest)
		build_inspector()
		message("Estás junto a " + str(colony.get_resident(nearest).name) + ". Puedes conversar o consultar sus encargos.")
	else:
		message("Acércate a una persona, una puerta, la tienda o un objeto y pulsa E.")

func gather_neighbors() -> void:
	if sync_exhaustion(): return
	take_control()
	paused = false
	gathering = 20.0
	for resident in colony.active_residents():
		colony.apply_decision(resident.id, "cafe")
		if resident.get("room", "street") == "street":
			resident.target = [float(82 + colony.residents.find(resident) * 6), 194.0]
	message("Caminarán al café. Pausa al llegar para conversar.")

func toggle_bicycle() -> void:
	if sync_exhaustion(): return
	if colony.player_autonomy: take_control()
	if not colony.can_ride_bicycle():
		message("Tu bicicleta sigue averiada. Pide a Mateo que te enseñe a repararla; consulta el Diario.")
		return
	if not WorldLayout.is_outdoor(current_room):
		message("Saca la bicicleta a la calle para montar.")
		return
	seating.stand()
	riding_bicycle = not riding_bicycle
	actors.queue_redraw()
	world_labels.queue_redraw()
	hud.sync_actions()
	message("Vas en bicicleta: puedes recorrer el barrio más rápido." if riding_bicycle else "Bajaste de la bicicleta.")

func walk_to_area(area: String, destination: Vector2) -> void:
	if sync_exhaustion() or not WorldLayout.is_outdoor(area): return
	take_control()
	hide_inspector()
	if colony.travel_to("player", area, destination):
		paused = false
		paths.erase("player")

func walk_to_shop() -> void:
	if sync_exhaustion(): return
	take_control()
	var room: String = WorldLayout.place_area("tienda")
	var destination: Vector2 = WorldLayout.stand_at("shop", room)
	if not colony.travel_to("player", room, destination): return
	pending_shop = true
	paused = false
	learning.close()
	message("Caminando al mostrador de la tienda.")

func walk_to_mentor(mentor_id: String) -> void:
	if sync_exhaustion(): return
	take_control()
	var mentor: Dictionary = colony.get_resident(mentor_id)
	if mentor.is_empty(): return
	learning.close()
	open_inspector(mentor_id, "historia")
	pending_mentor = mentor_id
	selected_id = mentor_id
	page = "historia"
	paused = false
	follow_elapsed = 0.0
	follow_mentor()
	message("Vas hacia " + str(mentor.name) + ".")

func follow_mentor() -> void:
	if colony.is_exhausted(): return
	if pending_mentor.is_empty(): return
	var id = pending_mentor
	var approaching_chat: bool = player_chat.approach_id == id
	var mentor: Dictionary = colony.get_resident(id)
	var player: Dictionary = colony.get_resident("player")
	var room: String = mentor.get("room", "street")
	if player.room != room:
		if WorldLayout.is_outdoor(player.room) and WorldLayout.is_outdoor(room):
			close_door_panel()
			pending_home = ""
			colony.travel_to("player", room, position_of(mentor))
		elif WorldLayout.is_outdoor(player.room):
			var awaiting_this_door: bool = is_instance_valid(door_panel) and door_panel.get_meta("home_id", "") == room
			if pending_home != room and not awaiting_this_door: walk_to_door(room)
		elif not pending_exit:
			go_outside()
		pending_mentor = id
		if approaching_chat: player_chat.approach_id = id
		return
	if player.has("travel_route"): colony.cancel_travel("player")
	if position_of(player).distance_to(position_of(mentor)) < 20:
		pending_mentor = ""
		pending_home = ""
		pending_exit = false
		close_door_panel()
		player.target = player.pos.duplicate()
		selected_id = id
		if player_chat.approach_id == id:
			player_chat.approach_id = ""
			page = "hablar"
			start_player_conversation(id)
			build_inspector()
			message("Llegaste con " + str(mentor.name) + ". Saluda o escribe tu mensaje.")
			return
		open_inspector(id, page)
		message("Llegaste con " + str(mentor.name) + ". Abre «Encargos y aprendizajes» para continuar.")
		return
	# Retarget at most twice per second; routes remain cached between updates.
	if Vector2(player.target[0], player.target[1]).distance_to(position_of(mentor)) > 12 or not pending_home.is_empty() or pending_exit:
		close_door_panel()
		pending_home = ""
		pending_exit = false
		player.target = mentor.pos.duplicate()

func walk_to_station(station: Dictionary) -> void:
	if sync_exhaustion(): return
	take_control()
	pending_mentor = ""
	if current_room != "player":
		learning.close()
		walk_to_door("player")
		return
	for item in Art.interior_items("player"):
		if item.get("id", "") == station.get("id", ""):
			var player: Dictionary = colony.get_resident("player")
			player.target = [item.stand_at.x, item.stand_at.y]
			player.travel_intent = ""
			pending_item = item.duplicate()
			pending_item.room = "player"
			pending_home = ""
			pending_exit = false
			pending_shop = false
			paused = false
			learning.close()
			message("Acercándote a " + str(item.title).to_lower() + ".")
			return

func position_of(resident: Dictionary) -> Vector2:
	return Vector2(float(resident.pos[0]), float(resident.pos[1]))

func _process(delta: float) -> void:
	if _menu_suspended: return
	if not is_finite(delta) or delta < 0.0: return
	sync_exhaustion()
	keyboard_walking = false
	hint_elapsed += delta
	if hint_elapsed >= 0.2:
		hint_elapsed = 0.0
		interaction_hover.refresh()
		overlay.refresh()
		hud.refresh_stats()
		hud.sync_actions()
		update_hint()
		player_chat.update_availability()
		sleep_ui.refresh()
	player_chat.hold()
	var real_delta = clampf(delta, 0.0, 0.1)
	var was_sleeping: bool = colony.is_sleeping("player")
	ai_cooldown = maxf(0.0, ai_cooldown - real_delta)
	if not paused:
		var direct_movement = false
		if not keyboard_blocked() and not Input.is_physical_key_pressed(KEY_CTRL) and not Input.is_physical_key_pressed(KEY_META) and not Input.is_physical_key_pressed(KEY_ALT):
			direct_movement = move_player_keyboard(Input.get_vector("city_left", "city_right", "city_up", "city_down"), real_delta)
		if colony.is_sleeping("player"):
			advance_sleep(delta)
		else:
			advance_world(real_delta * time_speed, direct_movement, false)
	if colony.is_exhausted(): sleep_ui.refresh()
	if ambient_suppressed() or was_sleeping:
		ambient_thoughts.silence()
	else:
		ambient_thoughts.advance(delta, current_room)
	seating.update()
	cafe_service.refresh()
	update_environment(delta)
	update_camera(delta)
	queue_redraw()
	actors.queue_redraw()
	world_labels.queue_redraw()

func visual_minute() -> float:
	return float(colony.minute) + clampf(elapsed / WORLD_TICK_SECONDS, 0.0, 1.0) * 5.0

func update_environment(delta: float = 0.0) -> void:
	if not paused and not _menu_suspended: environment_seconds += maxf(0.0, delta)
	environment.advance(delta, colony.minute, current_room, paused or _menu_suspended, home_project_state())
	var ambient: Color = WorldLighting.ambient_for(visual_minute(), current_room)
	for layer: Node2D in [scenery, actors, world_surround, atmosphere]:
		layer.modulate = ambient
	atmosphere.queue_redraw()
	world_lights.queue_redraw()

func advance_sleep(real_seconds: float) -> void:
	if not is_finite(real_seconds) or real_seconds <= 0.0: return
	if colony.is_exhausted():
		advance_exhaustion_sleep(real_seconds)
		return
	var sleep: Dictionary = colony.get_resident("player").sleep
	# Keep the full real delta during rest, including slow frames. Bound work by
	# the remaining sleep and stop at wake-up, never fast-forward an awake player.
	var until_wake: float = ceilf((int(sleep.until) - colony.minute) / 5.0) * WORLD_TICK_SECONDS - elapsed
	var remaining: float = minf(real_seconds * SLEEP_SPEED, maxf(0.0, until_wake))
	while remaining > 0.000001 and colony.is_sleeping("player") and not paused:
		# Move and update routines at each five-minute boundary, so doors, beds,
		# energy and neighbors follow the same physical simulation as normal play.
		var step: float = minf(remaining, WORLD_TICK_SECONDS - elapsed)
		advance_world(step, false, true)
		remaining = maxf(0.0, remaining - step)
	if not colony.is_sleeping("player"): elapsed = 0.0

func sync_exhaustion() -> bool:
	colony.ensure_exhaustion()
	if not colony.is_exhausted():
		_exhaustion_handled = false
		return false
	if _exhaustion_handled: return true
	_exhaustion_handled = true
	# Interrupt pending actions once, without taking the character to a bed or
	# letting an old chat/follow target resume when the recovery finishes.
	var player: Dictionary = colony.get_resident("player")
	var position: Array = player.pos.duplicate()
	var room: String = player.room
	var previous_pause: bool = paused
	control_epoch += 1
	cancel_player_ai()
	player_chat.approach_id = ""
	clear_player_intentions()
	colony.set_player_autonomy(false)
	riding_bicycle = false
	keyboard_walking = false
	gathering = 0.0
	elapsed = 0.0
	time_speed = 1.0
	close_door_panel()
	learning.close()
	sleep_ui.close()
	hide_inspector()
	paused = previous_pause
	player.room = room
	player.pos = position
	player.target = position.duplicate()
	player.travel_intent = ""
	player.activity = "Durmiendo por agotamiento"
	get_viewport().gui_release_focus()
	interaction_hover.clear()
	sleep_ui.refresh()
	refresh_status()
	return true

func advance_exhaustion_sleep(real_seconds: float) -> void:
	if paused or _menu_suspended or not colony.is_exhausted() or not is_finite(real_seconds) or real_seconds <= 0.0: return
	# This recovery runs on real, unpaused seconds. The village keeps normal
	# time; neither 4x speed nor the bed's accelerated clock shortens the wait.
	var remaining: float = minf(real_seconds, float(colony.get_resident("player").sleep.remaining))
	while remaining > 0.00000001 and colony.is_exhausted():
		var step: float = minf(remaining, 0.1)
		advance_world(step, false, true)
		var woke: bool = colony.advance_exhaustion(step)
		remaining = maxf(0.0, remaining - step)
		if woke:
			_exhaustion_handled = false
			elapsed = 0.0
			refresh_status()
			break
	sleep_ui.refresh()

func advance_world(world_delta: float, direct_movement: bool, sleeping: bool) -> void:
	encounters.advance(world_delta, sleeping)
	follow_elapsed += world_delta
	if follow_elapsed >= 0.5:
		follow_elapsed = 0.0
		follow_mentor()
	gathering = maxf(0.0, gathering - world_delta)
	for resident in colony.active_residents():
		if resident.id in colony.conversation_holds: continue
		if colony.is_sleeping(resident.id): continue
		if resident.id == "player" and direct_movement: continue
		move_resident(resident, world_delta)
	resolve_player_arrival()
	update_room()
	elapsed += world_delta
	if elapsed + 0.000001 >= WORLD_TICK_SECONDS:
		elapsed = maxf(0.0, elapsed - WORLD_TICK_SECONDS)
		if sleeping or gathering <= 0.0:
			colony.tick((not use_jev or sleeping) and dialogue_job.is_empty())
			sync_exhaustion()
			player_chat.hold()
			if not dialogue_job.is_empty(): freeze_conversation()
			if use_jev and not sleeping and not colony.is_exhausted() and ai_cooldown <= 0.0:
				ai_cooldown = 4.0
				decide_with_jev()
		refresh_status()
		sleep_ui.refresh()

func resident_walk_speed(resident: Dictionary) -> float:
	if resident.id != "player": return NEIGHBOR_WALK_SPEED
	if riding_bicycle and WorldLayout.is_outdoor(resident.room) and colony.can_ride_bicycle(): return BICYCLE_SPEED
	return PLAYER_WALK_SPEED

func _start_resident_detour(resident: Dictionary, signature: String, occupied: Array[Vector2], portal_yield: bool = false) -> bool:
	if not crowd.can_recover(resident): return false
	var route: Array[Vector2] = crowd.recovery_route(resident, WorldLayout.point(resident.target), occupied, portal_yield)
	if route.is_empty(): return false
	# A temporary waypoint is not a new task. Keep the original destination and
	# intent so routines, home entry and learning never complete at the pull-aside.
	paths[resident.id] = {"key": signature, "points": route, "index": 0, "arrived": false, "blocked": false,
		"retry_in": CrowdMotion.RETRY_SECONDS, "stalled": 0.0, "progress_anchor": position_of(resident), "detour": true}
	return true

func move_resident(resident: Dictionary, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	if colony.is_sleeping(resident.id) or resident.id in colony.conversation_holds: return
	if resident.id == "player" and seating.is_seated(): return
	crowd.recover_overlap(resident)
	var room: String = resident.get("room", "street")
	var target = Vector2(float(resident.target[0]), float(resident.target[1]))
	var signature = "%s:%s:%s:%s" % [room, target, resident.get("travel_intent", ""), colony._routine_keys.get(resident.id, "")]
	var previous: Dictionary = paths.get(resident.id, {})
	if previous.get("key", "") == signature:
		previous["retry_in"] = maxf(0.0, float(previous.get("retry_in", 0.0)) - delta)
		previous["yield_cooldown"] = maxf(0.0, float(previous.get("yield_cooldown", 0.0)) - delta)
		if previous.get("arrived",false) and resident.has("travel_route") and previous.retry_in <= 0.0:
			previous.retry_in = CrowdMotion.RETRY_SECONDS
			colony.on_arrival(resident.id)
			if resident.room != room:
				paths.erase(resident.id)
				return

		var anchor: Vector2 = previous.get("progress_anchor", position_of(resident))
		if position_of(resident).distance_to(anchor) >= 1.0:
			previous["progress_anchor"] = position_of(resident)
			previous["stalled"] = 0.0
		else:
			previous["stalled"] = float(previous.get("stalled", 0.0)) + delta
		if not str(previous.get("yield_to", "")).is_empty():
			var peer: Dictionary = colony.get_resident(previous.yield_to)
			previous["yield_remaining"] = maxf(0.0, float(previous.get("yield_remaining", 0.0)) - delta)
			var offset: Vector2 = position_of(peer) - position_of(resident) if not peer.is_empty() else Vector2.ZERO
			var passed: bool = offset.dot(previous.yield_heading) <= -4.0 and (offset / CrowdMotion.CLEARANCE).length_squared() >= 1.15
			if not peer.is_empty() and peer.room == room and not passed and previous.yield_remaining > 0.0:
				previous["stalled"] = 0.0
				return
			previous.erase("yield_to")
			previous["stalled"] = 0.0
			previous["retry_in"] = 0.0
			previous["yield_cooldown"] = CrowdMotion.RECOVERY_SECONDS * 2.0
		# This is a voluntary, bounded pause by one of two opposing walkers.
		# The other keeps routing around a stationary body instead of chasing it.
		if previous.get("blocked", false) and not previous.get("detour", false) and float(previous.get("yield_cooldown", 0.0)) <= 0.0:
			var priority: String = crowd.passing_priority(resident)
			if not priority.is_empty():
				previous["yield_to"] = priority
				previous["yield_heading"] = (target - position_of(resident)).normalized()
				previous["yield_remaining"] = CrowdMotion.PASSING_WAIT_SECONDS
				previous["stalled"] = 0.0
				return
	# A released key can leave an off-grid position. Staying put needs no A* route.
	if position_of(resident).distance_to(target) < 0.001 and not (previous.get("key", "") == signature and previous.get("detour", false)):
		if previous.get("key", "") != signature or not previous.get("arrived", false):
			paths[resident.id] = {"key": signature, "points": [], "index": 0, "arrived": true, "retry_in": CrowdMotion.RETRY_SECONDS,
				"stalled": 0.0, "progress_anchor": position_of(resident)}
			colony.on_arrival(resident.id)
			if resident.room != room:
				paths.erase(resident.id)
				return
		elif not str(resident.get("travel_intent", "")).is_empty():
			# A doorway can be occupied on the other side. Retry without relocating it.
			var arrived_path: Dictionary = paths[resident.id]
			if arrived_path.retry_in <= 0.0:
				arrived_path.retry_in = CrowdMotion.RETRY_SECONDS
				colony.on_arrival(resident.id)
				if resident.room != room:
					paths.erase(resident.id)
					return
		# Two opposite portal crossings cannot clear each other by waiting. The
		# person outside walks aside first, allowing the person indoors to leave.
		var waiting: Dictionary = paths[resident.id]
		if resident.room != room or float(waiting.get("stalled", 0.0)) < CrowdMotion.RECOVERY_SECONDS or crowd.exit_waiter(resident).is_empty(): return
		waiting["stalled"] = 0.0
		if not _start_resident_detour(resident, signature, crowd.people(resident), true): return
	var occupied: Array[Vector2] = crowd.people(resident)
	previous = paths.get(resident.id, {})
	if previous.get("key", "") != signature or (previous.get("blocked", false) and previous.retry_in <= 0.0):
		var route: Array = crowd.route(resident, target, occupied)
		var same_goal: bool = previous.get("key", "") == signature
		paths[resident.id] = {"key": signature, "points": route, "index": 0, "arrived": false, "blocked": route.is_empty(), "retry_in": CrowdMotion.RETRY_SECONDS,
			"stalled": float(previous.get("stalled", 0.0)) if same_goal else 0.0,
			"yield_cooldown": float(previous.get("yield_cooldown", 0.0)) if same_goal else 0.0,
			"progress_anchor": previous.get("progress_anchor", position_of(resident)) if same_goal else position_of(resident)}
	var path: Dictionary = paths[resident.id]
	if path.get("blocked", false) and float(path.get("stalled", 0.0)) >= CrowdMotion.RECOVERY_SECONDS:
		path["stalled"] = 0.0
		if _start_resident_detour(resident, signature, occupied): path = paths[resident.id]
	if path.get("blocked", false): return
	var speed: float = resident_walk_speed(resident)
	var remaining = maxf(0.0, delta) * speed
	while path.index < path.points.size() and remaining > 0.00001:
		var next_point: Vector2 = path.points[path.index]
		var distance = position_of(resident).distance_to(next_point)
		if distance < 0.01:
			path.index += 1
			continue
		var before = position_of(resident)
		# Swept, short steps prevent tunnelling even during accelerated sleep/time.
		var pos = before.move_toward(next_point, minf(remaining, 1.0))
		if before.distance_to(pos) < 0.00001: break
		if not crowd.can_step(before, pos, room, occupied):
			path.blocked = true
			break
		if before.distance_to(pos) > 0.001: facing[resident.id] = pos - before
		resident.pos = [pos.x, pos.y]
		if resident.id == "player": _record_environment_movement(room, before, pos)
		remaining = maxf(0.0, remaining - before.distance_to(pos))
		if pos.distance_to(next_point) < 0.01:
			path.index += 1
	if not path.arrived and path.index >= path.points.size():
		if path.get("detour", false):
			path.detour = false
			path.blocked = true
			path.retry_in = CrowdMotion.YIELD_WAIT_SECONDS
			path.stalled = 0.0
			path.progress_anchor = position_of(resident)
		elif position_of(resident).distance_to(target) < 0.1:
			path.arrived = true
			colony.on_arrival(resident.id)
			if resident.room != room: paths.erase(resident.id)
		else:
			# The desired point may still be occupied. Wait, then find a new route.
			path.blocked = true

func update_room() -> void:
	_sync_environment_geometry()
	if _environment_revision != int(colony.environment.state.get("revision",0)) or _settlement_revision != int(colony.settlement.state.revision) or _settlement_minute != colony.minute:
		_environment_revision = int(colony.environment.state.get("revision",0))
		_settlement_revision = int(colony.settlement.state.revision)
		_settlement_minute = colony.minute
		scenery.interior_state = home_project_state()
		scenery.queue_redraw()
	var next_room: String = colony.get_resident("player").get("room", "street")
	if current_room != next_room:
		var changed_block: bool = WorldLayout.is_outdoor(current_room) and WorldLayout.is_outdoor(next_room)
		seating.stand(false)
		interaction_hover.clear()
		current_room = next_room
		if not WorldLayout.is_outdoor(current_room):
			riding_bicycle = false
			hud.sync_actions()
		scenery.room = current_room
		actors.queue_redraw()
		world_labels.queue_redraw()
		scenery.interior_state = home_project_state()
		scenery.queue_redraw()
		world_surround.queue_redraw()
		close_door_panel()
		learning.close()
		settlement_ui.close()
		home_ui.refresh()
		apply_responsive_layout()
		if changed_block: neighborhood.changed_area()
	home_ui.refresh()
	if is_instance_valid(world_lights): update_environment()

func home_project_state() -> Dictionary:
	var unlocks: Array = colony.progression_state().unlocks
	return {"bicycle_repaired": colony.can_ride_bicycle(), "bicycle_away": false,
		"garden_planted": "cuidar_jardin" in unlocks, "tea_ready": "servir_te" in unlocks, "settlement":colony.settlement.view(), "environment":colony.environment.view()}

func _record_environment_movement(room: String, before: Vector2, after: Vector2) -> void:
	if before.distance_to(after) < 0.001: return
	colony.environment.record_motion(room,before,after)
	# Fallen fruit is a one-use world object, not another repeatable inventory source.
	for fruit: Dictionary in colony.environment.view().get("fruit",[]):
		if str(fruit.room) != room: continue
		var at: Vector2 = WorldLayout.point(fruit.at) if fruit.at is Array else fruit.at
		if after.distance_to(at) > 5.0: continue
		var result: Dictionary = colony.environment.collect_fruit(str(fruit.tree_id))
		if result.get("ok",false):
			# Walking onto a clicked apple can collect it before its approach point.
			# Finish that intent now so arrival cannot overwrite the success notice.
			if str(pending_item.get("fruit_id","")) == str(fruit.tree_id): pending_item.clear()
			message(str(result.message))
			refresh_status()

func _near_environment_target(pos: Vector2) -> Dictionary:
	var best := {}
	var distance := 18.0
	var targets: Array[Dictionary] = WorldInteractions._targets(current_room,home_project_state())
	for target: Dictionary in targets:
		if str(target.get("kind","")) not in ["environment","fruit"]: continue
		var at: Vector2 = target.item.stand_at
		if pos.distance_to(at) < distance:
			distance = pos.distance_to(at)
			best = target
	# A nearby decoration must not steal E from the bed, wardrobe, exit or
	# another established action whose approach point the player is closer to.
	if best.is_empty(): return best
	for target: Dictionary in targets:
		var kind: String = str(target.get("kind",""))
		if kind in ["environment","fruit"]: continue
		var at: Vector2 = target.rect.get_center()
		if kind == "door": at = WorldLayout.point(WorldLayout.data().doors[str(target.home_id)])
		elif target.get("item",{}).has("stand_at"): at = target.item.stand_at
		if pos.distance_to(at) <= distance: return {}
	return best

func _sync_environment_geometry() -> void:
	var obstacles := {}
	for tree: Dictionary in colony.environment.view().get("treeplants",[]):
		if int(tree.stage) < 3: continue
		var at: Vector2 = WorldLayout.point(tree.at) if tree.at is Array else tree.at
		var trunk := Rect2(at-Vector2(3,4),Vector2(6,4))
		# Growth never traps or teleports somebody standing on a young sapling.
		# The trunk becomes solid as soon as the occupied root clears.
		var occupied := false
		for person: Dictionary in colony.active_residents():
			if str(person.room) == str(tree.room) and trunk.grow(2).has_point(position_of(person)): occupied = true; break
		if occupied: continue
		if not obstacles.has(str(tree.room)): obstacles[str(tree.room)] = []
		obstacles[str(tree.room)].append(trunk)
	Navigation.set_environment_obstacles(obstacles)

func go_outside() -> void:
	if sync_exhaustion() or WorldLayout.is_outdoor(current_room): return
	take_control()
	pending_mentor = ""
	var player: Dictionary = colony.get_resident("player")
	player.travel_intent = ""
	player.target = WorldLayout.data().exit.duplicate()
	pending_exit = true
	pending_home = ""
	pending_shop = false
	pending_item.clear()
	paused = false

func resolve_player_arrival() -> void:
	if colony.is_exhausted(): return
	seating.update()
	var player: Dictionary = colony.get_resident("player")
	var arrival_distance := 0.9 if pending_item.get("environment",false) else 5.0
	if not pending_item.is_empty() and player.get("room", "street") == pending_item.room and position_of(player).distance_to(pending_item.stand_at) < arrival_distance:
		var item = pending_item.duplicate()
		pending_item.clear()
		if item.has("fruit_id"):
			var result: Dictionary = colony.environment.collect_fruit(str(item.fruit_id))
			message(str(result.message))
			update_room()
			refresh_status()
			return
		if item.get("environment",false):
			var result: Dictionary = colony.environment.house_action(str(item.room),str(item.prop_key),"inspect")
			if result.get("ok",false): home_ui.show_item(item)
			else: message(str(result.message))
			return
		if item.room == "player" and item.get("id", "") == "bed":
			sleep_ui.show_choices()
			return
		if item.room == "player" and item.get("id", "") == "closet":
			open_inspector("player", "aspecto")
			return
		if WorldLayout.is_outdoor(item.room): colony.observe_area_item("player", item.room, item.title, item.text)
		else: colony.observe_house_item("player", item.room, item.title, item.text)
		remember_notice(str(item.title) + ": " + str(item.text), "OBJETO")
		if item.room == "player" and learning.has_station(item.get("id", "")):
			learning.show_station(item.id)
		else:
			home_ui.show_item(item)
	if pending_shop and player.get("room", "street") == WorldLayout.place_area("tienda") and position_of(player).distance_to(WorldLayout.stand_at("shop", WorldLayout.place_area("tienda"))) < 5:
		pending_shop = false
		learning.show_shop()
	if pending_exit and position_of(player).distance_to(WorldLayout.point(WorldLayout.data().exit)) < 5:
		if colony.leave_home("player"):
			pending_exit = false
			paths.erase("player")
	if not pending_home.is_empty() and player.get("room", "street") == WorldLayout.home_area(pending_home):
		var door: Vector2 = Navigation.door_positions().get(pending_home, Vector2.ZERO)
		if position_of(player).distance_to(door) < 5:
			var home = pending_home
			pending_home = ""
			show_door_panel(home)

func walk_to_door(home_id: String) -> void:
	if sync_exhaustion() or not Navigation.door_positions().has(home_id): return
	take_control()
	close_door_panel()
	var door: Vector2 = Navigation.door_positions()[home_id]
	if not colony.travel_to("player", WorldLayout.home_area(home_id), door): return
	pending_home = home_id
	paused = false
	selected_id = "player"
	build_inspector()
	message("Caminando a tu casa." if home_id == "player" else "Caminando a casa de " + str(colony.get_resident(home_id).name) + ".")

func close_door_panel() -> void:
	if is_instance_valid(door_panel):
		var focused: Control = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused) and door_panel.is_ancestor_of(focused): get_viewport().gui_release_focus()
		door_panel.get_parent().remove_child(door_panel)
		door_panel.queue_free()
		door_panel = null
	door_primary = null
	door_return = null
	if is_instance_valid(door_backdrop):
		door_backdrop.queue_free()
		door_backdrop = null
	if not visit_job.is_empty():
		visit_request.cancel_request()
		visit_job.clear()

func show_door_panel(home_id: String) -> void:
	if sync_exhaustion(): return
	close_help()
	learning.close()
	close_door_panel()
	var context: Dictionary = colony.visit_context("player", home_id)
	door_backdrop = modal_backdrop()
	door_panel = Panel.new()
	door_panel.name = "DoorModal"
	door_panel.set_meta("home_id", home_id)
	door_panel.size = Vector2(396, 192)
	door_panel.clip_contents = true
	door_panel.add_theme_stylebox_override("panel", box(PAPER, INK, 2))
	add_child(door_panel)
	label_at(door_panel, "TU CASA" if home_id == "player" else "CASA DE " + str(colony.get_resident(home_id).name).to_upper(), Vector2(16, 16), Vector2(364, 28), 18)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(16, 56)
	scroll.size = Vector2(364, 76)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	door_panel.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	door_text = Label.new()
	door_text.text = "Hay alguien dentro. Toca y espera su respuesta." if context.get("occupied", false) else "La casa está vacía y la puerta está abierta."
	door_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	door_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door_text.add_theme_font_size_override("font_size", 16)
	column.add_child(door_text)
	if home_id == "player": door_text.text = "Tu hogar, tus proyectos. La bicicleta espera una segunda oportunidad."
	door_primary = button_at(door_panel, "Tocar la puerta" if context.get("occupied", false) else "Entrar", Vector2(16, 148), Vector2(220, 28), func(): knock_home(home_id), "Enter: elegir · Flechas: cambiar")
	door_primary.name = "PrimaryAction"
	door_return = button_at(door_panel, "Volver", Vector2(252, 148), Vector2(128, 28), close_door_panel, "Enter: elegir · Escape: volver")
	door_return.name = "BackAction"
	configure_modal_actions([door_primary, door_return])
	_layout_modals()
	door_primary.grab_focus()
	interaction_hover.clear()

func configure_modal_actions(buttons: Array[Button]) -> void:
	for index in buttons.size():
		var button: Button = buttons[index]
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var previous: NodePath = button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		var following: NodePath = button.get_path_to(buttons[(index + 1) % buttons.size()])
		button.focus_previous = previous
		button.focus_next = following
		button.focus_neighbor_left = previous
		button.focus_neighbor_top = previous
		button.focus_neighbor_right = following
		button.focus_neighbor_bottom = following
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color.TRANSPARENT
		outline.border_color = Color("efd899")
		outline.set_border_width_all(2)
		outline.set_expand_margin_all(2)
		outline.anti_aliasing = false
		button.add_theme_stylebox_override("focus", outline)
		style_button(button)
		button.focus_entered.connect(func(): style_button(button, true))
		button.focus_exited.connect(func(): style_button(button, false))

func knock_home(home_id: String) -> void:
	if sync_exhaustion(): return
	if not visit_job.is_empty():
		return
	var context: Dictionary = colony.visit_context("player", home_id)
	if not context.get("valid", false):
		door_text.text = str(context.get("reason", "Acércate a la puerta."))
		return
	if home_id == "player" or not use_jev or not context.get("occupied", false):
		finish_visit(home_id, colony.request_home_visit("player", home_id))
		return
	var owner_id: String = context.get("resident_id", home_id)
	var player: Dictionary = colony.get_resident("player")
	var payload = {"resident": colony.context_for(owner_id, "player", "visita confianza encuentros"), "visitor": {"id": "player", "name": player.name}, "visit": {"home_id": home_id, "known": bool(context.get("known", false)), "encounters": int(context.get("encounters", 0)), "routine": str(context.get("routine", "En casa"))}}
	visit_job = {"home_id": home_id, "signature": str(context.get("occupant_signature", ""))}
	door_text.text = "Toc, toc... espera su decisión."
	var error = visit_request.request(service_url + "/visit-decision", service_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		visit_job.clear()
		door_text.text = "No se pudo solicitar la visita. Inténtalo de nuevo."

func _visit_received(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if visit_job.is_empty(): return
	var home_id: String = visit_job.home_id
	var signature: String = visit_job.signature
	visit_job.clear()
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or status != 200 or not data is Dictionary or not data.get("allowed") is bool:
		if is_instance_valid(door_text): door_text.text = "No llegó una decisión de Jev. La puerta permanece cerrada."
		return
	if not is_instance_valid(door_panel): return
	finish_visit(home_id, colony.apply_visit_decision("player", home_id, data.allowed, str(data.get("source", "jev")), signature))

func finish_visit(home_id: String, decision: Dictionary) -> void:
	if sync_exhaustion(): return
	if decision.get("allowed", false) and colony.enter_home("player", home_id):
		paths.erase("player")
		update_room()
		overlay.dismiss_toast()
	else:
		if is_instance_valid(door_text): door_text.text = colony.last_error if decision.get("allowed", false) else str(decision.get("reason", colony.last_error))

func refresh_status() -> void:
	clock_label.text = "Día %d · %02d:%02d" % [1 + colony.minute / 1440, (colony.minute / 60) % 24, colony.minute % 60]
	provider_label.text = "Rutinas durante el sueño" if colony.is_sleeping("player") else "Decisiones con IA" if use_jev else "Rutinas locales"
	provider_label.tooltip_text = ""
	hud.sync_actions()
	hud.refresh_stats()
	home_ui.refresh()
	collect_world_events()
	update_hint()
	if page == "recuerdos": build_inspector()
	if page == "historia" and is_instance_valid(activity_label):
		activity_label.text = str(colony.get_resident(selected_id).activity)
	if resident_ui != null: resident_ui.refresh_relationship()
	if cafe_service != null: cafe_service.refresh()

func collect_world_events() -> void:
	# Background events belong to history; they never open an on-map notification.
	for entry in colony.events:
		if not seen_world_events.has(entry):
			seen_world_events[entry] = true
			remember_notice(entry, "BARRIO")
	if seen_world_events.size() > 180:
		seen_world_events.clear()
		for entry in colony.events: seen_world_events[entry] = true

func remember_notice(text: String, source: String) -> void:
	notice_history.append({"text": text, "source": source, "time": colony.minute})
	if notice_history.size() > 100: notice_history.pop_front()

func show_notice(text: String) -> void:
	if feedback.text == text and overlay.toast.visible: return
	feedback.text = text
	msg_scroll.set_deferred("scroll_vertical", 0)
	overlay.show_notice()

func message(text: String) -> void:
	remember_notice(text, "AVISO")
	show_notice(text)

func update_hint() -> void:
	if not is_instance_valid(hint_label): return
	var content := ""
	if home_ui.is_reading():
		overlay.show_hint("")
		return
	if colony.is_exhausted():
		content = "Recuperando fuerzas"
	elif colony.is_sleeping("player"):
		content = "E / WASD: despertar"
	elif colony.settlement_jobs.busy("player"):
		var job: Dictionary = colony.settlement.state.jobs.player
		content = "%s · %d%% · WASD: cancelar" % [colony.settlement.task_spec(job.task_id).title, int(100.0 * float(job.progress) / float(job.required))]
	elif seating.is_seated():
		content = "E / WASD: levantarte"
	elif is_instance_valid(hud) and not hud.context_hint().is_empty():
		content = hud.context_hint()
	elif is_instance_valid(interaction_hover) and not interaction_hover.hint().is_empty():
		content = interaction_hover.hint()
	elif not seating.pending_id.is_empty():
		content = "Buscando asiento · WASD: cancelar"
	elif pending_exit:
		content = "Hacia la salida · WASD: cancelar"
	elif not pending_item.is_empty():
		content = "Acercándote · " + str(pending_item.title)
	elif not paused and not colony.player_autonomy:
		var player: Dictionary = colony.get_resident("player")
		var pos: Vector2 = position_of(player)
		if WorldLayout.is_outdoor(current_room):
			for home in Navigation.door_positions():
				if WorldLayout.home_area(home) != current_room or not colony.home_available(home): continue
				if pos.distance_to(Navigation.door_positions()[home]) < 20: content = "E: tocar / entrar"
			if current_room == WorldLayout.place_area("tienda") and pos.distance_to(WorldLayout.stand_at("shop", current_room)) < 20: content = "E: comprar"
			if content.is_empty() and not Seats.nearest(pos, 16.0, current_room).is_empty(): content = "E: sentarte"
		else:
			if pos.distance_to(WorldLayout.point(WorldLayout.data().exit)) < 16: content = "E: salir"
			for item in Art.interior_items(current_room):
				if pos.distance_to(item.stand_at) < 20:
					var action := "Mirar"
					if current_room == "player": action = {"bed":"Dormir", "closet":"Personalizar", "bicycle":"Revisar", "planting":"Cultivar", "tea_station":"Preparar"}.get(str(item.get("id", "")), "Mirar")
					content = "E: %s · %s" % [action, str(item.title)]
					break
	overlay.show_hint(content)

func modal_backdrop() -> ColorRect:
	if is_instance_valid(home_ui): home_ui.close()
	var shade = ColorRect.new()
	shade.color = Color(0.09, 0.14, 0.11, 0.55)
	shade.size = layout_size()
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	get_viewport().gui_release_focus()
	return shade

func close_help() -> void:
	if is_instance_valid(help_panel):
		help_panel.get_parent().remove_child(help_panel)
		help_panel.queue_free()
		help_panel = null
		paused = help_was_paused
	if is_instance_valid(help_backdrop):
		help_backdrop.queue_free()
		help_backdrop = null
	if is_instance_valid(clock_label): refresh_status()

func open_reading_panel(title: String) -> VBoxContainer:
	close_help()
	close_door_panel()
	learning.close()
	help_was_paused = paused
	paused = true
	help_backdrop = modal_backdrop()
	help_panel = Panel.new()
	help_panel.position = Vector2(104, 56)
	help_panel.size = Vector2(560, 344)
	help_panel.clip_contents = true
	help_panel.add_theme_stylebox_override("panel", box(PAPER, INK, 2))
	add_child(help_panel)
	label_at(help_panel, title, Vector2(20, 16), Vector2(408, 28), 20)
	button_at(help_panel, "Cerrar", Vector2(456, 16), Vector2(84, 28), close_help, "Escape: volver al juego.")
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 60)
	scroll.size = Vector2(520, 264)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	help_panel.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	refresh_status()
	return column

func reading_text(column: VBoxContainer, title: String, text: String) -> void:
	var heading = Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("985239"))
	column.add_child(heading)
	var body = Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_constant_override("line_spacing", 4)
	column.add_child(body)

func show_help() -> void:
	var column = open_reading_panel("CÓMO JUGAR")
	reading_text(column, "1. CREA TU PERSONAJE", "Entra a tu casa y acércate al clóset para cambiar nombre, piel, ojos, cabello, barba, ropa y accesorios. Haz clic o pulsa E. Guardar conserva tus cambios.")
	reading_text(column, "2. EXPLORA LA COLONIA", "WASD o flechas: caminar. También puedes hacer clic en un camino. Pasa el mouse por un objeto: si brilla, puedes usarlo con un clic. Acércate a una puerta, tienda, persona u objeto y pulsa E. En una casa ocupada, toca y espera permiso.")
	reading_text(column, "EL BARRIO", "Cada camino que sale por un borde lleva al bloque vecino. M abre el mapa. Las casas, el huerto y el taller están repartidos; tus vecinos recorren esos mismos caminos.")
	reading_text(column, "3. CONOCE Y APRENDE", "Selecciona a un vecino para leer su historia, recuerdos y horario. Diario muestra los encargos y tu siguiente paso. Para reparar tu bicicleta, empieza con Mateo.")
	reading_text(column, "JUGAR U OBSERVAR", "Vivir solo activa la rutina de tu personaje. Tomar control o empezar a caminar te devuelve el mando. 1× / 2× / 4× cambia la velocidad del mundo. Espacio pausa o continúa.")
	reading_text(column, "DORMIR", "En tu casa, pulsa E junto a la cama o haz clic en ella. Cada hora de sueño dura un segundo real: ocho horas son ocho segundos. La colonia sigue activa mientras descansas. E, WASD o Despertar te permiten levantarte antes.")
	reading_text(column, "TOMAR UN CAFÉ", "Siéntate en un banquito de las mesas del café. Haz clic en Pedir café o pulsa C para pagar %d monedas. Después, C bebe tu taza sin otro cobro. E o WASD te levanta." % colony.COFFEE_PRICE)
	reading_text(column, "PANELES Y CONVERSACIONES", "Hablar abre una charla con un vecino. Elige una respuesta o escribe; Enter envía y Shift+Enter añade una línea. La × o caminar termina el encuentro. Cada nueva charla empieza limpia, pero el vecino conserva sus recuerdos. Mientras escribes, las teclas no mueven al personaje.")
	reading_text(column, "CONVERSACIONES Y RUTINAS", "Los horarios y recorridos funcionan localmente. La IA inicia activada si está configurada y puedes cambiarla desde la barra superior. Sin conexión configurada, el chat usa respuestas locales. Guardar conserva los recuerdos y conocimientos.")

func show_history() -> void:
	collect_world_events()
	var column = open_reading_panel("HISTORIAL DEL BARRIO")
	if notice_history.is_empty():
		reading_text(column, "TU HISTORIA EMPIEZA AQUÍ", "Los avisos, encuentros y aprendizajes aparecerán aquí. Acércate a un vecino para empezar.")
	for index in range(notice_history.size() - 1, -1, -1):
		var entry: Dictionary = notice_history[index]
		var time = int(entry.time)
		reading_text(column, "%s · DÍA %d · %02d:%02d" % [entry.source, 1 + time / 1440, (time / 60) % 24, time % 60], entry.text)

func save_now() -> void:
	if preview_mode:
		message("La vista previa no modifica tu partida.")
		return
	if not save_allowed:
		message("No se guardó: revisa el archivo de partida indicado al iniciar.")
		return
	message("Partida guardada: apariencia, experiencias y conocimientos." if colony.save_game() else colony.last_error)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		controls_active = false
		if is_instance_valid(interaction_hover): interaction_hover.clear()
		keyboard_walking = false
		for action in ["city_left", "city_right", "city_up", "city_down"]:
			if InputMap.has_action(action): Input.action_release(action)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		controls_active = not _menu_suspended
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if managed_by_shell: return
		player_chat.finish("")
		if not preview_mode and save_allowed and not colony.save_game():
			message("No se pudo guardar. La ventana seguirá abierta: " + colony.last_error)
			return
		get_tree().quit()

func pointer_actor_signature() -> Array:
	var result: Array = [paused, riding_bicycle, seating.active_id, seating.pending_id]
	for resident: Dictionary in colony.active_residents():
		if resident.get("room", "street") != current_room: continue
		var state: Dictionary = colony.daily_state(resident.id)
		result.append([resident.id, position_of(resident).round(), resident.target.duplicate(), resident.appearance.duplicate(), facing.get(resident.id, Vector2.DOWN), state.get("kind", ""), state.get("action", "")])
	return result

func _pointer_frame_bounds(frame: Dictionary) -> Rect2:
	var texture: Texture2D = frame.texture
	var source: Rect2 = frame.source
	var identity: int = texture.get_rid().get_id()
	var key: String = "%d:%s" % [identity, source]
	if not _pointer_actor_bounds.has(key):
		if not _pointer_actor_images.has(identity):
			var bitmap: Image = texture.get_image()
			if bitmap != null and bitmap.is_compressed() and bitmap.decompress() != OK: bitmap = null
			_pointer_actor_images[identity] = {"texture": texture, "image": bitmap}
		var image: Image = _pointer_actor_images[identity].image
		_pointer_actor_bounds[key] = Rect2(image.get_region(Rect2i(source)).get_used_rect()) if image != null else Rect2()
	var bounds: Rect2 = _pointer_actor_bounds[key]
	if frame.get("flip_h", false): bounds.position.x = source.size.x - bounds.end.x
	return bounds

func pointer_actor_rect(resident: Dictionary, state: Dictionary) -> Rect2:
	if resident.id == "player" and seating.is_seated(): return Seats.actor_rect(seating.active_seat())
	if ActivityVisuals.is_bed_sleep(resident, state, current_room):
		# Only the head represents the sleeper; the quilt remains part of the bed.
		return ActivityVisuals.sleep_layout(current_room).head
	var feet: Vector2 = position_of(resident).round()
	var riding: bool = resident.id == "player" and riding_bicycle and WorldLayout.is_outdoor(current_room)
	var direction: Vector2 = facing.get(resident.id, Vector2.DOWN)
	if riding: return Sprites.bicycle_actor_rect(feet, direction)
	var walking: bool = not paused and (position_of(resident).distance_to(WorldLayout.point(resident.target)) > 2.0 or resident.id == "player" and keyboard_walking)
	var phase: int = int(Time.get_ticks_msec() / 150) % 4
	var pose: Dictionary = ActivityVisuals.active_pose(resident, state, feet, 0 if paused else int(Time.get_ticks_msec() / 450) % 4, direction) if not walking else {}
	if not pose.is_empty():
		direction = pose.direction
		phase = pose.frame
	var origin: Vector2 = feet - Vector2(12, 30)
	var result := Rect2()
	for layer: Dictionary in Sprites.character_layers(resident.appearance, walking or not pose.is_empty(), phase, direction):
		var bounds: Rect2 = _pointer_frame_bounds(layer)
		if not bounds.has_area(): continue
		bounds.position += origin + layer.get("offset", Vector2.ZERO)
		result = result.merge(bounds) if result.has_area() else bounds
	if not pose.is_empty() and pose.cup.has_area(): result = result.merge(pose.cup)
	return result

func resident_depth(resident: Dictionary, state: Dictionary) -> float:
	if resident.id == "player" and seating.is_seated(): return float(seating.active_seat().sort_y)
	return ActivityVisuals.sort_y(resident, state, current_room, position_of(resident))

func pick_world_target(point: Vector2, project_state: Dictionary = {}) -> Dictionary:
	var interaction: Dictionary = WorldInteractions.pick(point, current_room, project_state)
	var front_y: float = float(interaction.get("object", {}).get("y", -INF))
	var picked: Dictionary = interaction
	var objects: Array[Dictionary] = Sprites.scenery_objects(current_room, project_state)
	for resident: Dictionary in colony.active_residents():
		if resident.get("room", "street") != current_room: continue
		var state: Dictionary = colony.daily_state(resident.id)
		var depth: float = resident_depth(resident, state)
		if depth < front_y or not pointer_actor_rect(resident, state).has_point(point): continue
		var covered := false
		for object: Dictionary in objects:
			if float(object.y) > depth and object.rect.has_point(point):
				covered = true
				break
		if covered: continue
		front_y = depth
		picked = {"kind": "resident", "resident_id": resident.id}
	return picked

func _gui_input(event: InputEvent) -> void:
	if sync_exhaustion(): return
	if interaction_hover.blocked(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not world_map_rect.has_point(event.position) or point_over_interface(event.position):
			return
		var pos: Vector2 = screen_to_world(event.position)
		get_viewport().gui_release_focus()
		var interaction: Dictionary = pick_world_target(pos, home_project_state())
		if not interaction.is_empty():
			activate_world_interaction(interaction)
			return
		var player: Dictionary = colony.get_resident("player")
		var path: Array = Navigation.route(position_of(player), pos, current_room)
		if not path.is_empty():
			hide_inspector()
			take_control()
			pending_mentor = ""
			var goal: Vector2 = path[-1]
			player.travel_intent = ""
			player.target = [goal.x, goal.y]
			pending_home = ""
			pending_exit = false
			pending_shop = false
			pending_item.clear()
			paused = false
			selected_id = "player"
			build_inspector()

func begin_settlement_task(task_id: String, worker: String = "player") -> void:
	if sync_exhaustion(): return
	if worker == "player": take_control()
	var result: Dictionary = colony.settlement_jobs.request(worker,task_id)
	message(str(result.message))
	if result.ok:
		settlement_ui.close()
		learning.close()
		hide_inspector()
		paths.erase(worker)
		paused = false
		update_room()
		refresh_status()

func activate_world_interaction(target: Dictionary) -> void:
	if sync_exhaustion(): return
	match str(target.get("kind", "")):
		"settlement":
			var task_id: String = str(target.get("task_id",""))
			if task_id.is_empty(): settlement_ui.show_overview()
			else: settlement_ui.show_task(task_id)
		"resident":
			if target.resident_id == "player" and seating.is_seated():
				seating.stand()
				return
			open_inspector(str(target.resident_id), "hablar" if target.resident_id == chat_partner_id else "historia")
		"seat": seating.request(str(target.seat_id))
		"door": walk_to_door(target.home_id)
		"shop": walk_to_shop()
		"exit": go_outside()
		"area": walk_to_area(str(target.to), target.spawn)
		"item", "environment", "fruit":
			var item: Dictionary = target.item
			take_control()
			hide_inspector()
			var destination: Vector2 = item.stand_at
			var player: Dictionary = colony.get_resident("player")
			player.target = [destination.x, destination.y]
			pending_item = item.duplicate()
			pending_item.room = current_room
			paused = false
			overlay.dismiss_toast()
			update_hint()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout_size()), Color("65736b"))

func draw_world_actors(canvas: CanvasItem) -> void:
	WorldLighting.draw_fixture_lights(canvas, current_room, visual_minute())
	var draw_order: Array = Sprites.scenery_objects(current_room, home_project_state())
	var hover: Dictionary = {} if interaction_hover.blocked() else interaction_hover.target
	if hover.get("kind", "") == "exit": InteractionGlow.draw(canvas, hover.object)
	var visible_people: Array[Dictionary] = []
	for resident in colony.active_residents():
		if resident.get("room", "street") == current_room:
			var state: Dictionary = colony.daily_state(resident.id)
			draw_order.append({"resident": resident, "state": state, "y": resident_depth(resident, state)})
			visible_people.append(resident)
	draw_order.sort_custom(func(a, b): return float(a.y) < float(b.y))
	for entry in draw_order:
		if not entry.has("resident"):
			if not environment.draw_object(canvas, entry, pixel_font): Sprites.draw_object(canvas, entry, pixel_font)
			cafe_service.draw_on_table(canvas, entry)
			WorldLighting.draw_object_lights(canvas, entry, current_room, visual_minute())
			if not WorldLayout.is_outdoor(current_room) and entry.id == "window": WorldLighting.draw_window_view(canvas, entry, visual_minute())
			if hover.has("object") and hover.object.get("key", "") == entry.get("key", ""):
				InteractionGlow.draw(canvas, hover.object)
			continue
		var resident: Dictionary = entry.resident
		var state: Dictionary = entry.state
		var pos = position_of(resident).round()
		var target = Vector2(float(resident.target[0]), float(resident.target[1]))
		var walking = not paused and (pos.distance_to(target) > 2.0 or (resident.id == "player" and keyboard_walking))
		var direction: Vector2 = facing.get(resident.id, Vector2.DOWN)
		var phase: int = int(Time.get_ticks_msec() / 150) % 4
		var activity_phase: int = 0 if paused else int(Time.get_ticks_msec() / 450) % 4
		if hover.get("kind", "") == "resident" and hover.get("resident_id", "") == resident.id:
			# Draw in the same depth slot and native pose as the visible character.
			# Foreground props still cover the halo, just as they cover the sprite.
			if ActivityVisuals.is_bed_sleep(resident, state, current_room):
				InteractionGlow.draw_sleeping_head(canvas, resident.appearance, ActivityVisuals.sleep_layout(current_room).head.position)
			else:
				var pose: Dictionary = ActivityVisuals.active_pose(resident, state, pos, activity_phase, direction) if not walking else {}
				if pose.is_empty():
					InteractionGlow.draw_character(canvas, resident.appearance, pos, walking, phase, direction)
				else:
					InteractionGlow.draw_character_layers(canvas, ActivityVisuals.active_layers(resident.appearance, pose), pos)
		if ActivityVisuals.draw_sleeping(canvas, resident, state, current_room): continue
		if resident.id == "player" and seating.is_seated():
			Seats.draw_person(canvas, seating.active_seat(), resident.appearance)
			continue
		if resident.id == selected_id:
			canvas.draw_style_box(sprite_box("scroll_thumb"), Rect2(pos.x - 10, pos.y - 1, 20, 4))
		if resident.id == "player" and riding_bicycle and WorldLayout.is_outdoor(current_room):
			Art.draw_bicycle(canvas, pos, resident.appearance, walking, phase, direction)
		elif not walking and ActivityVisuals.draw_active(canvas, resident, state, pos, activity_phase, direction):
			pass
		else:
			Art.draw_person(canvas, pos, resident.appearance, 1, walking, phase, direction)

func ambient_suppressed() -> bool:
	return paused or _menu_suspended or colony.is_sleeping("player") or not chat_partner_id.is_empty() or is_instance_valid(help_panel) or is_instance_valid(door_panel) or is_instance_valid(learning.panel) or is_instance_valid(sleep_ui.panel)

func draw_world_labels(canvas: CanvasItem) -> void:
	if ambient_thoughts == null or ambient_suppressed(): return
	var visible_people: Array[Dictionary] = []
	for resident: Dictionary in colony.active_residents():
		if resident.get("room", "street") == current_room: visible_people.append(resident)
	var bounds := Rect2(Vector2(8, 8), layout_size() - Vector2(16, 16))
	var occupied: Array[Rect2] = []
	for surface: Control in [hud.stats_panel, hud.controls_panel, hud.dock_panel, inspector, overlay.toast, overlay.hint, cafe_service.panel, home_ui.location_panel, home_ui.reading_panel]:
		if surface.is_visible_in_tree(): occupied.append(surface.get_global_rect())
	for person: Dictionary in visible_people:
		var thought: Dictionary = encounters.visible_for(person.id)
		if thought.is_empty(): thought = ambient_thoughts.visible_for(person.id)
		if thought.is_empty(): continue
		var state: Dictionary = colony.daily_state(person.id)
		var world_anchor: Vector2 = ActivityVisuals.visual_anchor(person, state, current_room, position_of(person).round())
		var anchor: Vector2 = world_to_screen(world_anchor)
		anchor.y -= (12.0 if state.get("kind", "") == "sleeping" else 24.0) * maxf(0.0, world_scale - 1.0)
		var badge: Rect2 = ActivityVisuals.draw_thought(canvas, ui_font, person, thought, anchor, occupied, bounds)
		if badge.has_area():
			occupied.append(badge)

func decide_with_jev() -> void:
	if decision_pending or not dialogue_job.is_empty():
		return
	var npcs: Array = colony.active_residents(colony.player_autonomy)
	if npcs.is_empty(): return
	deciding_id = npcs[decision_index % npcs.size()].id
	decision_index += 1
	if colony.minute < int(decision_after.get(deciding_id, 0)):
		return
	if not colony.decision_due(deciding_id):
		return
	var actor: Dictionary = colony.get_resident(deciding_id)
	if actor.get("routine_place", "") == "descansar":
		return
	if position_of(actor).distance_to(Vector2(actor.target[0], actor.target[1])) > 3.0:
		return
	decision_after[deciding_id] = colony.minute + 30
	var payload = {"resident": colony.context_for(deciding_id), "allowed_actions": colony.allowed_actions_for(deciding_id)}
	var error = request.request(service_url + "/decide", service_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		last_provider = "JEV · no conectado"
		message("No fue posible contactar el servicio Jev. Puedes volver al modo local.")
		return
	decision_pending = true
	deciding_epoch = control_epoch
	last_provider = "JEV · consultando"

func _decision_received(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not decision_pending: return
	decision_pending = false
	if colony.is_sleeping(deciding_id) or colony.is_sleeping("player"): return
	if deciding_id == "player" and (not colony.player_autonomy or deciding_epoch != control_epoch): return
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		last_provider = "JEV · sin conexión / revisar servicio"
		use_jev = false
		message("Jev no está disponible. Se reactivó el modo local; configura backend/.")
		refresh_status()
		return
	var answer = JSON.parse_string(body.get_string_from_utf8())
	if not answer is Dictionary or not answer.get("action", null) is String:
		last_provider = "LOCAL · respuesta Jev inválida"
		use_jev = false
		refresh_status()
		return
	if not use_jev:
		return
	if not dialogue_job.is_empty() and deciding_id in [dialogue_job.a, dialogue_job.b]:
		return
	var applied = false
	if answer.action == "conversar":
		applied = begin_npc_dialogue(deciding_id)
	else:
		applied = colony.apply_decision(deciding_id, answer.action)
	last_provider = "JEV · " + str(answer.get("source", "sin origen")) + ("" if applied else " · acción no viable")
	refresh_status()

func service_headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + service_token])

func start_player_conversation(id: String) -> bool:
	if sync_exhaustion(): return false
	var started: bool = player_chat.start(id)
	if started: open_inspector(id, "hablar")
	return started

func end_player_conversation() -> void:
	player_chat.finish()

func close_chat_panel() -> void:
	player_chat.clear_prepared(selected_id)
	if selected_id == chat_partner_id: player_chat.finish()
	page = "historia"
	build_inspector()
	hide_inspector()

func return_to_conversation() -> void:
	if chat_partner_id.is_empty(): return
	open_inspector(chat_partner_id, "hablar")

func approach_chat(id: String) -> void:
	if sync_exhaustion(): return
	walk_to_mentor(id)
	player_chat.approach_id = id
	open_inspector(id, "hablar")

func chat_busy() -> bool:
	return player_chat.busy()

func chat_transcript_for(id: String) -> String:
	return player_chat.transcript(id)

func chat_suggestions_for(id: String) -> Array[Dictionary]:
	return player_chat.suggestions(id)

func chat_status_for(id: String) -> String:
	return player_chat.status(id)

func chat_error_for(id: String) -> String:
	return str(player_chat.errors.get(id, ""))

func send_chat_text(text: String) -> void:
	if sync_exhaustion(): return
	player_chat.send(text)

func send_player_dialogue() -> void:
	if is_instance_valid(chat_input): send_chat_text(chat_input.text)

func restore_chat_scroll(id: String, position: int, follow: bool) -> void:
	if page != "hablar" or selected_id != id or not is_instance_valid(chat_scroll): return
	chat_scroll.set_deferred("scroll_vertical", int(chat_scroll.get_v_scroll_bar().max_value) if follow else position)

func _chat_range_changed(id: String, scroll_id: int) -> void:
	if not is_instance_valid(chat_scroll) or chat_scroll.get_instance_id() != scroll_id: return
	restore_chat_scroll(id, int(player_chat.scroll_positions.get(id, 0)), bool(player_chat.scroll_follow.get(id, true)))

func complete_local_chat(serial: int, text: String) -> void:
	if dialogue_job.is_empty() or dialogue_job.get("serial", -1) != serial or not dialogue_job.get("manual_session", false): return
	var job: Dictionary = dialogue_job.duplicate(true)
	dialogue_job.clear()
	player_chat.completed(job, text, "Conversación local · respuesta predeterminada")
	refresh_status()

func begin_npc_dialogue(id: String) -> bool:
	if not colony.social_available(id) or (id == "player" and not colony.player_autonomy) or not dialogue_job.is_empty():
		return false
	var actor: Dictionary = colony.get_resident(id)
	var nearest = ""
	var distance = 45.0
	for other in colony.active_residents():
		if not colony.social_available(other.id) or other.id == id or (other.id == "player" and not colony.player_autonomy) or other.get("room", "street") != actor.get("room", "street"):
			continue
		var outgoing: Dictionary = colony.relationship_for(id, other.id)
		var incoming: Dictionary = colony.relationship_for(other.id, id)
		if [outgoing, incoming].any(func(relation): return relation.cooldown_until > colony.minute or relation.frustration >= 75 or relation.tolerance <= 12):
			continue
		var d = position_of(actor).distance_to(position_of(other))
		if not Navigation._clear_segment(position_of(actor),position_of(other),actor.room): continue
		if d < distance:
			distance = d
			nearest = other.id
	if nearest.is_empty():
		return false
	var acceptance: Dictionary = colony.social_start(nearest, id)
	if not acceptance.get("allowed", true): return false
	dialogue_serial += 1
	dialogue_job = {"a": id, "b": nearest, "first": "", "phase": "opening", "autonomous": true, "serial": dialogue_serial}
	# Preserve each speaker's actual task before reserving both for the exchange.
	dialogue_job["scenes"] = {id: colony.conversation_scene_for(id), nearest: colony.conversation_scene_for(nearest)}
	for scene: Dictionary in dialogue_job.scenes.values(): scene["paused_for_chat"] = true
	for participant: String in [id, nearest]:
		if participant not in colony.conversation_holds: colony.conversation_holds.append(participant)
	freeze_conversation()
	request_dialogue(id, nearest, "[Encuentro en la colonia: inicia una conversación breve sobre algo que realmente sabes. No atribuyas esta indicación al otro personaje.]")
	return true

func freeze_conversation() -> void:
	if dialogue_job.get("manual_session", false):
		player_chat.hold()
		return
	var goals: Dictionary = dialogue_job.get("goals", {})
	for id in [dialogue_job.a, dialogue_job.b]:
		var person: Dictionary = colony.get_resident(id)
		# A new routine may replace the destination while the conversation streams.
		if not goals.has(id) or person.target != person.pos or not str(person.get("travel_intent", "")).is_empty():
			goals[id] = {"target": person.target.duplicate(), "room": person.room, "intent": person.get("travel_intent", "")}
		person.target = person.pos.duplicate()
		person.travel_intent = ""
	dialogue_job["goals"] = goals

func release_conversation(resume_player: bool = true) -> void:
	if dialogue_job.get("autonomous", false):
		colony.social_finish(str(dialogue_job.get("a", "")), str(dialogue_job.get("b", "")))
		colony.conversation_holds.erase(str(dialogue_job.get("a", "")))
		colony.conversation_holds.erase(str(dialogue_job.get("b", "")))
	for id in dialogue_job.get("goals", {}):
		if id == "player" and not resume_player: continue
		var person: Dictionary = colony.get_resident(id)
		var goal: Dictionary = dialogue_job.goals[id]
		# An explicit order or room change takes precedence over the saved route.
		if person.room == goal.room and person.target == person.pos and str(person.get("travel_intent", "")).is_empty():
			person.target = goal.target.duplicate()
			person.travel_intent = goal.intent
			paths.erase(id)

func request_dialogue(resident_id: String, speaker_id: String, utterance: String) -> void:
	if dialogue_job.is_empty(): return
	if dialogue_job.get("autonomous", false) and dialogue_job.phase == "reply":
		var social: Dictionary = colony.social_turn(resident_id, speaker_id, utterance, 0)
		var local_text: String = str(social.get("reply", ""))
		if local_text.is_empty() and colony.social_dialogue.requires_local_reply(resident_id,speaker_id,utterance): local_text = colony.social_dialogue.reply(resident_id,speaker_id,utterance)
		if local_text.is_empty() and player_chat._departure(utterance): local_text = "Claro. Nos vemos luego."
		if not local_text.is_empty():
			dialogue_job["local_social"] = true
			dialogue_job["social_end"] = bool(social.get("end", false))
			dialogue_job["social_reason"] = str(social.get("reason", ""))
			call_deferred("_complete_social_dialogue", int(dialogue_job.serial), local_text)
			return
	var speaker: Dictionary = colony.get_resident(speaker_id)
	var scene: Dictionary = player_chat.scene_for(resident_id) if dialogue_job.get("manual_session", false) else dialogue_job.get("scenes", {}).get(resident_id, {})
	if not scene.is_empty() and dialogue_job.get("autonomous", false):
		scene = scene.duplicate(true)
		var current: Dictionary = colony.conversation_scene_for(resident_id)
		scene.next_plan = current.next_plan
		scene.routine = current.routine
	var payload = {"resident": colony.context_for(resident_id, speaker_id, utterance, scene), "speaker": {"id": speaker_id, "name": speaker.name}, "utterance": utterance.left(1200)}
	if dialogue_job.get("manual_session", false):
		payload["suggest_replies"] = true
		var inventory: Dictionary = colony.progression_state().get("inventory", {})
		# Facts are offered only as literal player replies, not as the neighbor's knowledge.
		payload["reply_facts"] = [
			"Ya tengo el aceite." if int(inventory.get("aceite", 0)) > 0 else "Aún no tengo aceite.",
			"Ya tengo las semillas." if int(inventory.get("semillas", 0)) > 0 else "Aún no tengo semillas."
		]
	stream_prefix = (speaker.name + ": " + utterance + "\n\n" if dialogue_job.phase == "reply" else "") + colony.get_resident(resident_id).name + ": "
	stream_text = ""
	var error: Error = dialogue_request.start(service_url + "/dialogue/stream", service_headers(), payload)
	if error != OK:
		_dialogue_failed("No se pudo conectar con el servicio de conversación.")

func _complete_social_dialogue(serial: int, text: String) -> void:
	if dialogue_job.is_empty() or dialogue_job.get("serial", -1) != serial: return
	_dialogue_completed({"text": text, "source": "local_social"})

func _dialogue_delta(text: String) -> void:
	if dialogue_job.is_empty(): return
	stream_text += text
	dialogue_text = stream_prefix + player_chat.compact_reply(stream_text)
	if is_instance_valid(chat_output) and page == "hablar" and selected_id == dialogue_job.b and dialogue_job.a == "player":
		var bar = chat_scroll.get_v_scroll_bar()
		var follow: bool = bar.value >= bar.max_value - bar.page - 4
		player_chat.scroll_follow[selected_id] = follow
		player_chat.scroll_positions[selected_id] = chat_scroll.scroll_vertical
		resident_ui.update_chat_stream(selected_id)
		if follow: restore_chat_scroll.call_deferred(selected_id, 0, true)

func _dialogue_failed(reason: String) -> void:
	if dialogue_job.is_empty(): return
	if dialogue_job.get("manual_session", false):
		var job: Dictionary = dialogue_job.duplicate(true)
		dialogue_job.clear()
		player_chat.failed(job, reason)
		return
	release_conversation()
	dialogue_job.clear()
	dialogue_text = reason + "\nLa conversación incompleta no se guardó."
	if page == "hablar": build_inspector()
	message("No se pudo completar la conversación de IA.")

func _dialogue_completed(data: Dictionary) -> void:
	if dialogue_job.is_empty():
		return
	if dialogue_job.get("autonomous", false) and "player" in [dialogue_job.a, dialogue_job.b] and not colony.player_autonomy:
		cancel_player_ai()
		return
	if not data.get("text") is String or data.text.strip_edges().is_empty():
		_dialogue_failed("No llegó una respuesta completa.")
		return
	var reply: String = player_chat.compact_reply(data.text)
	last_timing = "Inicio %.2fs · total %.2fs" % [float(dialogue_request.metrics.get("ttft_ms", 0)) / 1000.0, float(dialogue_request.metrics.get("total_ms", 0)) / 1000.0]
	if dialogue_job.phase == "opening":
		dialogue_job.first = reply
		dialogue_job.phase = "reply"
		call_deferred("continue_npc_dialogue", dialogue_job.get("serial", -1))
		return
	var job = dialogue_job.duplicate(true)
	if job.get("manual_session", false):
		dialogue_job.clear()
		player_chat.completed(job, reply, "OpenAI", data.get("suggestions", []) if data.get("suggestions", []) is Array else [])
		refresh_status()
		return
	release_conversation()
	dialogue_job.clear()
	if colony.record_dialogue(job.a, job.b, job.first, reply, "Conversación mixta" if job.get("local_social", false) else "OpenAI"):
		dialogue_text = colony.get_resident(job.a).name + ": " + job.first + "\n" + colony.get_resident(job.b).name + ": " + reply
		for pair in [[job.a, job.b, job.first], [job.b, job.a, reply]]:
			var leaves: bool = player_chat._departure(str(pair[2])) or pair[0] == job.b and job.get("social_end", false)
			colony.social_finish(pair[0], pair[1], not leaves)
			if leaves: encounters.let_leave(pair[0], pair[1])
	else:
		dialogue_text = "La conversación se interrumpió: los personajes se alejaron."
	if page == "hablar": build_inspector()
	refresh_status()

# A manual takeover may occur between the opening stream and its deferred reply.
func continue_npc_dialogue(serial: int) -> void:
	if dialogue_job.is_empty() or dialogue_job.get("serial", -1) != serial: return
	request_dialogue(dialogue_job.b, dialogue_job.a, dialogue_job.first)
