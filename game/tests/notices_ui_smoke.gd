extends SceneTree
## Real notification input and layout, isolated from saves and providers.
## --headless --script res://tests/notices_ui_smoke.gd -- --ui-test
## Add --capture with a graphical renderer to save the same states as PNG.
const Layout = preload("res://scripts/world_layout.gd")
const SHORT_TEXT := "Guardaste tu progreso. Puedes seguir explorando la colonia."
var long_text :=  "María dejó una nota junto al jardín: las semillas necesitan agua y un lugar con luz. Puedes revisar tus materiales en el Diario y entregar lo que reuniste cuando encuentres a tu mentor.\n\n".repeat(5) + "Última línea: ¿Qué detalle encontraste hoy? Aquí termina el aviso completo."

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var captured := 0
var capture_enabled := false
var save_path := "user://unused_notices_ui_%d.json" % OS.get_process_id()
var directory := ""

func _initialize() -> void: call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in range(5): await process_frame

func pointer(viewport: SubViewport, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	viewport.push_input(event,true)

func mouse(viewport: SubViewport, point: Vector2, button: MouseButton) -> void:
	pointer(viewport,point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	viewport.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)

func key(viewport: SubViewport, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)

func fixture(viewport: SubViewport) -> MainProbe:
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = save_path
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	scene.controls_active = true
	scene.paused = true
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = Layout.data().home_rest.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = "street"
	player.pos = [264.0,180.0]
	player.target = player.pos.duplicate()
	scene.update_room()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	return scene

func capture(viewport: SubViewport, name: String) -> void:
	if not capture_enabled: return
	await settle()
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var okay: bool = picture != null and not picture.is_empty() and picture.get_size() == viewport.size and picture.save_png(directory.path_join(name+".png")) == OK
	if not okay:
		failures.append("Could not capture " + name)
		push_error("Could not capture " + name)
	else:
		captured += 1
		print("CAPTURE: " + directory.path_join(name+".png"))

func no_overlap(scene, viewport: SubViewport, description: String) -> void:
	var rect: Rect2 = scene.overlay.toast.get_global_rect()
	var okay: bool = Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(rect)
	var obstacles: Array[Control] = [scene.hud.dock_panel,scene.hud.stats_panel,scene.hud.controls_panel,scene.inspector]
	if is_instance_valid(scene.sleep_ui.banner): obstacles.append(scene.sleep_ui.banner)
	for control: Control in obstacles:
		if control.is_visible_in_tree() and rect.intersects(control.get_global_rect()): okay = false
	expect(okay,description)

func text_and_input(scene: MainProbe, viewport: SubViewport) -> void:
	var prefix := "%dx%d: " % [viewport.size.x,viewport.size.y]
	scene.message(SHORT_TEXT)
	await settle()
	var toast: Panel = scene.overlay.toast
	var close_button: Button = toast.get_node("DismissToast")
	expect(scene.preview_mode and not scene.save_allowed and toast.is_visible_in_tree(),prefix+"a direct notice opens in an isolated world")
	expect(scene.log_label.text == SHORT_TEXT and scene.log_label.get_theme_font_size("font_size") < 16,prefix+"the complete short message uses smaller type than body controls")
	var bounds: Rect2 = toast.get_global_rect()
	expect(absf(bounds.end.x-(viewport.size.x-12)) <= 2 and bounds.position.y > viewport.size.y/2.0,prefix+"normal notice stays at the lower right")
	no_overlap(scene,viewport,prefix+"notice fits without covering the dock or other controls")
	await capture(viewport,"%dx%d-short" % [viewport.size.x,viewport.size.y])
	pointer(viewport,Vector2.ZERO)
	viewport.gui_release_focus()
	scene.overlay.toast_until = 1
	scene.overlay.refresh()
	expect(not toast.visible,prefix+"a short notice expires after the user leaves it")
	scene.message(long_text)
	await settle()
	var scroll: ScrollContainer = scene.msg_scroll
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	expect(scene.log_label.text == long_text and bar.max_value > bar.page and bar.is_visible_in_tree() and bar.size.x >= 6,prefix+"long text remains intact with a visible usable scrollbar")
	expect(scroll.focus_mode != Control.FOCUS_NONE or bar.focus_mode != Control.FOCUS_NONE,prefix+"scrolling also has a keyboard focus target")
	no_overlap(scene,viewport,prefix+"the expanded notice remains clear of dock and controls")
	await capture(viewport,"%dx%d-long" % [viewport.size.x,viewport.size.y])
	var baseline: String = JSON.stringify(scene.colony.residents)
	var point: Vector2 = scroll.get_global_rect().get_center()
	mouse(viewport,point,MOUSE_BUTTON_LEFT)
	for _step in range(3): mouse(viewport,point,MOUSE_BUTTON_WHEEL_DOWN)
	await settle()
	expect(scroll.scroll_vertical > 0,prefix+"real mouse wheel input reveals more of the message")
	expect(JSON.stringify(scene.colony.residents) == baseline and scene.pending_item.is_empty() and scene.pending_home.is_empty() and not scene.pending_exit and scene.interaction_hover.target.is_empty(),prefix+"clicks and wheel over text cannot route or interact with the world")
	pointer(viewport,Vector2.ZERO)
	viewport.gui_release_focus()
	scene.overlay.toast_until = 1
	scene.overlay.refresh()
	expect(toast.visible,prefix+"an unread long message does not vanish on the short-message deadline")
	scroll.scroll_vertical = int(bar.max_value)
	await settle()
	expect(scroll.scroll_vertical >= bar.max_value-bar.page-1 and scene.log_label.get_global_rect().end.y <= scroll.get_global_rect().end.y+1,prefix+"the scrollbar can expose the final line without truncation")
	close_button.grab_focus()
	key(viewport,KEY_ENTER)
	expect(not toast.visible,prefix+"the focused close action can dismiss a long message with Enter")

func lifecycle_and_resize(scene: MainProbe, viewport: SubViewport) -> void:
	scene.message("Un aviso que estás leyendo con el puntero.")
	await settle()
	pointer(viewport,scene.msg_scroll.get_global_rect().get_center())
	scene.overlay.toast_until = 1
	scene.overlay.refresh()
	expect(scene.overlay.toast.visible,"hover preserves a short notice while it is being read")
	pointer(viewport,Vector2.ZERO)
	var close_button: Button = scene.overlay.toast.get_node("DismissToast")
	close_button.grab_focus()
	scene.overlay.toast_until = 1
	scene.overlay.refresh()
	expect(scene.overlay.toast.visible,"keyboard focus preserves the notice until the user finishes")
	viewport.gui_release_focus()
	scene.overlay.toast_until = 1
	scene.overlay.refresh()
	expect(not scene.overlay.toast.visible,"the short notice may expire once hover and keyboard focus leave")
	scene.message(long_text)
	await settle()
	var scroll: ScrollContainer = scene.msg_scroll
	var baseline: String = JSON.stringify(scene.colony.residents)
	scroll.grab_focus()
	key(viewport,KEY_DOWN)
	await settle()
	expect(scroll.scroll_vertical > 0 and JSON.stringify(scene.colony.residents) == baseline,"Down scrolls focused notice text without moving the player")
	key(viewport,KEY_ESCAPE)
	expect(not scene.overlay.toast.visible and not scene.keyboard_blocked(),"Escape closes focused reading and restores normal game controls")
	scene.message(long_text)
	await settle()
	expect(scene.overlay.toast.visible and scroll.scroll_vertical == 0,"a repeated notice can reopen from its beginning after dismissal")
	scroll.scroll_vertical = 70
	await settle()
	var scroll_id: int = scroll.get_instance_id()
	var offset: int = scroll.scroll_vertical
	viewport.size = Vector2i(960,540)
	await settle()
	expect(scene.overlay.toast.visible and scroll.get_instance_id() == scroll_id and scroll.scroll_vertical == offset and scene.log_label.text == long_text,"resizing retains the notice, its complete text and reading position")
	no_overlap(scene,viewport,"resized notice still fits without overlapping controls")
	await capture(viewport,"960x540-resized-reading")
	scene.open_inspector("cesar","historia")
	await settle()
	no_overlap(scene,viewport,"an open NPC profile and the message remain separately usable")
	scene.hide_inspector()
	var player: Dictionary = scene.colony.get_resident("player")
	var bed: Vector2 = Layout.stand_at("bed","player")
	player.room = "player"
	player.pos = [bed.x,bed.y]
	player.target = player.pos.duplicate()
	player.energy = 40.0
	scene.update_room()
	var sleeping: bool = scene.sleep_ui.start(480)
	scene.set_process(false)
	scene.message(long_text)
	await settle()
	expect(sleeping and scene.colony.is_sleeping("player") and is_instance_valid(scene.sleep_ui.banner),"the overlap fixture uses real stationary bed rest")
	no_overlap(scene,viewport,"the long message avoids the active sleep banner and interior dock")
	viewport.size = Vector2i(768,432)
	await settle()
	scene.open_inspector("cesar","historia")
	await settle()
	no_overlap(scene,viewport,"compact viewport keeps sleep, NPC profile, dock and notice clear")
	await capture(viewport,"768x432-rest-and-profile")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ui-test" not in args:
		push_error("Requires -- --ui-test; normal progress must remain untouched.")
		quit(1)
		return
	capture_enabled = "--capture" in args
	if capture_enabled and DisplayServer.get_name() == "headless":
		push_error("Captures require a graphical renderer.")
		quit(1)
		return
	directory = ProjectSettings.globalize_path("res://../artifacts/notices-ui")
	if capture_enabled: DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for size: Vector2i in [Vector2i(960,540),Vector2i(768,432)]:
		viewport.size = size
		var scene := fixture(viewport)
		await settle()
		await text_and_input(scene,viewport)
		if size.x == 768: await lifecycle_and_resize(scene,viewport)
		expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not FileAccess.file_exists(save_path),"notice operations create no provider job or persisted progress")
		scene.free()
		await process_frame
	viewport.free()
	await process_frame
	print("NOTICES UI: %d/%d checks passed; %d captures" % [checks-failures.size(),checks,captured])
	quit(0 if failures.is_empty() else 1)
