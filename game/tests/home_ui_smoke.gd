extends SceneTree
## Home presentation through real input and movement, without saves or providers.
const Layout = preload("res://scripts/world_layout.gd")
const Targets = preload("res://scripts/world_interactions.gd")
const Navigation = preload("res://scripts/navigation.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	var menu_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var samples := 0
var invalid_samples := 0
var save_path := "user://unused_home_ui_%d.json" % OS.get_process_id()

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func settle() -> void:
	for _frame in range(4): await process_frame

func tap(viewport: SubViewport, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)

func click(viewport: SubViewport, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	viewport.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)

func position(scene, point: Vector2, room: String) -> void:
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = room
	player.pos = [point.x,point.y]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	scene.paths.erase("player")
	scene.update_room()

func fixture(viewport: SubViewport, room: String) -> MainProbe:
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
	scene.menu_requested.connect(func(): scene.menu_calls += 1)
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = Layout.data().home_rest.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	position(scene,Layout.point(Layout.data().entry),room)
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	return scene

func object_target(scene, room: String) -> Dictionary:
	# Household lore now shares the same physical props with contextual controls.
	# Select that real prop first; the remaining legacy item path still covers
	# the original reader when a prop has no contextual action.
	var prop_key: String = "photo" if room == "player" else "project"
	for target: Dictionary in Targets._targets(room,scene.home_project_state()):
		if target.get("item", {}).get("prop_key", "") == prop_key: return target
	var key: String = room+":item:"+("postcard" if room == "player" else "project")
	for target: Dictionary in Targets._targets(room,scene.home_project_state()):
		if target.key == key: return target
	return {}

func walk(scene) -> void:
	var player: Dictionary = scene.colony.get_resident("player")
	for _frame in range(700):
		scene.move_resident(player,1.0/30.0)
		scene.resolve_player_arrival()
		scene.update_room()
		samples += 1
		if not Navigation.is_walkable(scene.position_of(player),player.room): invalid_samples += 1
		if scene.pending_item.is_empty() and not scene.pending_exit: break

func known_item(target: Dictionary, room: String) -> Dictionary:
	var item: Dictionary = target.item.duplicate(true)
	item.room = room
	return item

func house_case(viewport: SubViewport, room: String) -> void:
	var scene := fixture(viewport,room)
	await settle()
	var label := "%dx%d %s: " % [viewport.size.x,viewport.size.y,room]
	var extent := Rect2(Vector2.ZERO,Vector2(viewport.size))
	var location: Rect2 = scene.home_ui.location_panel.get_global_rect()
	expect(scene.preview_mode and not scene.save_allowed and scene.home_ui.location_panel.is_visible_in_tree(),label+"isolated interior shows its location and exit")
	expect(scene.room_label.text == ("Tu casa" if room == "player" else "Casa de "+str(scene.colony.get_resident(room).name)),label+"location names the actual current house")
	expect(extent.encloses(location) and not location.intersects(scene.hud.stats_panel.get_global_rect()) and not location.intersects(scene.hud.controls_panel.get_global_rect()),label+"location fits between visible HUD groups")
	expect(scene.exit_button.is_visible_in_tree() and scene.exit_button.focus_mode == Control.FOCUS_ALL and not scene.exit_button.accessibility_name.is_empty(),label+"exit remains named and keyboard accessible")
	var player: Dictionary = scene.colony.get_resident("player")
	var origin: Array = player.pos.duplicate()
	click(viewport,location.position+Vector2(20,20))
	expect(player.target == origin and player.pos == origin,label+"clicking the location card never sends a world route")
	var target: Dictionary = object_target(scene,room)
	if target.is_empty():
		expect(false,label+"real object target exists")
		scene.free()
		return
	var count: int = player.memories.size()
	click(viewport,scene.world_to_screen(target.rect.get_center()))
	expect(not scene.pending_item.is_empty() and not scene.home_ui.is_reading() and player.memories.size() == count,label+"remote click schedules approach without reading or recording a discovery")
	walk(scene)
	await settle()
	expect(scene.home_ui.is_reading() and scene.position_of(player).distance_to(target.item.stand_at) < 5,label+"physical arrival opens the object's reader")
	expect(scene.home_ui.reading_title.text == target.item.title and scene.home_ui.reading_body.text == str(target.item.text).strip_edges(),label+"reader keeps the complete original title and text")
	expect(player.memories.size() == count+1 and player.memories[-1].kind == "objeto",label+"only arrival adds the personal object discovery")
	expect(not scene.paused and not scene.keyboard_blocked() and scene.home_ui.close_button.has_focus(),label+"reading is nonmodal and opens with an accessible close action")
	var minute: int = scene.colony.minute
	for _frame in range(41): scene._process(0.1)
	expect(scene.colony.minute > minute and scene.home_ui.is_reading(),label+"the world clock continues during reading")
	var unchanged: Array = player.target.duplicate()
	click(viewport,scene.home_ui.reading_scroll.get_global_rect().get_center())
	expect(player.target == unchanged and scene.home_ui.is_reading(),label+"clicking the reading text cannot move the player behind it")
	tap(viewport,KEY_ESCAPE)
	expect(not scene.home_ui.is_reading() and scene.menu_calls == 0,label+"Escape closes reading before requesting the menu")
	var item: Dictionary = known_item(target,room)
	scene.home_ui.show_item(item)
	tap(viewport,KEY_ENTER)
	expect(not scene.home_ui.is_reading(),label+"Enter activates the focused close button")
	# Keyboard interaction uses the same physical object; it never reads remotely.
	position(scene,target.item.stand_at,room)
	count = player.memories.size()
	tap(viewport,KEY_E)
	expect(not scene.pending_item.is_empty() and not scene.home_ui.is_reading() and player.memories.size() == count,label+"E selects the nearby object before arrival processing")
	scene.resolve_player_arrival()
	expect(scene.home_ui.is_reading() and scene.home_ui.reading_body.text == str(target.item.text).strip_edges(),label+"E arrives at the same complete description as pointer input")
	tap(viewport,KEY_D)
	expect(not scene.home_ui.is_reading(),label+"taking manual movement control closes the reader")
	scene.home_ui.show_item(item)
	scene.open_inspector("player","historia")
	expect(not scene.home_ui.is_reading() and scene.inspector.visible,label+"opening a profile releases the reading area")
	scene.hide_inspector()
	scene.home_ui.show_item(item)
	scene.learning.show_journal()
	expect(not scene.home_ui.is_reading() and is_instance_valid(scene.learning.panel),label+"a learning modal replaces the reader")
	scene.learning.close()
	scene.home_ui.show_item(item)
	scene.exit_button.grab_focus()
	tap(viewport,KEY_ENTER)
	expect(scene.pending_exit and not scene.home_ui.is_reading() and player.room == room,label+"keyboard exit closes reading and starts a route, without teleporting")
	walk(scene)
	expect(player.room == Layout.home_area(room) and scene.current_room == Layout.home_area(room) and scene.position_of(player).distance_to(Layout.door_positions()[room]) < 5,label+"exit reaches the portal and the matching street door")
	expect(scene.home_ui.location_panel.visible and scene.room_label.text == Layout.area_title(Layout.home_area(room)) and scene.exit_button.text == "M" and not scene.home_ui.is_reading(),label+"house exit changes to the area name and map shortcut")
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not FileAccess.file_exists(save_path),label+"interaction created no provider work or persisted save")
	scene.free()
	await process_frame

