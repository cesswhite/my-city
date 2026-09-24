extends SceneTree
## Measured façade pixels + real movement/input. Only isolated temporary saves.
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Targets = preload("res://scripts/world_interactions.gd")
# Native glass centers remain measured independently. The split houses now
# have finished side walls, so their frontage samples cover those opaque walls.
const FRONTAGES := [
	{"room":"street","x":42.0},{"room":"street","x":95.0},
	{"room":"gardens","x":128.0},{"room":"homes","x":208.0},
	{"room":"atelier","x":269.0},{"room":"workshops","x":380.0},
	{"room":"homes","x":421.0},{"room":"homes","x":461.0}]
const FRONT_Y := 160.0
const FACADES := {
	"street":[Rect2(16,70,100,90)],"gardens":[Rect2(120,84,48,76)],
	"homes":[Rect2(168,84,48,76),Rect2(406,90,70,70)],
	"atelier":[Rect2(220,86,68,74)],"workshops":[Rect2(292,88,110,72)]}
var checks := 0
var failures: Array[String] = []
var samples := 0
var test_path := "user://test_facade_collision_%d.json" % OS.get_process_id()

class LoadedFixture:
	extends "res://scripts/colony.gd"
	var loaded_fixture := false
	func setup(_load_existing: bool = true, _developed: bool = false):
		super.setup(false, true)
		# Main stays in --ui-test. Only this exact fixture prefix may be loaded.
		if save_path.begins_with("user://test_facade_collision_"):
			loaded_fixture = load_game()

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func clean() -> void:
	for suffix in ["",".tmp",".bak"]:
		if FileAccess.file_exists(test_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path+suffix))

func outside_facades(point: Vector2, room: String = "street") -> bool:
	for rect: Rect2 in FACADES.get(room, []):
		if rect.has_point(point): return false
	return true

func fixture() -> MainProbe:
	var scene := MainProbe.new()
	scene.start_new_game = true
	scene.colony.save_path = test_path
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.save_allowed = false
	scene.service_url = ""
	scene.service_token = ""
	scene.use_jev = false
	scene.controls_active = true
	scene.paused = false
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	for resident: Dictionary in scene.colony.residents:
		if resident.id == "player": continue
		resident.room = resident.id
		resident.pos = Layout.data().entry.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	return scene

func put_player(scene: MainProbe, point: Vector2, room: String = "street") -> void:
	scene.take_control()
	scene.close_door_panel()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = room
	player.pos = [point.x,point.y]
	player.target = player.pos.duplicate()
	scene.update_room()
	scene.controls_active = true
	scene.paused = false

