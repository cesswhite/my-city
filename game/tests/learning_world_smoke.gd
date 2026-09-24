extends SceneTree
## Full playable chain through the real UI callbacks and navigation, without a network or user save.

const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Art = preload("res://scripts/pixel_art.gd")
var checks = 0
var failures: Array[String] = []
var invalid_positions = 0
var sampled_positions = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func walk(scene: Node, frames = 700) -> void:
	for frame in range(frames):
		for resident in scene.colony.residents:
			scene.move_resident(resident, 1.0 / 30.0)
			sampled_positions += 1
			if not Navigation.is_walkable(scene.position_of(resident), resident.room): invalid_positions += 1
		scene.resolve_player_arrival()
		scene.update_room()

func action_button(scene: Node, action_id: String, item_id: String = "") -> Button:
	if not is_instance_valid(scene.learning.panel): return null
	for child in scene.learning.panel.find_children("*", "Button", true, false):
		if str(child.get_meta("journal_action", "")) != action_id: continue
		if not item_id.is_empty() and str(child.get_meta("item_id", "")) != item_id: continue
		if not child.disabled: return child
	return null

func press(scene: Node, action_id: String, item_id: String = "") -> bool:
	if not is_instance_valid(scene.learning.panel):
		expect(false, "Panel exists for action " + action_id)
		return false
	var button: Button = action_button(scene,action_id,item_id)
	if is_instance_valid(button):
		button.pressed.emit()
		return true
	expect(false, "Enabled journal action exists: " + action_id + (" / " + item_id if not item_id.is_empty() else ""))
	return false

