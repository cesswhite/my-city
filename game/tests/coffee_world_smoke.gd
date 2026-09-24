extends SceneTree
## Real seat approach, mouse/key input and paid coffee, without saves or providers.
const Seats = preload("res://scripts/seating.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const COFFEE := "taza_cafe"
class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_id: String, _speaker: String, _text: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var movement_samples := 0
var capture_enabled := false
var output: String

func _initialize() -> void: call_deferred("run")
func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func settle() -> void:
	for _frame in range(4): await process_frame

func click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func press_c() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_C
	event.physical_keycode = KEY_C
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func reset_player(scene) -> void:
	for action: String in ["city_left","city_right","city_up","city_down","city_cafe"]:
		if InputMap.has_action(action): Input.action_release(action)
	scene.take_control()
	scene.hide_inspector()
	scene.close_help()
	scene.overlay.dismiss_toast()
	scene.controls_active = true
	scene.paused = false
	scene.elapsed = 0.0
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = "street"
	player.pos = [192.0,230.0]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	scene.paths.clear()
	scene.get_viewport().gui_release_focus()
	scene.update_room()
	scene.cafe_service._locked_until = 0
	scene.cafe_service.refresh()

func balance(scene) -> int: return int(scene.colony.progression_state().coins)
func cups(scene) -> int: return int(scene.colony.progression_state().inventory.get(COFFEE,0))

func approach(scene, seat: Dictionary) -> bool:
	var player: Dictionary = scene.colony.get_resident("player")
	var safe := true
	for _frame in range(1000):
		if scene.seating.active_id == seat.id:
			scene.cafe_service.refresh()
			return safe
		var before: Vector2 = scene.position_of(player)
		scene.move_resident(player,0.05)
		scene.resolve_player_arrival()
		var after: Vector2 = scene.position_of(player)
		movement_samples += 1
		safe = safe and Navigation.is_walkable(after) and Navigation._clear_segment(before,after,"street") and before.distance_to(after) <= 2.41
	return false

func table_for(seat: Dictionary) -> Dictionary:
	for object: Dictionary in Sprites.scenery_objects():
		if object.key == seat.prop_key: return object
	return {}

func snapshot(scene, name: String) -> Image:
	scene.interaction_hover.clear()
	scene.overlay.dismiss_toast()
	scene.refresh_status()
	scene.actors.queue_redraw()
	scene.world_labels.queue_redraw()
	await settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	expect(image.save_png(output.path_join(name + ".png")) == OK,name + " screenshot saved")
	return image

func table_changes(scene, seat: Dictionary, before: Image, after: Image) -> int:
	var table: Dictionary = table_for(seat)
	var world := Rect2(table.rect.position+Vector2(10,0),Vector2(19,13))
	var screen := Rect2i(scene.world_to_screen(world.position).floor(),(world.size*scene.world_scale).ceil())
	var changed := 0
	for y in range(screen.position.y,screen.end.y):
		for x in range(screen.position.x,screen.end.x):
			if before.get_pixel(x,y) != after.get_pixel(x,y): changed += 1
	return changed

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	capture_enabled = "--capture-coffee" in OS.get_cmdline_user_args()
	output = ProjectSettings.globalize_path("res://../artifacts/coffee")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(768,432)
	var scene = MainProbe.new()
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	for resident: Dictionary in scene.colony.residents:
		if resident.id == "player": continue
		resident.room = resident.id
		resident.pos = Layout.data().entry.duplicate()
		resident.target = resident.pos.duplicate()
	await settle()
	var coffee_seats: Array[Dictionary] = []
	for seat: Dictionary in Seats.seats():
		if str(seat.prop_key).begins_with("cafe_table"): coffee_seats.append(seat)
	expect(coffee_seats.size() == 4,"coffee is associated with exactly four physical cafe stools")
	var bound := false
	if InputMap.has_action("city_cafe"):
		for event in InputMap.action_get_events("city_cafe"):
			bound = bound or (event is InputEventKey and event.physical_keycode == KEY_C)
	expect(bound,"coffee action has a real physical C-key binding")
	for index in coffee_seats.size():
		var seat: Dictionary = coffee_seats[index]
		reset_player(scene)
		scene.colony.get_resident("player").energy = 80.0
		scene.colony._progression.state.coins = 20
		scene.colony._progression.state.inventory.erase(COFFEE)
		click(scene.world_to_screen(seat.rect.get_center()))
		expect(scene.seating.pending_id == seat.id and not scene.seating.is_seated(),seat.id + " click starts physical approach without instantly seating")
		press_c()
		expect(balance(scene) == 20 and cups(scene) == 0 and not scene.cafe_service.panel.visible,seat.id + " walking or pressing C before arrival cannot place an order")
		expect(approach(scene,seat),seat.id + " reaches the real stool through walkable, speed-limited steps")
		await settle()
		expect(scene.cafe_service.panel.visible and not scene.cafe_service.action_button.disabled and scene.cafe_service.action_button.text.contains("3"),seat.id + " displays the explicit three-coin offer after arrival")
		expect(balance(scene) == 20 and cups(scene) == 0,seat.id + " sitting does not buy coffee automatically")
		var before_image: Image
		if capture_enabled and index == 0: before_image = await snapshot(scene,"coffee-offer")
		if index % 2 == 0: click(scene.cafe_service.action_button.get_global_rect().get_center())
		else: press_c()
		expect(balance(scene) == 17 and cups(scene) == 1,seat.id + " real input pays exactly three coins for one cup")
		expect(scene.colony.player_energy() == 80.0 and scene.hud.energy_value.text == "80%",seat.id + " buying alone does not restore energy")
		expect(scene.hud.coin_value.text == "17" and scene.cafe_service.action_button.text.contains("Beber"),seat.id + " updates the wallet and switches the same action to drinking")
		# The immediate second activation must neither charge again nor consume the cup.
		press_c()
		click(scene.cafe_service.action_button.get_global_rect().get_center())
		expect(balance(scene) == 17 and cups(scene) == 1,seat.id + " rapid clicks and key presses cannot double-charge or auto-drink")
		if capture_enabled and index == 0:
			var ready_image: Image = await snapshot(scene,"coffee-ready")
			expect(table_changes(scene,seat,before_image,ready_image) > 0,"paid coffee adds visible native sprite pixels on the occupied table")
		var before_pos: Array = scene.colony.get_resident("player").pos.duplicate()
		scene.cafe_service._locked_until = 0
		scene.cafe_service.refresh()
		if index % 2 == 0: press_c()
		else: click(scene.cafe_service.action_button.get_global_rect().get_center())
		expect(balance(scene) == 17 and cups(scene) == 0 and scene.seating.active_id == seat.id and scene.colony.get_resident("player").pos == before_pos,seat.id + " intentional drinking consumes the paid cup while remaining seated")
		expect(scene.colony.player_energy() == 85.0 and scene.hud.energy_value.text == "85%" and scene.cafe_service.note.text.contains("+5%"),seat.id + " drinking by mouse or keyboard restores five points and immediately updates the energy HUD")
		if capture_enabled and index == 0:
			var empty_image: Image = await snapshot(scene,"coffee-finished")
			expect(table_changes(scene,seat,before_image,empty_image) == 0,"finishing the coffee removes only its temporary cup from the table")

	# Stale callbacks must re-read posture rather than trust the previously visible button.
	scene.cafe_service._locked_until = 0
	scene.cafe_service.activate()
	var paid_balance: int = balance(scene)
	expect(cups(scene) == 1,"stale-state fixture purchases a real cup")
	scene.seating.stand()
	scene.cafe_service._locked_until = 0
	scene.cafe_service.activate()
	scene.cafe_service.refresh()
	expect(not scene.cafe_service.panel.visible and balance(scene) == paid_balance and cups(scene) == 1,"standing hides the offer and invalidates an already queued activation")
	var seat: Dictionary = coffee_seats.back()
	scene.seating.request(seat.id)
	approach(scene,seat)
	expect(cups(scene) == 1 and scene.cafe_service.action_button.text.contains("Beber"),"sitting again preserves the bought cup without charging again")
	scene.cafe_service._locked_until = 0
	scene.cafe_service.activate()

	scene.colony._progression.state.coins = 2
	scene.cafe_service._locked_until = 0
	scene.cafe_service.refresh()
	expect(scene.cafe_service.panel.visible and scene.cafe_service.action_button.disabled,"insufficient funds visibly disable ordering at a valid stool")
	click(scene.cafe_service.action_button.get_global_rect().get_center())
	press_c()
	expect(balance(scene) == 2 and cups(scene) == 0,"mouse and keyboard cannot bypass insufficient funds")

	for id: String in ["bench_west_front","fountain_south"]:
		reset_player(scene)
		var other: Dictionary = Seats.get_seat(id)
		scene.seating.request(id)
		expect(approach(scene,other),id + " remains a functional ordinary seat")
		await settle()
		scene.cafe_service._locked_until = 0
		press_c()
		scene.cafe_service.activate()
		expect(not scene.cafe_service.panel.visible and balance(scene) == 2 and cups(scene) == 0,id + " never advertises or sells cafe service")
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and scene.colony.minute == 480 and not scene.save_allowed,"coffee, seating and rendering require no provider, artificial clock advance or save")
	scene.free()
	await process_frame
	print("COFFEE WORLD: %d/%d checks passed; %d movement samples" % [checks-failures.size(),checks,movement_samples])
	quit(0 if failures.is_empty() else 1)
