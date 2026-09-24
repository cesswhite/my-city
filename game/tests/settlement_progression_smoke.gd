extends "res://tests/settlement_smoke.gd"
var days_used := 0
func stock(id: String) -> int: return int(world.progression_state().inventory.get(id,0))
func walk(room: String, at: Array) -> bool:
	return world.travel_to("player",room,Layout.point(at)) and move_to_goal("player")
func restore_energy() -> bool:
	if world.player_energy() > 24: return true
	return advance_day()
func advance_day() -> bool:
	days_used += 1
	if days_used > 30: return false
	return next_day()
func gather_day() -> bool:
	for id in world.settlement.catalog.nodes:
		while world.settlement.offer("gather:"+id).ok:
			if not restore_energy() or not do_task("gather:"+id): return false
	return true
func sell_surplus(needed: Dictionary, target_coins: int) -> bool:
	if int(world.progression_state().coins) >= target_coins: return true
	var shop: Dictionary=world._progression.catalog.shop
	if not walk(shop.room,shop.pos): return false
	for row in world.settlement.market():
		var reserve: int=int(needed.get(row.id,0))
		var quantity: int=mini(int(row.remaining),maxi(0,int(row.owned)-reserve))
		if quantity>0 and not world.settlement.sell(row.id,quantity).ok: return false
		if int(world.progression_state().coins)>=target_coins: return true
	return false
func materials_for(project: Dictionary) -> bool:
	var needed: Dictionary=project.cost.items.duplicate()
	for day in range(30):
		if not restore_energy() or not gather_day(): return false
		for id in ["tablones","compost"]:
			var recipe: String="boards" if id=="tablones" else "compost"
			while stock(id)<int(needed.get(id,0)) and world.settlement.offer("produce:"+recipe).ok:
				if not restore_energy() or not do_task("produce:"+recipe): return false
		var enough: bool=world._progression._has_items(needed)
		var funds: bool=sell_surplus(needed,int(project.cost.coins))
		if enough and funds: return true
		if not advance_day(): return false
	return false
func run():
	world=Colony.new();world.setup(false);world.settlement_jobs.autonomous_enabled=false
	for project_id in ["workbench","gardens_path","cesar_home","community_garden","workshops_path","mateo_home","atelier_path","alma_home","forest_path","storage_upgrade","garden_upgrade"]:
		var project: Dictionary=world.settlement.catalog.projects[project_id]
		if not str(project.discovery).is_empty():
			expect(restore_energy() and do_task("explore:"+str(project.discovery)),"exploración física previa: "+str(project_id))
		expect(materials_for(project),"economía renovable financia: "+str(project_id))
		if not world.settlement.offer("build:"+project_id).ok:
			expect(false,"obra preparada: "+str(project_id)+" "+str(world.settlement.offer("build:"+project_id)))
			break
		expect(restore_energy() and do_task("build:"+project_id),"obra presencial terminada: "+str(project_id))
		expect(world.settlement.validate(world.settlement.snapshot()),"estado válido después de "+str(project_id))
		if not str(project.arrival).is_empty():
			expect(world.is_present(project.arrival) and world.get_resident(project.arrival).room==project.area,"habitante llega a su calle: "+str(project.arrival))
			var save_path: String="user://settlement-progression-test.json"
			for suffix in ["",".bak",".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path+suffix))
			world.save_path=save_path
			expect(world.save_game(),"guarda desbloqueo y llegada: "+str(project.arrival))
			var loaded=Colony.new();loaded.setup(false);loaded.save_path=save_path
			expect(loaded.load_game() and loaded.active_residents().size()==world.active_residents().size(),"carga población sin duplicarla")
			world=loaded;world.settlement_jobs.autonomous_enabled=false
			for suffix in ["",".bak",".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path+suffix))
	if failures:
		print("PROGRESSION STOP: ",checks-failures,"/",checks," day ",days_used)
		quit(1);return
	# Persistent, productive crops need care before harvesting, and can be sown again.
	while stock("compost")<1:
		if not world.settlement.offer("produce:compost").ok: gather_day()
		expect(restore_energy() and do_task("produce:compost"),"prepara compost para cultivo")
	expect(restore_energy() and do_task("plant:north_bed"),"siembra materializa cultivo")
	expect(not world.settlement.offer("harvest:north_bed").ok,"no cosecha planta recién sembrada")
	expect(do_task("tend:north_bed"),"riega el bancal")
	for _step in range(40): world.tick(false)
	var vegetables: int=stock("verduras")
	expect(do_task("harvest:north_bed"),"cosecha tras crecimiento y cuidado")
	expect(stock("verduras")==vegetables+4,"mejorar huerto cambia rendimiento real")
	# Repeated community assistance can unlock a relationship-dependent community hall.
	for _day in range(10):
		if float(world.relationship_for("lupita","player").trust)>=40: break
		if not world._progression._has_items({"madera":2,"fibra":1}): gather_day()
		var neighbor: Dictionary=world.get_resident("lupita")
		if not Layout.is_outdoor(neighbor.room):
			# Let her morning routine physically leave before delivering.
			world._set_destination(neighbor,"plaza")
			move_to_goal("lupita")
		if walk(neighbor.room,neighbor.pos): world.settlement.deliver_order("welcome_supplies")
		if float(world.relationship_for("lupita","player").trust)<40: advance_day()
	var hall: Dictionary=world.settlement.catalog.projects.community_hall
	expect(materials_for(hall) and restore_energy() and do_task("build:community_hall"),"confianza y recursos permiten edificio comunitario")
	expect(world.settlement.stage().index==4,"todas las etapas alcanzables sin regalar recursos ni monedas")
	expect(world.active_residents().size()==6 and world.settlement.state.areas.size()==6,"pueblo creció a seis habitantes y seis zonas")
	expect(world.settlement.validate(world.settlement.snapshot()) and world._progression.validate(world.progression_state()),"estado final consistente con inventario y aprendizaje existente")
	print("PROGRESSION: %d/%d checks passed; %d días de descanso/renovación"%[checks-failures,checks,days_used])
	quit(1 if failures else 0)
