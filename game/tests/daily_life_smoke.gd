extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures: Array[String] = []
var walked_samples := 0
var invalid_samples := 0
var save_path := "user://daily_life_%d.json" % OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func fixture():
	var world = Colony.new()
	world.save_path = save_path
	world.setup(false, true)
	return world

func move_world(world) -> void:
	for resident: Dictionary in world.residents:
		if (resident.id == "player" and not world.player_autonomy) or resident.id in world.conversation_holds or world.is_sleeping(resident.id): continue
		var from := Layout.point(resident.pos)
		var target := Layout.point(resident.target)
		var path: Array[Vector2] = Navigation.route(from, target, resident.room)
		var remaining := 120.0 # Four real seconds at the walking speed, per five-minute world tick.
		for waypoint in path:
			while from.distance_to(waypoint) > 0.01 and remaining > 0:
				var distance: float = minf(3.0, minf(from.distance_to(waypoint), remaining))
				from = from.move_toward(waypoint, distance)
				walked_samples += 1
				if not Navigation.is_walkable(from, resident.room): invalid_samples += 1
				remaining -= distance
			if remaining <= 0: break
		resident.pos = [from.x, from.y]
		if from.distance_to(target) <= 0.1: world.on_arrival(resident.id)

func task_world():
	var world = fixture()
	world.minute = 600
	world.tick(false)
	for _tick in range(8):
		move_world(world)
		world.tick(false)
	return world

