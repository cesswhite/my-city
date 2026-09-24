extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures := 0
var world
func _initialize(): call_deferred("run")
func expect(value: bool, message: String):
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
	else: print("PASS: " + message)
func move_to_goal(id: String, limit: int = 18000) -> bool:
	var resident: Dictionary = world.get_resident(id)
	for step in range(limit):
		for other in world.active_residents():
			if other.id == id or world.is_sleeping(other.id) or other.id in world.conversation_holds: continue
			var location: Vector2 = Layout.point(other.pos)
			if location.distance_to(Layout.point(other.target)) > 1:
				var other_route: Array = Navigation.route(location,Layout.point(other.target),other.room)
				for point: Vector2 in other_route:
					if location.distance_to(point) > 0.1:
						location = location.move_toward(point,5.0)
						break
				other.pos = [location.x,location.y]
			world.on_arrival(other.id)
		var from: Vector2 = Layout.point(resident.pos)
		var target: Vector2 = Layout.point(resident.target)
		if from.distance_to(target) > 1.0:
			var route: Array = Navigation.route(from,target,resident.room)
			if route.is_empty(): return false
			var remaining: float = 5.0
			for point: Vector2 in route:
				var distance: float = from.distance_to(point)
				if distance <= remaining:
					from = point
					remaining -= distance
				else:
					from = from.move_toward(point,remaining)
					break
			resident.pos = [from.x,from.y]
		world.on_arrival(id)
		if not resident.has("travel_route") and Layout.point(resident.pos).distance_to(Layout.point(resident.target)) <= 2: return true
	return false
func do_task(task: String, worker: String = "player") -> bool:
	var response: Dictionary = world.settlement_jobs.request(worker,task)
	if not response.ok:
		print("CANNOT ",task,": ",response.message)
		return false
	for _step in range(150):
		if not world.settlement_jobs.busy(worker): return true
		if not move_to_goal(worker):
			print("MOVE FAIL ",task," ",world.get_resident(worker).room,world.get_resident(worker).pos,world.get_resident(worker).target,world.get_resident(worker).get("travel_route",{}))
			return false
		world.tick(false)
	print("TASK TIMEOUT ",task,world.settlement.state.jobs.get(worker,{}),world.get_resident(worker).pos)
	return false
func next_day() -> bool:
	var player: Dictionary = world.get_resident("player")
	if player.room != "player":
		if not world.travel_to("player", "homes", Layout.point(world.HOME_DOORS.player)): return false
		if not move_to_goal("player") or not world.enter_home("player","player"): return false
	var bed: Vector2 = Layout.stand_at("bed","player")
	if not world.travel_to("player","player",bed) or not move_to_goal("player"): return false
	if not world.start_sleep("player",480): return false
	for _step in range(96): world.tick(false)
	# A quiet day can pass normally; renewal remains tied to the simulation clock.
	while world.minute % 1440 < 480 or world.minute % 1440 > 485: world.tick(false)
	return true
