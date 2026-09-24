extends SceneTree
## Real household actions, page-specific memories and input, with no providers/save.
const Details = preload("res://scripts/home_details.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Targets = preload("res://scripts/world_interactions.gd")
const Navigation = preload("res://scripts/navigation.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var save_path := "user://unused_home_details_%d.json" % OS.get_process_id()

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func settle() -> void:
	for _frame in range(5): await process_frame

func position(scene: MainProbe, room: String, point: Vector2) -> void:
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = room
	player.pos = [point.x, point.y]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	scene.paths.clear()
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
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = Layout.data().home_rest.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	position(scene, room, Layout.point(Layout.data().entry))
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	return scene

func tap(viewport: SubViewport, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event, true)

func target_for(scene: MainProbe, key: String) -> Dictionary:
	for target: Dictionary in Targets._targets(scene.current_room, scene.home_project_state()):
		if str(target.get("item", {}).get("prop_key", "")) == key: return target
	return {}

func approach(scene: MainProbe, target: Dictionary) -> void:
	scene.activate_world_interaction(target)
	var player: Dictionary = scene.colony.get_resident("player")
	for _frame in range(900):
		scene.move_resident(player, 1.0 / 30.0)
		scene.resolve_player_arrival()
		if scene.pending_item.is_empty(): break

func action_button(scene: MainProbe, id: String) -> Button:
	for child: Node in scene.home_ui.actions_row.get_children():
		if child is Button and child.get_meta("house_action", "") == id: return child
	return null

func catalog_checks() -> void:
	var profiles: Dictionary = Details.profiles()
	for room: String in Details.HOMES:
		var pages: Array = profiles[room].pages
		expect(pages.size() in [2, 3], room + ": a small authored album has two or three pages")
		var texts := {}
		var assets_valid := true
		for page: Dictionary in pages:
			texts[page.text] = true
			for part: Dictionary in page.scene:
				assets_valid = assets_valid and not Sprites.frame_info(str(part.asset)).is_empty()
		expect(texts.size() == pages.size() and assets_valid, room + ": distinct page text and existing native sprite vignettes")
		for prop: Dictionary in Layout.props(room):
			if prop.key == "bed" or (room == "player" and prop.key in ["cabinet", "project", "storage", "table", "tea"]):
				expect(Details.for_object(prop, room).is_empty(), room + ": original route stays authoritative for " + str(prop.key))
	profiles.alma.pages[0].text = "CHANGED"
	expect(Details.profiles().alma.pages[0].text != "CHANGED", "callers cannot mutate the shared authored page catalog")
	expect(Details.page_for("alma", "storage", "secret").is_empty(), "unlisted private pages cannot be resolved")

func album_case(viewport: SubViewport) -> void:
	var scene := fixture(viewport, "alma")
	await settle()
	var player: Dictionary = scene.colony.get_resident("player")
	var target: Dictionary = target_for(scene, "storage")
	expect(not target.is_empty(), "Alma's real bookshelf exposes the album")
	if target.is_empty():
		scene.free()
		return
	var original_memories: int = player.memories.size()
	scene.activate_world_interaction(target)
	expect(not scene.home_ui.is_reading() and player.memories.size() == original_memories, "a distant album click does not show or remember its contents")
	approach(scene, target)
	await settle()
	expect(scene.home_ui.is_reading() and scene.home_ui.page_index == -1 and scene.position_of(player).distance_to(target.item.stand_at) < 5, "arrival opens the compact album cover at its physical stand")
	var before_page: int = player.memories.size()
	var album: Button = action_button(scene, "album")
	expect(is_instance_valid(album) and album.focus_mode == Control.FOCUS_ALL and not album.accessibility_name.is_empty(), "the album action has a visible named keyboard control")
	if not is_instance_valid(album):
		scene.free()
		return
	album.grab_focus()
	tap(viewport, KEY_ENTER)
	await settle()
	var page: Dictionary = Details.profiles().alma.pages[0]
	expect(scene.home_ui.page_index == 0 and scene.home_ui.reading_body.text == page.text and scene.home_ui.vignette.visible, "Enter opens the first real page and its sprite vignette")
	expect(player.memories.size() == before_page + 1 and str(player.memories[-1].content).contains(str(page.text)), "only the page actually read becomes a personal memory")
	var first_text: String = scene.home_ui.reading_body.text
	tap(viewport, KEY_ENTER)
	await settle()
	expect(scene.home_ui.page_index == 1 and scene.home_ui.reading_body.text != first_text and player.memories.size() == before_page + 2, "the focused next action changes both the page and the observed memory")
	await capture(viewport, "alma-page2-768")
	var held: Array = player.pos.duplicate()
	var held_target: Array = player.target.duplicate()
	tap(viewport, KEY_LEFT)
	scene._process(0.05)
	await settle()
	# The last subpixel of the previous approach may settle; arrow input must not
	# issue a new target or move beyond the world's one-pixel stationary tolerance.
	expect(scene.home_ui.page_index == 0 and player.memories.size() == before_page + 2 and player.target == held_target and scene.position_of(player).distance_to(Layout.point(held)) <= 1.0, "the left arrow rereads a page without issuing movement or duplicating a memory")
	var panel: Panel = scene.home_ui.reading_panel
	var fits := true
	for child: Node in scene.home_ui.actions_row.get_children():
		if child is Control: fits = fits and panel.get_global_rect().encloses(child.get_global_rect())
	expect(fits and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(panel.get_global_rect()), "page controls remain visible inside the compact reader")
	viewport.size = Vector2i(960, 540)
	await settle()
	expect(scene.home_ui.page_index == 0 and scene.home_ui.reading_body.text == first_text and panel.get_global_rect().encloses(scene.home_ui.actions_row.get_global_rect()), "resize preserves the active page and its controls")
	await capture(viewport, "alma-album-960")
	viewport.size = Vector2i(768, 432)
	await settle()
	await capture(viewport, "alma-album-768")
	scene.home_ui.turn_page(1)
	scene.home_ui.turn_page(1)
	await settle()
	expect(scene.home_ui.page_index == 2 and scene.home_ui.next_button.disabled and not scene.home_ui.previous_button.disabled, "the final authored page stops forward navigation and keeps a way back")
	await capture(viewport, "alma-page3-768")
	tap(viewport, KEY_ESCAPE)
	expect(not scene.home_ui.is_reading(), "Escape closes the album before opening a menu")
	expect(scene.provider_calls == 0 and not FileAccess.file_exists(save_path), "the album uses no provider and does not save the fixture")
	scene.free()
	await process_frame

func household_case(viewport: SubViewport) -> void:
	var scene := fixture(viewport, "player")
	await settle()
	var player: Dictionary = scene.colony.get_resident("player")
	for key: String in ["window", "window_work", "plant"]:
		var target := target_for(scene, key)
		expect(not target.is_empty(), "real household object is targetable: " + key)
		if target.is_empty(): continue
		approach(scene, target)
		await settle()
		expect(scene.home_ui.is_reading() and Navigation.is_walkable(scene.position_of(player), "player"), key + ": arrival reaches a walkable stand and opens its action")
		var action: String = "water" if key == "plant" else "curtains"
		var button: Button = action_button(scene, action)
		expect(is_instance_valid(button), key + ": contextual action exists")
		if not is_instance_valid(button): continue
		var beam_before := Color.TRANSPARENT
		var beam_pixel := Vector2i.ZERO
		if action == "curtains" and "--capture" in OS.get_cmdline_user_args():
			# Sample below the window PNG, inside its daylight polygon. The scene's
			# process is disabled, so this detects a stale cached lighting draw.
			beam_pixel = Vector2i(scene.world_to_screen(target.item.rect.position + Vector2(26,55)))
			await RenderingServer.frame_post_draw
			beam_before = viewport.get_texture().get_image().get_pixelv(beam_pixel)
		button.grab_focus()
		tap(viewport, KEY_ENTER)
		await settle()
		var state: Dictionary = scene.colony.environment.view().households.player
		if action == "curtains":
			expect(bool(state.curtains.get(key, false)) and action_button(scene, action).text == "Abrir cortinas", key + ": the real curtain changes and the next action matches it")
			if key == "window": expect(not state.curtains.get("window_work", false), "closing one window does not close the other")
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var beam_after: Color = viewport.get_texture().get_image().get_pixelv(beam_pixel)
				expect(beam_before.get_luminance() > beam_after.get_luminance() + 0.002, key + ": closing the curtain removes its daylight immediately without a simulation frame")
		else:
			expect(state.watered.has(key), "watering records the actual plant")
			var snapshot: String = JSON.stringify(state)
			var memories: int = player.memories.size()
			scene.home_ui.activate_action("water")
			expect(JSON.stringify(scene.colony.environment.view().households.player) == snapshot and player.memories.size() == memories and not scene.home_ui.feedback.text.is_empty(), "a still-wet plant gives feedback without repeated changes or memories")
		await capture(viewport, "player-" + key)
		var before: String = JSON.stringify(scene.colony.environment.view())
		player.pos = Layout.data().entry.duplicate()
		player.target = player.pos.duplicate()
		scene.home_ui.activate_action(action)
		expect(not scene.home_ui.is_reading() and JSON.stringify(scene.colony.environment.view()) == before, key + ": a delayed button cannot act after walking away")
	expect(scene.provider_calls == 0 and not FileAccess.file_exists(save_path), "household controls make no provider call or real save")
	scene.free()
	await process_frame

func visible_activity_case(viewport: SubViewport) -> void:
	var scene := fixture(viewport, "alma")
	await settle()
	var target := target_for(scene, "project")
	expect(not target.is_empty(), "the actual painting exposes its personal detail")
	if target.is_empty():
		scene.free()
		return
	position(scene, "alma", target.item.stand_at)
	var owner: Dictionary = scene.colony.get_resident("alma")
	owner.room = "street"
	owner.activity = "ACTIVIDAD REMOTA PRIVADA"
	scene.home_ui.show_item(target.item)
	expect(not scene.home_ui.feedback.visible and not scene.home_ui.reading_body.text.contains("REMOTA"), "a painting never discloses the owner's activity in another room")
	owner.room = "alma"
	var at: Vector2 = target.item.stand_at + Vector2(-18, 0)
	owner.pos = [at.x, at.y]
	owner.target = owner.pos.duplicate()
	owner.activity = "Mirando el boceto"
	scene.home_ui.show_item(target.item)
	expect(scene.home_ui.feedback.visible and scene.home_ui.feedback.text == "Alma · Mirando el boceto", "nearby unobstructed owner activity can accompany the painting")
	scene.free()
	await process_frame

func capture(viewport: SubViewport, name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../artifacts/home-details")
	DirAccess.make_dir_recursive_absolute(directory)
	var image: Image = viewport.get_texture().get_image()
	expect(image != null and not image.is_empty() and image.save_png(directory.path_join(name + ".png")) == OK, "capture " + name)

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test for isolation")
		quit(1)
		return
	catalog_checks()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768, 432)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await album_case(viewport)
	await household_case(viewport)
	await visible_activity_case(viewport)
	viewport.free()
	await process_frame
	print("HOME DETAILS UI: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