func reading_and_own_actions(viewport: SubViewport) -> void:
	viewport.size = Vector2i(768,432)
	var scene := fixture(viewport,"player")
	await settle()
	var item := {"room":"player","title":"Un cuaderno de recuerdos de la colonia", "text":"Íñigo escribió: ¿Qué aprendimos ayer? María señaló el jardín, la tetera y las pequeñas historias del barrio.\n".repeat(18).strip_edges()}
	var baseline: String = JSON.stringify(scene.colony.residents)
	scene.home_ui.show_item(item)
	await settle()
	var reader: Panel = scene.home_ui.reading_panel
	var scroll: ScrollContainer = scene.home_ui.reading_scroll
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	expect(scene.home_ui.reading_body.text == item.text and bar.max_value > bar.page and bar.is_visible_in_tree() and bar.size.x >= 6,"long accented descriptions remain intact with a usable scrollbar")
	scroll.scroll_vertical = int(bar.max_value)
	await settle()
	var offset: int = scroll.scroll_vertical
	var reader_id: int = reader.get_instance_id()
	viewport.size = Vector2i(960,540)
	await settle()
	expect(scene.home_ui.is_reading() and reader.get_instance_id() == reader_id and scroll.scroll_vertical == offset and scene.home_ui.reading_body.text == item.text,"resizing retains the same reading card, full text and scroll position")
	var extent := Rect2(Vector2.ZERO,Vector2(viewport.size))
	expect(extent.encloses(reader.get_global_rect()) and reader.get_global_rect().encloses(scroll.get_global_rect()) and reader.get_global_rect().encloses(scene.home_ui.close_button.get_global_rect()),"reader, close button and scroll stay inside their viewport after resize")
	expect(JSON.stringify(scene.colony.residents) == baseline,"presenting, scrolling and resizing a known description do not create memories or alter residents")
	scene.home_ui.close()
	position(scene,Layout.stand_at("bed","player"),"player")
	tap(viewport,KEY_E)
	scene.resolve_player_arrival()
	expect(is_instance_valid(scene.sleep_ui.panel) and not scene.home_ui.is_reading(),"the player's bed still opens sleep choices instead of an object reader")
	scene.sleep_ui.close()
	position(scene,Layout.stand_at("bicycle","player"),"player")
	tap(viewport,KEY_E)
	scene.resolve_player_arrival()
	expect(is_instance_valid(scene.learning.panel) and not scene.home_ui.is_reading(),"the player's work station still opens its real learning procedure")
	scene.learning.close()
	scene.home_ui.show_item(item)
	position(scene,Layout.point(Layout.data().entry),"cesar")
	expect(not scene.home_ui.is_reading() and scene.room_label.text == "Casa de César","changing rooms closes stale content and updates the current house")
	scene.free()
	await process_frame