func run():
	world = Colony.new()
	world.setup(false)
	world.settlement_jobs.autonomous_enabled = false
	expect(world.active_residents().size()==3,"nuevo pueblo sólo tiene jugador, Lupita e Inés")
	expect(world.progression_state().coins==8,"cartera inicial pequeña y única")
	expect(world.area_open("homes") and world.area_open("street") and not world.area_open("gardens"),"dos calles iniciales y expansión bloqueada")
	expect(not world.travel_to("player","gardens",Vector2(240,196)),"no cruza terreno cerrado por viaje")
	var player: Dictionary = world.get_resident("player")
	player.room="street"; player.pos=[244,76]; player.target=player.pos.duplicate()
	expect(not world.cross_exit("player","north"),"cruce directo también rechaza paso cerrado")
	expect(not world.enter_home("player","cesar"),"casa de futuro habitante no está abierta")
	expect(not world.start_apprenticeship("jardin_memoria").get("ok",false),"no acepta aprendizaje de mentor ausente")
	var before: Dictionary = world.progression_state()
	expect(not world.settlement.offer("build:cesar_home").ok,"no salta requisitos de obra")
	expect(world.progression_state()==before,"consultar obra no consume nada")
	expect(do_task("gather:fallen_branches"),"recoge madera caminando desde otra calle")
	expect(do_task("gather:loose_stones"),"recoge piedra físicamente")
	var saved_path := "user://settlement-smoke.json"
	for suffix in ["",".bak",".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path+suffix))
	world.save_path=saved_path
	var started: Dictionary = world.settlement_jobs.request("player","build:workbench")
	expect(started.ok,"financia mesa de trabajo una sola vez")
	var wallet: Dictionary = world.progression_state()
	expect(not world.settlement_jobs.request("player","build:workbench").ok and wallet==world.progression_state(),"doble clic no vuelve a cobrar")
	expect(move_to_goal("player"),"alcanza solar de trabajo")
	world.tick(false); world.tick(false)
	expect(float(world.settlement.state.projects.workbench.progress)>0,"avance presencial de obra")
	expect(world.save_game(),"guarda a mitad de construcción")
	var reloaded = Colony.new(); reloaded.save_path=saved_path; reloaded.setup(false)
	expect(reloaded.load_game(),"restaura trabajo, materiales y obra")
	expect(JSON.parse_string(JSON.stringify(reloaded.progression_state()))==JSON.parse_string(JSON.stringify(wallet)),"cargar no cobra ni reinicia inventario")
	world=reloaded; world.settlement_jobs.autonomous_enabled=false
	var job: Dictionary = world.settlement.state.jobs.player
	world.conversation_holds.assign(["player","lupita"])
	var progress: float = float(job.progress)
	world.tick(false)
	expect(float(job.progress)==progress,"hablar suspende el trabajo")
	world.conversation_holds.clear()
	for _step in range(6): world.tick(false)
	expect(world.settlement.building_ready("workbench"),"reanuda obra sin pagar otra vez")
	expect(not world.settlement.complete_task(job).ok,"recibo impide cobrar dos veces")
	expect(world.settlement.validate(world.settlement.snapshot()),"estado construido válido")
	expect(do_task("explore:survey_gardens"),"exploración confirma un camino existente")
	expect("survey_gardens" in world.settlement.state.discoveries,"descubrimiento persistente")
	expect(not world.settlement.offer("explore:survey_gardens").ok,"exploración no permite recompensa infinita")
	# Exercise conservation on cancellation and finite harvesting.
	expect(do_task("gather:wild_fibers"),"fibra renovable con propósito")
	var materials: Dictionary = world.progression_state().inventory
	expect(world.settlement_jobs.request("player","produce:compost").ok,"receta reserva insumos")
	world.settlement_jobs.cancel("player")
	expect(world.progression_state().inventory==materials,"cancelar devuelve exactamente los insumos")
	for _step in range(8):
		if not world.settlement.offer("gather:fallen_branches").ok: break
		expect(do_task("gather:fallen_branches"),"nodo permite sólo stock restante")
	expect(not world.settlement.offer("gather:fallen_branches").ok,"stock agotado hasta siguiente periodo")
	# Complete a genuine early request in person, earning both coins and trust.
	var lupita: Dictionary = world.get_resident("lupita")
	if not world._progression._has_items({"madera":2,"fibra":1}): expect(false,"materiales disponibles para pedido")
	player=world.get_resident("player")
	lupita.room=player.room; lupita.pos=[player.pos[0]+18,player.pos[1]]; lupita.target=lupita.pos.duplicate()
	var trust_before: float = float(world.relationship_for("lupita","player").trust)
	var coins_before: int = int(world.progression_state().coins)
	expect(world.settlement.deliver_order("welcome_supplies").ok,"pedido físico genera ingreso")
	expect(int(world.progression_state().coins)==coins_before+6 and float(world.relationship_for("lupita","player").trust)>trust_before,"ayuda une economía y confianza")
	expect(not world.settlement.deliver_order("welcome_supplies").ok,"pedido diario no se cobra dos veces")
	# A developed legacy save must keep all previous neighbors/roads and achievements.
	var legacy = Colony.new(); legacy.setup(false,true)
	legacy.save_path="user://settlement-legacy-smoke.json"
	for suffix in ["",".bak",".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy.save_path+suffix))
	expect(legacy.save_game(),"prepara partida antigua aislada")
	var payload: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(legacy.save_path));payload.erase("settlement")
	var file=FileAccess.open(legacy.save_path,FileAccess.WRITE);file.store_string(JSON.stringify(payload));file.close()
	var migration=Colony.new();migration.setup(false);migration.save_path=legacy.save_path
	expect(migration.load_game(),"migra partida previa sin estado de pueblo")
	expect(migration.active_residents().size()==6 and migration.area_open("atelier") and JSON.parse_string(JSON.stringify(migration.progression_state()))==JSON.parse_string(JSON.stringify(legacy.progression_state())),"migración conserva vecinos, terrenos y cartera")
	expect(not migration.area_open("forest"),"bosque nuevo aún necesita exploración")
	var malformed: Dictionary=world.settlement.snapshot();malformed.jobs.player={"id":"fake"}
	expect(not world.settlement.validate(malformed),"trabajo corrupto se rechaza")
	for path in [saved_path,legacy.save_path]:
		for suffix in ["",".bak",".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("SETTLEMENT: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
