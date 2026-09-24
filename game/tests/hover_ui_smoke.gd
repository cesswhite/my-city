extends SceneTree
## Pointer-to-action integration, scaled rendering, and modal boundaries. No saves/providers.
const Layout = preload("res://scripts/world_layout.gd")
const Targets = preload("res://scripts/world_interactions.gd")
const Sprites = preload("res://scripts/sprite_art.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void:
		provider_calls += 1

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: " + description)
	else:
		failures.append(description)
		push_error(description)

func settle() -> void:
	for _frame in range(4): await process_frame

func move(scene: Control, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = scene.world_to_screen(point)
	scene.get_viewport().push_input(event, true)

func click(scene: Control, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = scene.world_to_screen(point)
	scene.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	scene.get_viewport().push_input(event, true)

func enter(scene: Control, room: String) -> void:
	scene.controls_active = true
	scene.close_door_panel()
	scene.close_help()
	scene.learning.close()
	scene.sleep_ui.close()
	scene.clear_player_intentions()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = room
	player.pos = Layout.data().entry.duplicate()
	player.target = player.pos.duplicate()
	scene.update_room()
	scene.paused = true

func target_for(room: String, key: String, state: Dictionary) -> Dictionary:
	for item: Dictionary in Targets._targets(room, state):
		if item.object.get("key", "") == key: return item
	return {}

func world_snapshot(scene: Control) -> String:
	return JSON.stringify({"residents":scene.colony.residents, "events":scene.colony.events,
		"progression":scene.colony.progression_state(), "minute":scene.colony.minute,
		"holds":scene.colony.conversation_holds, "autonomy":scene.colony.player_autonomy})

func place(scene: Control, id: String, feet: Vector2, room: String = "street") -> void:
	var resident: Dictionary = scene.colony.get_resident(id)
	resident.room = room
	resident.pos = [feet.x,feet.y]
	resident.target = resident.pos.duplicate()
	resident.travel_intent = ""

func actor_point(scene: Control, id: String) -> Vector2:
	return scene.pointer_actor_rect(scene.colony.get_resident(id),scene.colony.daily_state(id)).get_center()

func capture(viewport: SubViewport, name: String) -> void:
	var directory: String = OS.get_environment("MY_CITY_CAPTURE_DIR")
	if directory.is_empty(): return
	await settle()
	await RenderingServer.frame_post_draw
	expect(viewport.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, name + " screenshot exported")

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,432)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := MainProbe.new()
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	for dimensions: Vector2i in [Vector2i(768,432),Vector2i(960,600)]:
		viewport.size = dimensions
		await settle()
		enter(scene,"player")
		var bed: Dictionary = target_for("player","bed",scene.home_project_state())
		move(scene,bed.rect.get_center())
		expect(scene.interaction_hover.target.get("item",{}).get("id","") == "bed", "%s pointer resolves the rendered bed" % dimensions)
		expect(scene.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND and scene.hint_label.text == "Clic: Dormir · Tu cama", "%s hover gives a hand and a concise action even while paused" % dimensions)
		click(scene,bed.rect.get_center())
		expect(scene.pending_item.get("id","") == "bed" and scene.colony.get_resident("player").target == [bed.item.stand_at.x,bed.item.stand_at.y], "%s click walks to the same bed interaction" % dimensions)
		enter(scene,"mateo")
		var project: Dictionary = target_for("mateo","project",scene.home_project_state())
		move(scene,project.rect.get_center())
		expect(scene.interaction_hover.target.get("key","") == "mateo:item:project", "%s hovering tools picks Mateo's actual project" % dimensions)
		click(scene,project.rect.get_center())
		expect(scene.pending_item.get("title","") == project.item.title and scene.pending_item.get("room","") == "mateo", "%s clicking the highlighted tools keeps their story and approach point" % dimensions)
		var floor_point := Vector2(186,248)
		move(scene,floor_point)
		expect(scene.interaction_hover.target.is_empty() and scene.mouse_default_cursor_shape == Control.CURSOR_ARROW, "%s empty floor has no false interaction" % dimensions)
		enter(scene,"street")
		var own_door: Dictionary = {}
		for target: Dictionary in Targets._targets("street",{}):
			if target.get("home_id","") == "player": own_door = target
		move(scene,own_door.rect.get_center())
		expect(scene.interaction_hover.target.get("home_id","") == "player" and scene.interaction_hover.target.object.glow_rect == own_door.rect, "%s only the doorway is highlighted" % dimensions)
		click(scene,own_door.rect.get_center())
		expect(scene.pending_home == "player", "%s highlighted door routes to the real entrance" % dimensions)
		enter(scene,"player")
		var exit: Dictionary = target_for("player","exit_mat",{})
		move(scene,exit.rect.get_center())
		click(scene,exit.rect.get_center())
		expect(scene.pending_exit and scene.pending_item.is_empty(), "%s highlighted exit mat routes outside" % dimensions)

	enter(scene,"mateo")
	var project: Dictionary = target_for("mateo","project",{})
	move(scene,project.rect.get_center())
	scene.show_help()
	scene.interaction_hover.refresh()
	expect(scene.interaction_hover.target.is_empty() and scene.mouse_default_cursor_shape == Control.CURSOR_ARROW, "opening a modal clears the halo and pointer")
	click(scene,project.rect.get_center())
	expect(scene.pending_item.is_empty(), "modal blocks the action behind it")
	scene.close_help()
	move(scene,project.rect.get_center())
	scene._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(scene.interaction_hover.target.is_empty(), "losing window focus clears hover")
	scene.controls_active = true
	move(scene,project.rect.get_center())
	scene.suspend_for_menu()
	expect(scene.interaction_hover.target.is_empty(), "main menu cannot retain a world halo")
	scene.resume_from_menu()
	scene.set_process(false)
	scene.controls_active = true
	move(scene,project.rect.get_center())
	enter(scene,"player")
	expect(scene.interaction_hover.target.is_empty(), "changing rooms clears the previous object's feedback")
	var bed: Dictionary = target_for("player","bed",{})
	move(scene,bed.rect.get_center())
	scene.open_inspector("player", "historia")
	scene.interaction_hover.update(Vector2(viewport.size.x-100,100))
	expect(scene.interaction_hover.target.is_empty(), "moving into the inspector clears the world feedback")

	# Hover and profile selection are read-only, including at a stationary pointer.
	enter(scene,"street")
	await settle()
	for resident: Dictionary in scene.colony.residents:
		if resident.id != "player": place(scene,resident.id,Layout.point(Layout.data().home_rest),resident.id)
	place(scene,"player",Vector2(326,214))
	place(scene,"mateo",Vector2(270,194))
	place(scene,"lupita",Vector2(326,194))
	scene.selected_id = "player"
	var before: String = world_snapshot(scene)
	var mateo_point := actor_point(scene,"mateo")
	scene.actors.queue_redraw()
	await capture(viewport,"npc-before")
	move(scene,mateo_point)
	expect(scene.interaction_hover.target.get("resident_id","") == "mateo" and scene.interaction_hover.target.get("kind","") == "resident", "an awake street NPC becomes the hover target at the rendered body")
	expect(scene.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND and scene.hint_label.text == "Clic: Ver perfil · Mateo", "NPC hover gives the hand cursor and the profile action with their name")
	await capture(viewport,"npc-hover")
	for _repeat in range(5): scene.interaction_hover.refresh()
	expect(world_snapshot(scene) == before and scene.provider_calls == 0, "repeated NPC hover changes neither world state, relationships nor provider activity")
	move(scene,actor_point(scene,"lupita"))
	expect(scene.interaction_hover.target.get("resident_id","") == "lupita" and scene.hint_label.text == "Clic: Ver perfil · Lupita", "moving the pointer to another NPC switches both the halo target and name")
	move(scene,mateo_point)
	place(scene,"mateo",Vector2(326,194))
	place(scene,"lupita",Vector2(270,194))
	before = world_snapshot(scene)
	scene.interaction_hover.refresh()
	expect(scene.interaction_hover.target.get("resident_id","") == "lupita" and scene.hint_label.text == "Clic: Ver perfil · Lupita", "a different NPC arriving under a stationary pointer replaces the old resident feedback")
	click(scene,mateo_point)
	expect(scene.selected_id == "lupita" and scene.inspector.visible and scene.page == "historia" and scene.chat_partner_id.is_empty(), "clicking a highlighted NPC opens their profile without beginning or reserving a chat")
	expect(world_snapshot(scene) == before and scene.provider_calls == 0 and scene.dialogue_job.is_empty(), "viewing a profile leaves schedules, memories, emotions and provider state unchanged")
	scene.interaction_hover.update(scene.inspector.get_global_rect().get_center())
	expect(scene.interaction_hover.target.is_empty() and scene.mouse_default_cursor_shape == Control.CURSOR_ARROW, "the inspector covers NPC feedback and restores the normal cursor")
	scene.hide_inspector()
	move(scene,actor_point(scene,"player"))
	expect(scene.pick_world_target(actor_point(scene,"player"),{}).get("resident_id","") == "player" and scene.interaction_hover.target.is_empty() and scene.mouse_default_cursor_shape == Control.CURSOR_ARROW, "the real player body remains clickable without an NPC halo or profile hint")
	move(scene,actor_point(scene,"lupita"))
	scene.show_help()
	scene.interaction_hover.refresh()
	expect(scene.interaction_hover.target.is_empty() and scene.mouse_default_cursor_shape == Control.CURSOR_ARROW, "opening a modal also clears a resident halo")
	scene.close_help()

	# A frontmost body hides an object, including when the pointer stays still.
	enter(scene,"mateo")
	await settle() # Flush modal backdrops queued for deletion by the preceding checks.
	var mateo: Dictionary = scene.colony.get_resident("mateo")
	mateo.room = "mateo"
	mateo.pos = [300,252]
	mateo.target = mateo.pos.duplicate()
	scene.selected_id = "player"
	var overlap := Vector2(146,168)
	move(scene,overlap)
	expect(scene.interaction_hover.target.get("object",{}).get("key","") == "bed", "an unobscured part of the bed can be highlighted")
	mateo.pos = [146,184]
	mateo.target = mateo.pos.duplicate()
	scene.interaction_hover.refresh()
	expect(scene.interaction_hover.target.get("resident_id","") == "mateo" and scene.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "a person moving in front of the bed replaces its stationary-pointer halo with resident feedback")
	click(scene,overlap)
	expect(scene.selected_id == "mateo" and scene.pending_item.is_empty(), "clicking the body in front of the bed selects that person rather than using the bed")
	expect(scene.pick_world_target(Vector2(160,174),{}).get("kind","") != "resident", "empty space outside the real sprite bounds does not use the old broad NPC radius")
	var cached_images: int = scene._pointer_actor_images.size()
	var cached_frames: int = scene._pointer_actor_bounds.size()
	scene.pick_world_target(overlap,{})
	expect(scene._pointer_actor_images.size() == cached_images and scene._pointer_actor_bounds.size() == cached_frames, "repeated pointer checks reuse decoded character images and measured frame bounds")
	mateo.pos = [300,252]
	mateo.target = mateo.pos.duplicate()
	scene.interaction_hover.refresh()
	expect(scene.interaction_hover.target.get("object",{}).get("key","") == "bed", "the bed halo returns when the person leaves without pointer motion")
	mateo.pos = [146,144]
	mateo.target = mateo.pos.duplicate()
	expect(scene.pick_world_target(Vector2(146,140),{}).get("kind","") == "item", "a body behind the bed cannot occlude its foreground surface")
	var bed_stand: Vector2 = Layout.stand_at("bed", "mateo")
	mateo.pos = [bed_stand.x,bed_stand.y]
	mateo.target = mateo.pos.duplicate()
	expect(scene.colony.start_sleep("mateo",60), "sleeper fixture starts through the real bed rule")
	var head: Rect2 = scene.ActivityVisuals.sleep_layout("mateo").head
	move(scene,head.get_center())
	expect(scene.interaction_hover.target.get("resident_id","") == "mateo" and scene.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "hovering a sleeper selects the visible pillow head for profile feedback")
	await capture(viewport,"sleeping-npc-hover")
	click(scene,head.get_center())
	expect(scene.selected_id == "mateo" and scene.pending_item.is_empty() and scene.colony.is_sleeping("mateo") and scene.chat_partner_id.is_empty(), "a sleeper's profile opens at the drawn head without using the bed, waking them or forcing a chat")
	expect(scene.pick_world_target(bed_stand-Vector2(0,10),{}).get("kind","") != "resident", "a sleeper has no invisible standing-body target at their physical bed waypoint")
	scene.colony.wake_resident("mateo")
	mateo.room = "street"

	# Render the actual table/tool overlap and doorway crop through the normal y-sort.
	enter(scene,"mateo")
	scene.selected_id = "mateo"
	scene.colony.get_resident("mateo").room = "street"
	scene.build_inspector()
	scene.message("Pasa el mouse por los objetos. Haz clic para acercarte y usarlos.")
	scene.interaction_hover.clear()
	scene.actors.queue_redraw()
	await capture(viewport,"tools-before")
	move(scene,project.rect.get_center())
	await capture(viewport,"tools-hover")
	enter(scene,"player")
	move(scene,bed.rect.get_center())
	await capture(viewport,"bed-hover")
	enter(scene,"street")
	for target: Dictionary in Targets._targets("street",{}):
		if target.get("home_id","") == "mateo":
			move(scene,target.rect.get_center())
			break
	await capture(viewport,"door-hover")
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and not scene.decision_pending and scene.colony.minute == 480, "hover and clicks neither consult providers nor advance isolated simulation")
	scene.free()
	viewport.free()
	await process_frame
	print("HOVER UI: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