func pending_arrival_preserves_journal(viewport: SubViewport) -> void:
	viewport.size = Vector2i(768,432)
	var scene := fixture(viewport,"cesar")
	await settle()
	var player: Dictionary = scene.colony.get_resident("player")
	var target := object_target(scene,"cesar")
	var count: int = player.memories.size()
	click(viewport,scene.world_to_screen(target.rect.get_center()))
	scene.learning.show_journal()
	await settle()
	var panel: Panel = scene.learning.panel
	var focus: Control = viewport.gui_get_focus_owner()
	expect(not scene.pending_item.is_empty() and is_instance_valid(focus) and panel.is_ancestor_of(focus),"an object approach can remain pending while the journal owns keyboard focus")
	walk(scene)
	await settle()
	expect(scene.pending_item.is_empty() and player.memories.size() == count+1 and player.memories[-1].kind == "objeto","arrival behind the journal records one physical discovery")
	expect(is_instance_valid(panel) and panel.is_visible_in_tree() and scene.learning.panel == panel and viewport.gui_get_focus_owner() == focus and not scene.home_ui.is_reading(),"arrival preserves the newer journal and its focus instead of opening a reader")
	scene.resolve_player_arrival()
	expect(player.memories.size() == count+1,"rechecking arrival cannot record the same pending discovery twice")
	scene.free()
	await process_frame

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; normal progress must remain untouched.")
		quit(1)
		return
	var viewport := SubViewport.new()
	root.add_child(viewport)
	for size: Vector2i in [Vector2i(768,432),Vector2i(960,540)]:
		viewport.size = size
		for room: String in ["cesar","player"]: await house_case(viewport,room)
	await reading_and_own_actions(viewport)
	await pending_arrival_preserves_journal(viewport)
	expect(invalid_samples == 0,"all %d movement samples remain on walkable world coordinates" % samples)
	expect(not FileAccess.file_exists(save_path),"the entire fixture leaves isolated save persistence absent")
	viewport.free()
	await process_frame
	print("HOME UI: %d/%d checks passed; %d movement samples" % [checks-failures.size(),checks,samples])
	quit(0 if failures.is_empty() else 1)