func run() -> void:
	var world = task_world()
	var mateo: Dictionary = world.get_resident("mateo")
	var state: Dictionary = world.daily_state("mateo")
	expect(state.has("action") and state.has("kind") and state.has("label") and state.has("until") and state.has("source"), "daily state exposes concrete action, kind, label, duration boundary and source")
	expect(state.kind in ["working", "leisure", "walking"], "Mateo develops short activities within his workshop block")
	var player_pos: Array = world.get_resident("player").pos.duplicate()
	var player_target: Array = world.get_resident("player").target.duplicate()
	var memories := 0
	for resident in world.residents: memories += resident.memories.size()
	for _tick in range(8):
		move_world(world)
		world.tick(false)
	var later_memories := 0
	for resident in world.residents: later_memories += resident.memories.size()
	expect(memories == later_memories, "tasks alone do not append memories on each tick")
	expect(world.get_resident("player").pos == player_pos and world.get_resident("player").target == player_target, "daily activities do not control a manual player")
	expect(world.progression_state().quests.is_empty() and world.get_resident("player").skills.is_empty(), "ambient chores do not award the player's learning or materials")
	# A route selected by a decision survives ordinary task updates, then expires.
	world = fixture()
	world.minute = 610
	world.tick(false)
	expect(world.apply_decision("mateo", "huerto"), "an explicit decision can override the workshop block")
	var chosen: Array = world.get_resident("mateo").target.duplicate()
	for _tick in range(3): world.tick(false)
	expect(world.get_resident("mateo").target == chosen and world.daily_state("mateo").source == "decision", "task scheduling respects the decision's temporary priority")
	for _tick in range(6): world.tick(false)
	var workshop_target: Vector2 = Layout.point(world.get_resident("mateo").target)
	expect(world.get_resident("mateo").travel_intent == "taller" and workshop_target.distance_to(Layout.point(Colony.PLACES.taller)) < Colony.MAX_DISTANCE and Navigation.is_walkable(workshop_target, Layout.place_area("taller")) and world.daily_state("mateo").source == "routine", "expired decision returns to a walkable slot within the still-current scheduled venue")
	world.apply_decision("mateo", "huerto")
	world.minute = 790
	world.tick(false)
	expect(world.daily_state("mateo").source == "routine" and world.get_resident("mateo").routine_place == "plaza", "a new schedule block takes precedence over an old decision")
	world = fixture()
	world.minute = 600
	world.tick(false)
	for id in ["ines", "mateo", "lupita"]:
		var resident: Dictionary = world.get_resident(id)
		resident.room = "street"
		resident.pos = Colony.PLACES.cafe.duplicate()
		resident.target = resident.pos.duplicate()
		world.apply_decision(id, "cafe")
	world.tick(false)
	var separated := true
	var arrivals := ["ines", "mateo", "lupita"]
	for first_index in range(arrivals.size()):
		var destination: Vector2 = Layout.point(world.get_resident(arrivals[first_index]).target)
		separated = separated and Navigation.is_walkable(destination, "street")
		for second_index in range(first_index + 1, arrivals.size()):
			separated = separated and destination.distance_to(Layout.point(world.get_resident(arrivals[second_index]).target)) >= 18.0
	expect(separated, "simultaneous café tasks choose separate physical destinations when space is available")
	world = fixture()
	world.minute = 600
	world.tick(false)
	mateo = world.get_resident("mateo")
	var bed: Vector2 = Layout.stand_at("bed", "mateo")
	mateo.room = "mateo"
	mateo.pos = [bed.x, bed.y]
	mateo.target = mateo.pos.duplicate()
	world.apply_decision("mateo", "descansar")
	world.tick(false)
	world.tick(false)
	expect(world.is_sleeping("mateo") and int(mateo.sleep.until) - world.minute == 30, "a temporary rest decision starts one thirty-minute nap at the actual bed")
	for _tick in range(6): world.tick(false)
	expect(not world.is_sleeping("mateo") and mateo.target == Colony.ROOM_EXIT, "a completed nap resumes the schedule through the physical exit")
	world.tick(false)
	expect(not world.is_sleeping("mateo") and world.daily_state("mateo").source == "routine", "the expired rest priority does not restart the nap")
	# Real completed dialogue has a bounded visible speaking state.
	world = fixture()
	world.minute = 650
	world.tick(false)
	var cesar: Dictionary = world.get_resident("cesar")
	var lupita: Dictionary = world.get_resident("lupita")
	cesar.room = Layout.place_area("plaza")
	lupita.room = cesar.room
	cesar.erase("travel_route")
	lupita.erase("travel_route")
	cesar.pos = [236.0, 210.0]
	lupita.pos = [250.0, 210.0]
	cesar.target = [268.0, 210.0]
	lupita.target = [272.0, 242.0]
	cesar.travel_intent = "plaza"
	lupita.travel_intent = "plaza"
	var cesar_goal: Array = cesar.target.duplicate()
	var lupita_goal: Array = lupita.target.duplicate()
	var first: String = world.converse("cesar", "lupita")
	expect(not first.is_empty() and world.daily_state("cesar").kind == "speaking", "a local exchange creates a brief speaking state")
	expect(cesar.target == cesar.pos and lupita.target == lupita.pos, "local speaking pauses both physical routes")
	expect(not world.social_available("cesar") and not world.social_available("lupita"), "speaking and cooldown exclude another automatic conversation")
	world.tick(false)
	expect(cesar.target == cesar_goal and lupita.target == lupita_goal, "the speaking interval restores both interrupted goals")
	expect(not cesar.activity.begins_with("Conversando") and world.daily_state("cesar").kind != "speaking", "the activity label does not stay stuck on Conversando")
	cesar.pos = [236.0, 210.0]
	lupita.pos = [250.0, 210.0]
	var second: String = world.converse("cesar", "lupita")
	expect(second != first and not first.contains(cesar.goal + "\n"), "local lines vary with the role, current activity and exchange history")
	expect(cesar.memories.back().origin == "conversación local predeterminada" and cesar.memories.size() == 2, "only completed local exchanges write honestly sourced memories")
	# Held tasks keep remaining work and can accept a new scheduled goal for host restoration.
	world = task_world()
	mateo = world.get_resident("mateo")
	for _tick in range(15):
		if world.daily_state("mateo").kind == "working": break
		move_world(world)
		world.tick(false)
	state = world.daily_state("mateo")
	expect(state.kind == "working", "fixture reaches an actual work task before testing a hold")
	var remaining: int = int(state.until) - world.minute
	var held_target: Array = mateo.target.duplicate()
	world.conversation_holds.assign(["mateo", "player"])
	for _tick in range(3): world.tick(false)
	expect(world.daily_state("mateo").kind == "speaking" and mateo.target == held_target, "a held task cannot launch another route")
	world.conversation_holds.clear()
	expect(int(world.daily_state("mateo").until) - world.minute == remaining, "work duration excludes time reserved for a conversation")
	world.tick(false)
	expect(not mateo.activity.begins_with("Conversando"), "releasing a hold resumes a valid activity label")
	# Two full days use physical navigation, never assigning pos directly to a destination.
	world = fixture()
	var actions: Dictionary = {}
	var nights: Dictionary = {}
	var conversations: Dictionary = {}
	var active_ticks: Dictionary = {}
	var world_memory_max := 0
	for resident in world.residents:
		if resident.id == "player": continue
		actions[resident.id] = {}
		nights[resident.id] = {}
		active_ticks[resident.id] = 0
	for _tick in range(288 * 2):
		move_world(world)
		world.tick(true)
		for resident in world.residents:
			if resident.id == "player": continue
			state = world.daily_state(resident.id)
			if state.kind in ["working", "eating", "leisure"]:
				actions[resident.id][state.action] = true
				active_ticks[resident.id] += 1
			if world.is_sleeping(resident.id):
				nights[resident.id][int(resident.sleep.started / 1440)] = true
				if not world.Rest.at_bed(resident): invalid_samples += 1
			world_memory_max = maxi(world_memory_max, resident.memories.size())
	expect(invalid_samples == 0 and walked_samples > 1000, "all physical samples and sleeping positions respect navigation and bed geometry")
	for id in actions:
		var count := 0
		for memory in world.get_resident(id).memories:
			if memory.kind == "conversacion": count += 1
		conversations[id] = count
		expect(actions[id].size() >= 2 and int(active_ticks[id]) > 20, id + " performs multiple arrived tasks across the two days")
		expect(nights[id].size() >= 2, id + " physically sleeps in bed on both nights")
		expect(count >= 2, id + " takes part in at least two completed encounters across the two days")
	print("DAILY COVERAGE: tasks=", actions, " active_ticks=", active_ticks, " conversations=", conversations, " walked_samples=", walked_samples)
	var total_chats := 0
	for value in conversations.values(): total_chats += int(value)
	expect(total_chats > 0 and world_memory_max < 40, "daily opportunities create bounded real encounters rather than one memory per tick")
	expect(world.get_resident("player").memories.is_empty(), "two days of neighbor life never invent a conversation with the manual player")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	expect(world.save_game(), "physical daily life and sleeping state form a valid save")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(not payload.has("daily_life") and not payload.residents[0].has("daily_state"), "transient task scheduler does not bloat the save schema")
	var reopened = fixture()
	expect(reopened.load_game() and reopened.daily_state("cesar").has("kind"), "loading reconstructs a usable daily state without a saved scheduler")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("DAILY LIFE: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
