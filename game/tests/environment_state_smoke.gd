extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Catalog = preload("res://scripts/environmental_catalog.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []
var paths: Array[String] = []

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: "+message)
	else: failures.append(message); push_error("FAIL: "+message)
func fixture(developed: bool = true):
	var world = Colony.new()
	world.save_path = "user://environment_state_%d_%d.json" % [OS.get_process_id(),paths.size()]
	paths.append(world.save_path)
	world.setup(false,developed)
	world.settlement_jobs.autonomous_enabled = false
	return world
func place(world, room: String, point: Vector2) -> void:
	var player: Dictionary = world.get_resident("player")
	player.room = room
	player.pos = [point.x,point.y]
	player.target = player.pos.duplicate()
	player.travel_intent = ""
	player.erase("travel_route")
func motion(world, before: Vector2, after: Vector2, room: String = "gardens") -> bool:
	place(world,room,after)
	return world.environment.record_motion(room,before,after)
func cell_for(world, id: String) -> Dictionary:
	for cell: Dictionary in world.environment.view().cropcells:
		if cell.id == id: return cell
	return {}
func trample(world, cell: Dictionary, times: int) -> void:
	var outside: Vector2 = cell.rect.position + Vector2(7,-4)
	var inside: Vector2 = cell.rect.position + Vector2(7,2)
	for _step in range(times):
		motion(world,outside,inside)
		motion(world,inside,outside)
func mature(world) -> void:
	world.settlement.state.plots.north_bed = {"status":"growing","planted_at":world.minute-180,"tended":true}
func corrupt(world, change: Callable, label: String) -> void:
	var data: Dictionary = world.environment.snapshot()
	change.call(data)
	expect(not world.environment.validate(data,world.minute),label)
func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()

func run() -> void:
	var world = fixture()
	var environment = world.environment
	expect(Catalog.crop_cells().size() == 16 and Catalog.tree_sites().size() == 3 and Catalog.fruit_trees().size() == 3,"catalog has exactly sixteen crop cells and bounded tree/fruit sites")
	for tree: Dictionary in Catalog.tree_sites():
		expect(Layout.bounds(tree.room).encloses(tree.footprint) and Navigation.is_walkable(tree.at,tree.room),"new wild tree root starts on legal clear ground: "+tree.id)
	for tree: Dictionary in Catalog.fruit_trees():
		expect(Navigation.is_walkable(tree.at,tree.room),"fallen fruit is on reachable ground: "+tree.id)
		var clear := true
		var fruit_rect := Rect2(tree.at-Vector2(4,9),Vector2(8,9))
		for obstacle: Rect2 in Layout.obstacles(tree.room):
			if fruit_rect.intersects(obstacle): clear = false
		expect(clear,"fruit sprite clears solid props: "+tree.id)
	var initial: Dictionary = environment.snapshot()
	for _read in range(20): environment.view(); environment.snapshot()
	expect(initial == environment.snapshot(),"repeated views are pure and never roll fruit")
	var copy: Dictionary = environment.snapshot(); copy.households.player = {"watered":{},"curtains":{}}
	expect(not environment.snapshot().households.has("player"),"snapshot does not alias persistent state")
	var minute_before: int = world.minute
	world.tick(false)
	expect(environment.view().minute == minute_before+5,"Colony tick advances environment using the same five game minutes")
	mature(world)
	var first: Dictionary = Catalog.crop_cells()[0]
	trample(world,first,1)
	var once: Dictionary = environment.snapshot()
	var inside: Vector2 = first.rect.position+Vector2(7,2)
	for _frame in range(100): motion(world,inside,inside)
	expect(environment.snapshot() == once,"standing on a crop cannot create damage")
	trample(world,first,1)
	expect(not cell_for(world,first.id).bent,"two real entries do not bend a crop")
	trample(world,first,1)
	expect(cell_for(world,first.id).bent and cell_for(world,first.id).harvestable,"three entries bend a mature crop without erasing its harvest")
	trample(world,first,2)
	expect(cell_for(world,first.id).destroyed and cell_for(world,first.id).stage == 0 and not cell_for(world,first.id).harvestable,"five entries remove the plant and its harvest eligibility")
	expect(environment.harvest_outputs("north_bed",{"verduras":8}) == {"verduras":7},"harvest counts actual mature cells and excludes the destroyed plant")
	expect(world.save_game(),"active crop damage saves against the matching existing planting")
	var damage_loaded = fixture(); damage_loaded.save_path = world.save_path
	expect(damage_loaded.load_game() and damage_loaded.environment.snapshot().cells == environment.snapshot().cells,"loading preserves the actual five footsteps and destruction time")
	damage_loaded.minute += 45; damage_loaded.environment.tick()
	expect(cell_for(damage_loaded,first.id).stage == 1 and not cell_for(damage_loaded,first.id).harvestable,"a restored destroyed plant regrows from its saved time without maturing early")
	var damaged_at: int = world.minute
	for row: Array in [[44,0],[45,1],[119,1],[120,2],[240,2],[359,2],[360,3]]:
		world.minute = damaged_at+row[0]
		environment.tick()
		expect(cell_for(world,first.id).stage == row[1],"crop regrows at game minute +%d without a reward" % row[0])
	expect(environment.harvest_outputs("north_bed",{"verduras":8}) == {"verduras":8},"fully recovered plant can be harvested again")
	trample(world,first,3)
	world.minute += 31; environment.tick()
	expect(not cell_for(world,first.id).bent,"entry pressure expires after thirty game minutes")
	environment.reset_plot("north_bed")
	motion(world,first.rect.position-Vector2(100,0),inside)
	expect(environment.snapshot().cells.is_empty(),"teleport/load recovery is not counted as trampling")
	motion(world,inside,first.rect.position+Vector2(7,-4))
	motion(world,first.rect.position+Vector2(7,-4),inside)
	var entry_count: int = environment.state.cells[first.id].entries.size()
	motion(world,inside,first.rect.position+Vector2(7,-1))
	motion(world,first.rect.position+Vector2(7,-1),inside)
	expect(environment.state.cells[first.id].entries.size() == entry_count,"two-pixel exit hysteresis prevents border jitter from adding entries")
	world.conversation_holds.append("player")
	var held: Dictionary = environment.snapshot()
	trample(world,first,5)
	expect(environment.snapshot() == held,"held participants cannot trample via a movement callback")
	world.conversation_holds.clear()
	# Canonical completed settlement work, not a second crop inventory.
	world = fixture(); environment = world.environment; mature(world)
	trample(world,first,5)
	var spec: Dictionary = world.settlement.task_spec("harvest:north_bed")
	expect(world.settlement_jobs.request("player","harvest:north_bed").ok,"partial crop still offers real harvesting work")
	place(world,spec.room,Layout.point(spec.at))
	var job: Dictionary = world.settlement.state.jobs.player
	job.phase = "working"; job.worked = true; job.progress = job.required
	var before_stock: int = int(world.progression_state().inventory.get("verduras",0))
	expect(world.settlement.complete_task(job).ok,"canonical completed harvest settles successfully")
	expect(int(world.progression_state().inventory.get("verduras",0))-before_stock == int(floor(float(spec.outputs.verduras)*7.0/8.0)),"only undamaged mature plants contribute to real settlement output")
	expect(environment.snapshot().cells.is_empty() and world.settlement.state.plots.north_bed.status == "empty","harvest clears environmental markers with the existing plot")
	expect(not world.settlement.complete_task(job).ok,"harvest retry cannot mint another payout")
	world.settlement.state.jobs.erase("player")
	world._progression._add_items({"fibra":1,"compost":1})
	expect(world.settlement_jobs.request("player","plant:north_bed").ok,"existing planting workflow can be repeated")
	spec = world.settlement.task_spec("plant:north_bed")
	place(world,spec.room,Layout.point(spec.at)); job = world.settlement.state.jobs.player
	job.phase = "working"; job.worked = true; job.progress = job.required
	expect(world.settlement.complete_task(job).ok and environment.harvest_outputs("north_bed",{"verduras":8}).is_empty(),"new planting is immature and cannot be harvested immediately")
	world.settlement.state.jobs.erase("player")
	# Fixed daily rolls: tests inject only the local pure RNG seam.
	world = fixture(false); environment = world.environment
	environment._fruit_roll = func(_tree,_day): return 1
	world.minute += 1440; environment.tick()
	expect(environment.state.fruit.size() == 1 and environment.state.trees.size() == 1,"closed forest and gardens neither roll fruit nor grow trees")
	var fruit: Dictionary = environment.view().fruit[0]
	place(world,fruit.room,fruit.at+Vector2(40,0))
	var funds: Dictionary = world.progression_state()
	expect(not environment.collect_fruit(fruit.tree_id).ok,"remote fruit pickup is rejected")
	place(world,fruit.room,fruit.at)
	var player: Dictionary = world.get_resident("player")
	player.energy = 37.5; player.target = [fruit.at.x+30,fruit.at.y]
	expect(environment.collect_fruit(fruit.tree_id).ok and player.energy == 38.5,"walking past an apple adds exactly one energy immediately")
	expect(not environment.collect_fruit(fruit.tree_id).ok and player.energy == 38.5 and world.progression_state() == funds,"collection is idempotent and never touches inventory or coins")
	var collected: Dictionary = environment.snapshot()
	environment.tick(); environment.view(); environment.tick()
	expect(environment.snapshot() == collected,"same-day ticks cannot reroll a collected fruit")
	world.minute += 1440
	environment.tick()
	place(world,fruit.room,fruit.at); player.energy = 0
	var no_energy: Dictionary = environment.snapshot()
	expect(not environment.collect_fruit(fruit.tree_id).ok and environment.snapshot() == no_energy,"fruit cannot bypass pending exhaustion at zero energy")
	player.energy = 99.5
	expect(environment.collect_fruit(fruit.tree_id).ok and player.energy == 100,"ordinary apple respects the energy cap")
	world.minute += 1440*8; environment.tick()
	expect(environment.view().fruit.size() == 1 and int(environment.state.fruit[fruit.tree_id].day) == int(world.minute/1440),"skipped days do not accumulate fruit")
	var fresh: Dictionary = environment.view().fruit[0]
	world.minute = int(fresh.expires_at)
	expect(environment.view().fruit.is_empty() and not environment.collect_fruit(fruit.tree_id).ok,"daily fruit expires without clicks generating a replacement")
	# Exactly one golden opportunity per playthrough, even if ignored.
	world = fixture(); environment = world.environment
	environment.state.fruit.clear(); environment.state.golden.clear()
	environment._fruit_roll = func(_tree,_day): return 0
	environment.tick()
	expect(environment.view().fruit.size() == 1 and environment.view().fruit[0].kind == "golden","simultaneous successful rolls still yield only one golden apple")
	fruit = environment.view().fruit[0]
	place(world,fruit.room,fruit.at); player = world.get_resident("player"); player.energy = 20
	expect(environment.collect_fruit(fruit.tree_id).ok and player.energy == 100,"golden fruit restores energy up to the existing cap")
	world.minute += 1440; environment.tick()
	expect(environment.view().fruit.is_empty(),"golden fruit cannot recur on another day or tree")
	expect(environment.validate(environment.snapshot(),world.minute),"golden lifetime record remains valid after the daily record changes")
	# Save/load retains both environmental state and immediate energy, without reapplying effects.
	expect(world.save_game(),"environment and existing settlement save together atomically")
	var loaded = fixture(); loaded.save_path = world.save_path
	var loaded_ok: bool = loaded.load_game()
	expect(loaded_ok and loaded.environment.snapshot() == environment.snapshot() and loaded.player_energy() == 100,"reload preserves rolls and energy without paying fruit twice")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world.save_path))
	payload.erase("environment"); write_json(world.save_path,payload)
	expect(loaded.load_game() and loaded.environment.validate(loaded.environment.snapshot(),loaded.minute),"legacy saves acquire environment state without resetting residents or settlement")
	# Each regeneration site follows game time and never produces automatic inventory.
	world = fixture(); environment = world.environment
	var forest_project: Dictionary = world.settlement.catalog.projects.forest_path
	world.settlement.state.projects.forest_path = {"status":"completed","progress":float(forest_project.minutes)}
	world.settlement.state.areas.append("forest")
	world.settlement.state.discoveries.append(forest_project.discovery)
	world.settlement.state.revision += 1
	environment.tick()
	expect(environment.view().treeplants.size() == 3,"opening the forest starts both additional regeneration sites on that day")
	var began: int = world.minute; funds = world.progression_state()
	for index: int in range(Catalog.TREE_STAGES.size()):
		world.minute = began+Catalog.TREE_STAGES[index]; environment.tick()
		var all_same := true
		for tree: Dictionary in environment.view().treeplants:
			if tree.stage != index: all_same = false
		expect(all_same,"all three wild tree sites reach stage %d from persistent planting time" % index)
	expect(world.progression_state() == funds,"wild regrowth never awards automatic resources")
	# Household object authority and scoped observation.
	for room: String in ["player","lupita"]:
		var at: Vector2 = Catalog.stand_for(room,"window")
		expect(Navigation.is_walkable(at,room),"canonical window approach is reachable in "+room)
		place(world,room,at)
		player = world.get_resident("player"); player.energy = 70
		expect(environment.house_action(room,"window","curtains").ok and environment.state.households[room].curtains.window,"a visited house window closes independently: "+room)
		expect(environment.house_action(room,"window","curtains").ok and not environment.state.households[room].curtains.window,"same physical action opens the same curtain: "+room)
		place(world,room,Catalog.stand_for(room,"plant"))
		var prior_energy: float = player.energy
		expect(environment.house_action(room,"plant","water").ok,"reachable household plant can be watered: "+room)
		expect(not environment.house_action(room,"plant","water").ok and player.energy == prior_energy,"watering cannot farm stats or repeated actions: "+room)
	place(world,"player",Catalog.stand_for("player","window"))
	expect(not environment.house_action("lupita","window","curtains").ok,"matching coordinates do not allow acting in another house")
	expect(not environment.house_action("player","window","water").ok,"an action cannot target the wrong object kind")
	place(world,"lupita",Catalog.stand_for("lupita","photo"))
	var owner_memories: int = world.get_resident("lupita").memories.size()
	var player_memories: int = player.memories.size()
	expect(not environment.house_action("lupita","photo","page:private_diary").ok,"unknown or private pages cannot be observed")
	expect(environment.house_action("lupita","photo","page:photograph").ok and player.memories.size() == player_memories+1,"explicit page inspection records only that visible page")
	environment.house_action("lupita","photo","page:photograph")
	expect(player.memories.size() == player_memories+1 and world.get_resident("lupita").memories.size() == owner_memories,"rereading deduplicates and does not give the absent owner a memory")
	expect(environment.validate(environment.snapshot(),world.minute),"complete environmental state satisfies bounded schema")
	corrupt(world,func(d): d.seed = NAN,"nonfinite seed is rejected")
	corrupt(world,func(d): d.households.player.watered.window = world.minute,"watering ledger rejects a window")
	corrupt(world,func(d): d.households.player.curtains.window = 1,"curtain value must be boolean")
	corrupt(world,func(d): d.trees["invented"] = {"planted_at":0},"unknown regeneration site is rejected")
	corrupt(world,func(d): d.trees[d.trees.keys()[0]].planted_at = world.minute+1,"future growth timestamps are rejected")
	corrupt(world,func(d): d.fruit[d.fruit.keys()[0]].kind = "coins","fruit cannot carry invented rewards")
	corrupt(world,func(d): d.cells["north_bed:0"] = {"planted_at":0,"entries":[0,1,2,3,4,5],"destroyed_at":-1},"crop entry history is bounded")
	corrupt(world,func(d): d.cells["north_bed:0"] = {"planted_at":0,"entries":[world.minute+1],"destroyed_at":-1},"future footsteps are rejected")
	expect(world.save_game(),"household and observed-page changes persist with the rest of the world")
	loaded = fixture(); loaded.save_path = world.save_path
	loaded_ok = loaded.load_game()
	expect(loaded_ok and loaded.environment.snapshot().households == environment.snapshot().households,"reload retains watering and each curtain state")
	payload = JSON.parse_string(FileAccess.get_file_as_string(world.save_path))
	payload.environment.seed = -1; write_json(world.save_path,payload)
	var bytes: String = FileAccess.get_file_as_string(world.save_path)
	expect(not loaded.load_game() and not loaded.save_game() and FileAccess.get_file_as_string(world.save_path) == bytes,"malformed environment is rejected without overwriting the original save")
	for path: String in paths:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("ENVIRONMENT STATE: %d/%d" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