func capture(scene: Node, name: String) -> void:
	if "--capture-learning" not in OS.get_cmdline_user_args(): return
	scene.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var folder = OS.get_environment("MY_CITY_CAPTURE_DIR")
	if not folder.is_empty(): root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func run() -> void:
	# Apply after engine startup: the headless window otherwise remains 64×64.
	root.size = Vector2i(768, 432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test so this test never touches the player's save.")
		quit(1)
		return
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.save_allowed = false
	var player: Dictionary = scene.colony.get_resident("player")
	expect(scene.preview_mode, "Fixture never loads the user's game")
	scene.toggle_bicycle()
	expect(not scene.riding_bicycle, "Bicycle cannot be ridden before learning and repair")
	scene.learning.show_journal("bicicleta_de_mateo")
	expect(not is_instance_valid(action_button(scene,"start")) and is_instance_valid(action_button(scene,"mentor")), "A distant mentor offers an approach route instead of remote acceptance")
	press(scene, "mentor")
	expect(scene.colony.quest_status("bicicleta_de_mateo").status == "available", "Ordering the approach does not accept the assignment remotely")
	walk(scene)
	expect(scene.position_of(player).distance_to(scene.position_of(scene.colony.get_resident("mateo"))) < scene.colony.MAX_DISTANCE, "Player physically reaches talking distance from Mateo without overlapping him")
	scene.learning.show_for_mentor("mateo")
	press(scene, "start")
	expect(scene.colony.quest_status("bicicleta_de_mateo").status == "accepted", "Nearby mentor starts the quest through its UI action")
	press(scene, "shop")
	walk(scene)
	expect(scene.learning.mode == "shop" and is_instance_valid(scene.learning.panel), "Arriving at the actual shop opens its counter")
	expect(scene.position_of(player).distance_to(Layout.stand_at("shop", "street")) < 5, "Purchase is made at the shop's service point")
	var coins_before: int = scene.colony.progression_state().coins
	press(scene, "buy", "aceite")
	expect(scene.colony.progression_state().coins < coins_before, "Shop purchase charges coins")
	expect(not scene.colony.can_ride_bicycle(), "Buying oil alone never unlocks the bicycle")
	# Mateo finishes his workshop visit and physically walks elsewhere. Delivery
	# must follow the person, while the shop and home practice remain real places.
	var mentor: Dictionary = scene.colony.get_resident("mateo")
	mentor.target = [184.0,280.0]
	mentor.travel_intent = ""
	scene.paths.erase("mateo")
	walk(scene)
	expect(scene.position_of(mentor).distance_to(Vector2(184,280)) < 1.0, "Mentor physically reaches a different neighborhood meeting point")
	expect(scene.position_of(mentor).distance_to(Layout.point(scene.colony.PLACES.taller)) >= scene.colony.MAX_DISTANCE, "Delivery fixture is outside the workshop's former required radius")
	scene.learning.show_journal("bicicleta_de_mateo")
	expect(not is_instance_valid(action_button(scene,"deliver")) and is_instance_valid(action_button(scene,"mentor")), "Materials ready with a distant mentor offer an approach route instead of remote delivery")
	var materials_before: Dictionary = scene.colony.progression_state().inventory
	press(scene, "mentor")
	expect(scene.colony.quest_status("bicicleta_de_mateo").status == "accepted" and scene.colony.progression_state().inventory == materials_before, "Approaching the relocated mentor preserves undelivered materials and assignment")
	walk(scene)
	scene.learning.show_for_mentor("mateo")
	press(scene, "deliver")
	expect(scene.colony.quest_status("bicicleta_de_mateo").status == "learned" and player.room == mentor.room and scene.position_of(player).distance_to(scene.position_of(mentor)) < scene.colony.MAX_DISTANCE, "UI delivery beside the relocated mentor gives a stored procedure")
	expect(not scene.colony.can_ride_bicycle(), "Receiving instructions is distinct from demonstrating repair")
	press(scene, "station")
	walk(scene)
	expect(is_instance_valid(scene.door_panel), "Player walks to their own door")
	scene.knock_home("player")
	expect(player.room == "player", "Player enters their own home")
	var bike: Dictionary = {}
	for item in Art.interior_items("player"):
		if item.id == "bicycle": bike = item
	var click = InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	click.position = scene.world_to_screen(bike.rect.get_center())
	scene._gui_input(click)
	walk(scene)
	expect(scene.position_of(player).distance_to(bike.stand_at) < 5, "Bicycle interaction requires walking to the work area")
	expect(is_instance_valid(scene.learning.panel), "Bicycle hotspot opens the procedure")
	await capture(scene, "learning-procedure")
	var quest: Dictionary = scene.colony.available_apprenticeships()[0]
	for index in range(quest.steps.size()):
		press(scene, "practice")
		expect(scene.colony.quest_status(quest.id).step_index == index + 1, "Each step executes once in the world")
	expect(scene.colony.can_ride_bicycle(), "Complete verified repair unlocks bicycle")
	expect(scene.scenery.interior_state.bicycle_repaired, "Repair also changes the displayed bicycle state")
	scene.toggle_bicycle()
	expect(not scene.riding_bicycle, "Player cannot ride inside a house")
	scene.learning.close()
	await capture(scene, "bicycle-repaired-home")
	scene.go_outside()
	walk(scene)
	expect(player.room == Layout.home_area("player"), "Player exits at the real home door")
	scene.toggle_bicycle()
	expect(scene.riding_bicycle, "Repaired bicycle can be mounted outdoors")
	await capture(scene, "cycling")
	# The doorway may sit between grid cells. Walk onto a node before measuring
	# straight-line displacement; a first sideways segment is real travel too.
	var door: Vector2 = Navigation.door_positions().player
	var aligned: Vector2 = (door / Navigation.CELL).round() * Navigation.CELL
	player.target = [aligned.x, aligned.y]
	scene.paths.erase("player")
	for _step in range(16):
		scene.move_resident(player, 1.0 / 30.0)
		if scene.position_of(player).distance_to(aligned) < 0.01: break
	expect(scene.position_of(player) == aligned, "cycling physically reaches a nearby grid node before its straight speed sample")
	# Stay in the free approach above the garden: the old +80 goal now lies in a crop bed.
	player.target = [aligned.x, aligned.y + 48.0]
	scene.paths.erase("player")
	var start: Vector2 = scene.position_of(player)
	scene.move_resident(player, 0.25)
	var ridden: float = scene.position_of(player).distance_to(start)
	expect(absf(ridden - 30.0) < 0.1, "Cycling moves 120 pixels/s across grid waypoints, not just a cosmetic sprite")
	expect(Navigation.is_walkable(scene.position_of(player)), "Riding preserves collisions")
	scene.toggle_bicycle()
	start = scene.position_of(player)
	scene.move_resident(player, 0.25)
	expect(absf(scene.position_of(player).distance_to(start) - 12.0) < 0.1, "Dismounting restores the player walking speed of 48 pixels/s")
	expect(invalid_positions == 0, "Every sampled position in the playable quest is walkable")
	expect(scene.dialogue_job.is_empty() and scene.visit_job.is_empty(), "Local learning chain requires no AI request")
	scene.queue_free()
	await process_frame
	print("LEARNING WORLD: %d/%d checks passed; %d sampled positions" % [checks - failures.size(), checks, sampled_positions])
	quit(0 if failures.is_empty() else 1)
