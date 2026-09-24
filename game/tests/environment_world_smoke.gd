extends SceneTree
## Actual movement, picking, light and HUD integration; isolated state, no providers or saves.
const Main = preload("res://scripts/main.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Catalog = preload("res://scripts/environmental_catalog.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Targets = preload("res://scripts/world_interactions.gd")
const Lighting = preload("res://scripts/world_lighting.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)
	else: print("PASS: "+text)
func place(scene, room: String, at: Vector2) -> void:
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = room; player.pos = [at.x,at.y]; player.target = player.pos.duplicate()
	player.travel_intent = ""; player.erase("travel_route")
	scene.paths.erase("player"); scene.update_room()
func crop(scene, id: String) -> Dictionary:
	for item: Dictionary in scene.colony.environment.view().cropcells:
		if item.id == id: return item
	return {}
func roll_apple(_tree: String, _day: int) -> int: return 1

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args(): quit(1); return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,540)
	root.add_child(viewport)
	var scene := Main.new()
	scene.managed_by_shell = true; scene.start_new_game = true
	scene.colony.save_path = "user://unused_environment_world_%d.json" % OS.get_process_id()
	viewport.add_child(scene)
	scene.set_process(false); scene.save_allowed = false; scene.use_jev = false
	scene.service_token = ""; scene.service_url = ""
	scene.colony.setup(false,true); scene.colony.settlement_jobs.autonomous_enabled = false
	for person: Dictionary in scene.colony.residents:
		if person.id != "player": person.room = person.id; person.pos = [236,252]; person.target = person.pos.duplicate()
	scene.paused = false; scene.controls_active = true
	scene.colony.settlement.state.plots.north_bed = {"status":"growing","planted_at":scene.colony.minute-180,"tended":true}
	place(scene,"gardens",Vector2(351,254))
	var cell: Dictionary = Catalog.crop_cells()[0]
	expect(Navigation.is_walkable(cell.rect.get_center(),"gardens"),"ground crop rows are physically walkable")
	for cycle in range(5):
		for _step in range(3): scene.move_player_keyboard(Vector2.UP,0.1)
		for _step in range(3): scene.move_player_keyboard(Vector2.DOWN,0.1)
		if cycle == 2: expect(crop(scene,cell.id).bent,"third real keyboard crossing bends one plant")
	expect(crop(scene,cell.id).stage == 0,"fifth real keyboard crossing leaves soil")
	expect(not crop(scene,"north_bed:1").destroyed,"neighboring plant remains intact")
	var held: Dictionary = scene.colony.environment.snapshot()
	for _frame in range(60): scene.move_player_keyboard(Vector2.ZERO,0.016)
	expect(scene.colony.environment.snapshot() == held,"idle frames create no additional damage")
	var now: int = scene.colony.minute
	scene.colony.minute += 45; scene.colony.environment.tick(); scene.update_room()
	var sprouts: Array = Sprites.scenery_objects("gardens",scene.home_project_state()).filter(func(o: Dictionary): return o.get("key","") == "environment_crop_"+str(cell.id))
	expect(crop(scene,cell.id).stage == 1 and sprouts.size() == 1,"regrown sprout returns through the actual scene state")
	place(scene,"homes",Vector2(200,200)); place(scene,"gardens",Vector2(351,254))
	expect(crop(scene,cell.id).stage == 1,"changing blocks never resets a damaged plant")
	# Click walking crosses the second cell through the same authoritative hook.
	place(scene,"gardens",Vector2(365,254))
	var player: Dictionary = scene.colony.get_resident("player")
	player.target = [365,237]
	for _step in range(12): scene.move_resident(player,0.05)
	expect(scene.colony.environment.state.cells.has("north_bed:1"),"click-path movement also records physical crop entry")
	# A dropped apple is distinct from the nearby economic resource node.
	scene.colony.environment._fruit_roll = roll_apple
	scene.colony.minute = (int(scene.colony.minute/1440)+1)*1440+480
	scene.colony.environment.tick()
	var fruit: Dictionary = Catalog.fruit_tree("homes_apple")
	place(scene,fruit.room,fruit.at+Vector2(0,9))
	player.energy = 50.0
	scene.move_player_keyboard(Vector2.UP,0.1)
	expect(is_equal_approx(float(player.energy),51.0),"walking over fallen fruit restores exactly one energy point")
	var wallet: Dictionary = scene.colony.progression_state().duplicate(true)
	for _step in range(3): scene.move_player_keyboard(Vector2.DOWN,0.1); scene.move_player_keyboard(Vector2.UP,0.1)
	expect(is_equal_approx(float(player.energy),51.0) and scene.colony.progression_state() == wallet,"walking back cannot repeat fruit or create saleable items")
	var second_fruit: Dictionary = Catalog.fruit_tree("garden_apple")
	place(scene,second_fruit.room,second_fruit.at+Vector2(0,16))
	var fruit_targets: Array = Targets._targets(second_fruit.room,scene.home_project_state()).filter(func(t: Dictionary): return t.kind == "fruit" and t.item.fruit_id == "garden_apple")
	expect(fruit_targets.size() == 1,"fallen fruit also has a physical click target")
	if fruit_targets.size() == 1:
		scene.activate_world_interaction(fruit_targets[0])
		for _step in range(60):
			scene.move_resident(player,0.02)
			if float(player.energy) > 51.0: break
		expect(is_equal_approx(float(player.energy),52.0) and scene.pending_item.is_empty(),"walking onto a clicked apple completes its intent before arrival can repeat it")
		scene.resolve_player_arrival()
		expect(scene.colony.progression_state() == wallet,"click collection has the same bounded reward as walking")
	# Cursor + keyboard targets stay tied to each actual window and physical approach.
	place(scene,"player",Catalog.stand_for("player","window"))
	player.target = player.pos.duplicate()
	var windows: Array = Targets._targets("player",scene.home_project_state()).filter(func(t: Dictionary): return t.kind == "environment" and t.item.prop_key == "window")
	expect(windows.size() == 1 and windows[0].item.stand_at == Catalog.stand_for("player","window"),"new controls share one valid physical target")
	var before_lights: Array = Lighting.emitters("player",scene.home_project_state()).filter(func(e: Dictionary): return e.kind == "inside_window")
	var closed: Dictionary = scene.colony.environment.house_action("player","window","curtains")
	var after_lights: Array = Lighting.emitters("player",scene.home_project_state()).filter(func(e: Dictionary): return e.kind == "inside_window")
	expect(closed.ok and after_lights.size() == before_lights.size()-1,"closing one curtain removes only its own daylight beam")
	var reopened: Dictionary = scene.colony.environment.house_action("player","window","curtains")
	expect(reopened.ok and Lighting.emitters("player",scene.home_project_state()).filter(func(e: Dictionary): return e.kind == "inside_window").size() == before_lights.size(),"reopening restores its daylight without a cache reset")
	# Growth cannot close a trunk around a person already standing on its root.
	var site: Dictionary = Catalog.tree_sites()[0]
	scene.colony.environment.state.trees[site.id] = {"planted_at":scene.colony.minute-1440}
	place(scene,site.room,site.at-Vector2(0,2))
	expect(Navigation.is_walkable(scene.position_of(player),site.room),"an occupied new trunk never traps the player")
	place(scene,site.room,site.at+Vector2(18,12))
	expect(not Navigation.is_walkable(site.at-Vector2(0,2),site.room),"grown trunk becomes solid after the root clears")
	# The same regenerated tree remains present, with no layout or home rewrite.
	expect(Sprites.scenery_objects(site.room,scene.home_project_state()).any(func(o: Dictionary): return o.get("key","") == "environment_tree_"+str(site.id)),"the persistent tree has a native object in the real scene")
	expect(scene.colony.minute > now and scene.save_allowed == false and scene.service_token.is_empty(),"fixture never touches a real save or provider")
	scene.queue_free(); await process_frame; viewport.queue_free(); await process_frame
	Navigation.set_environment_obstacles({})
	print("ENVIRONMENT WORLD %d/%d" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