func click(viewport: Viewport, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	viewport.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	viewport.push_input(event,true)

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Requires -- --ui-test; refusing access to the real save.")
		quit(1)
		return
	root.size = Vector2i(768,432)
	clean()
	var scene := fixture()
	await process_frame
	await process_frame
	var player: Dictionary = scene.colony.get_resident("player")
	for sample: Dictionary in [
		{"room":"atelier","x":226},{"room":"atelier","x":266},
		{"room":"street","x":26},{"room":"street","x":106},
		{"room":"gardens","x":128},{"room":"homes","x":208},
		{"room":"workshops","x":340},{"room":"homes","x":412},{"room":"homes","x":470}]:
		expect(not Navigation.is_walkable(Vector2(sample.x,158),sample.room),"integrated planter base is solid in %s at x=%d" % [sample.room,sample.x])
	var old_frontages_open := true
	for x: float in [142.0,195.0,249.0,441.0]:
		old_frontages_open = old_frontages_open and Navigation.is_walkable(Vector2(x,158),"street")
	expect(old_frontages_open,"relocated homes leave open ground apart from the authored community building plot")
	expect(not Navigation.is_walkable(Vector2(352,158),"street"),"community building plot retains its fixed solid footprint")
	for frontage: Dictionary in FRONTAGES:
		var room: String = frontage.room
		var x: float = frontage.x
		expect(not Navigation.is_walkable(Vector2(x,FRONT_Y-2),room),"the measured façade frontage is solid in %s at x=%.0f" % [room,x])
		var start := Vector2(x,FRONT_Y+14)
		expect(Navigation.is_walkable(start,room),"the façade approach remains real walkable ground in %s at x=%.0f" % [room,x])
		for direction: Vector2 in [Vector2.UP,Vector2(-1,-1),Vector2(1,-1)]:
			put_player(scene,start,room)
			var safe := true
			var moved := false
			for _frame in range(30):
				var before: Vector2 = scene.position_of(player)
				scene.move_player_keyboard(direction,0.1)
				var after: Vector2 = scene.position_of(player)
				samples += 1
				moved = moved or before.distance_to(after) > 0.001
				safe = safe and outside_facades(after,room) and Navigation.is_walkable(after,room) and before.distance_to(after) <= 4.81
				if direction == Vector2.UP: safe = safe and scene.position_of(player).y >= FRONT_Y
			expect(safe and moved and player.room == room,"front/diagonal input %s stops or slides outside %s façade at x=%.0f" % [direction,room,x])

	# The same façade applies to pathfinding, including goals from older coordinates.
	put_player(scene,Vector2(192,230))
	var npc: Dictionary = scene.colony.get_resident("mateo")
	var path_safe := true
	var reached_front := true
	for frontage: Dictionary in FRONTAGES:
		var room: String = frontage.room
		var x: float = frontage.x
		npc.room = room
		npc.pos = [x,174.0]
		npc.target = [x,158.0]
		npc.travel_intent = ""
		scene.paths.erase(npc.id)
		for _frame in range(30):
			var before: Vector2 = scene.position_of(npc)
			scene.move_resident(npc,0.05)
			var after: Vector2 = scene.position_of(npc)
			samples += 1
			path_safe = path_safe and outside_facades(after,room) and Navigation.is_walkable(after,room) and Navigation._clear_segment(before,after,room) and before.distance_to(after) <= 1.51
		reached_front = reached_front and scene.position_of(npc).y < 174
	expect(path_safe and reached_front,"NPC paths toward old window coordinates approach safely without entering a façade")
	npc.room = "mateo"
	npc.pos = Layout.data().entry.duplicate()
	npc.target = npc.pos.duplicate()
	var doors: Dictionary = Layout.door_positions()
	expect(doors.size() == 6,"the six actual household entrances remain in the shared layout")
	for home_id: String in doors:
		var door: Vector2 = doors[home_id]
		var room: String = Layout.home_area(home_id)
		put_player(scene,Vector2(244,196),room)
		var target: Dictionary = {}
		for candidate: Dictionary in Targets._targets(room,{}):
			if candidate.get("home_id","") == home_id: target = candidate
		expect(Navigation.is_walkable(door,room) and not target.is_empty(),home_id + " has a navigable physical doorway and its own clickable opening")
		if target.is_empty(): continue
		var picked: Dictionary = Targets.pick(target.rect.get_center(),room)
		expect(picked.get("home_id","") == home_id,home_id + " doorway pixels resolve the correct home")
		click(root,scene.world_to_screen(target.rect.get_center()))
		expect(scene.pending_home == home_id and Layout.point(player.target) == door,home_id + " actual viewport click orders the unchanged doorstep")
		var legal := true
		for _frame in range(900):
			var before: Vector2 = scene.position_of(player)
			scene.move_resident(player,0.05)
			scene.resolve_player_arrival()
			var after: Vector2 = scene.position_of(player)
			samples += 1
			legal = legal and outside_facades(after,room) and Navigation.is_walkable(after,room) and Navigation._clear_segment(before,after,room) and before.distance_to(after) <= 2.41
			if is_instance_valid(scene.door_panel): break
		expect(legal and scene.position_of(player).distance_to(door) < 5 and is_instance_valid(scene.door_panel),home_id + " is reached through legal segments and opens the visit dialog")
		scene.close_door_panel()
		await process_frame
	expect(scene.provider_calls == 0 and scene.dialogue_job.is_empty() and scene.visit_job.is_empty(),"façade movement and door clicks create no provider calls")
	scene.free()

	# Load a genuine, isolated older save through Main's real startup reconciliation.
	var saved = Colony.new()
	saved.save_path = test_path
	saved.setup(false, true)
	var saved_player: Dictionary = saved.get_resident("player")
	saved_player.room = "player"
	saved.observe_house_item("player","player","Recuerdo temporal","Esta observación pertenece sólo a la prueba.")
	saved_player.name = "Partida de prueba"
	saved_player.energy = 63.0
	saved_player.room = "homes"
	saved_player.pos = [176.0,158.0]
	saved_player.target = saved_player.pos.duplicate()
	var saved_npc: Dictionary = saved.get_resident("mateo")
	saved_npc.room = "workshops"
	saved_npc.pos = [380.0,158.0]
	saved_npc.target = saved_npc.pos.duplicate()
	var only_target: Dictionary = saved.get_resident("cesar")
	only_target.room = "atelier"
	only_target.pos = [280.0,180.0]
	only_target.target = [269.0,158.0]
	var memories: Array = JSON.parse_string(JSON.stringify(saved_player.memories))
	expect(saved.save_game(),"isolated older-save fixture writes valid data with newly obstructed coordinates")
	var source_text := FileAccess.get_file_as_string(test_path)
	var loaded := LoadedFixture.new()
	loaded.save_path = test_path
	var reopened := MainProbe.new()
	reopened.colony = loaded
	root.add_child(reopened)
	reopened.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reopened.set_process(false)
	reopened.save_allowed = false
	reopened.service_token = ""
	reopened.use_jev = false
	expect(reopened.preview_mode and loaded.loaded_fixture,"startup loads only the explicit temporary save while retaining UI-test isolation")
	for id: String in ["player","mateo"]:
		var resident: Dictionary = loaded.get_resident(id)
		var former := Vector2(176,158) if id == "player" else Vector2(380,158)
		var room: String = str(resident.room)
		var recovered: Vector2 = Layout.point(resident.pos)
		expect(recovered != former and recovered.distance_to(former) <= 64 and recovered.y >= FRONT_Y and Navigation.is_walkable(recovered,room) and resident.target == resident.pos,id + " older façade position recovers to nearby free ground with a safe stopped target")
		expect(not Navigation.route(recovered,Vector2(244,196),room).is_empty(),id + " recovered position reconnects to the rest of the street")
	expect(loaded.get_resident("cesar").pos == [280.0,180.0] and loaded.get_resident("cesar").target == loaded.get_resident("cesar").pos,"a valid saved position is preserved while an obstructed target is stopped")
	expect(loaded.get_resident("player").memories == memories and loaded.get_resident("player").name == "Partida de prueba" and loaded.player_energy() == 63,"startup recovery preserves personal memories, customization and energy")
	expect(FileAccess.get_file_as_string(test_path) == source_text,"loading and recovering never silently rewrite the source save")
	expect(reopened.provider_calls == 0 and not loaded.player_autonomy,"recovery starts under manual control without provider requests")
	reopened.free()
	clean()
	print("FACADE COLLISION: %d/%d checks passed; %d movement samples" % [checks-failures.size(),checks,samples])
	quit(0 if failures.is_empty() else 1)
