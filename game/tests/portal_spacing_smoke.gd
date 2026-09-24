extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []

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
	world.setup(false, true)
	world.minute = 600
	for resident: Dictionary in world.residents:
		resident.room = resident.id
		resident.pos = Colony.HOME_REST.duplicate()
		resident.target = resident.pos.duplicate()
	return world

func run() -> void:
	var world = fixture()
	var visitor: Dictionary = world.get_resident("player")
	var owner: Dictionary = world.get_resident("lupita")
	visitor.room = Layout.home_area("lupita")
	visitor.pos = Colony.HOME_DOORS.lupita.duplicate()
	visitor.target = visitor.pos.duplicate()
	owner.pos = Colony.ROOM_ENTRY.duplicate()
	owner.target = owner.pos.duplicate()
	expect(world.apply_visit_decision("player", "lupita", true, "fixture local").allowed, "fixture obtiene permiso real de visita")
	var permission: Dictionary = world._visit_permissions["player:lupita"].duplicate(true)
	var original_residents: Array = world.residents.duplicate(true)
	var revisions: Dictionary = world._room_revisions.duplicate(true)
	var events: Array = world.events.duplicate(true)
	for attempt in range(3):
		expect(not world.enter_home("player", "lupita"), "entrada ocupada espera sin teletransportar, intento %d" % attempt)
	expect(world.residents == original_residents and world._room_revisions == revisions and world.events == events, "esperar no mueve personas ni añade recuerdos, eventos o revisiones")
	expect(world._visit_permissions["player:lupita"] == permission, "esperar conserva permiso y vencimiento originales")
	owner.pos = Colony.HOME_REST.duplicate()
	owner.target = owner.pos.duplicate()
	expect(world.enter_home("player", "lupita") and visitor.room == "lupita" and visitor.pos == Colony.ROOM_ENTRY, "reintento cruza al portal exacto cuando queda libre")
	expect(not world._visit_permissions.has("player:lupita"), "entrada exitosa consume el permiso una sola vez")
	# Collision is an ellipse, not an overly broad rectangular exclusion.
	owner.pos = [244.0, 259.0]
	expect(not world._entry_clear(Colony.ROOM_ENTRY, "lupita", "player"), "desplazamiento diagonal8×7 todavía ocupa el portal")
	owner.pos = [252.0, 252.0]
	expect(world._entry_clear(Colony.ROOM_ENTRY, "lupita", "player"), "borde horizontal16 permite pasar y excluye al propio actor")
	owner.pos = [236.0, 266.0]
	expect(world._entry_clear(Colony.ROOM_ENTRY, "lupita", "player"), "borde vertical14 permite pasar")
	owner.pos = [251.0, 265.0]
	expect(world._entry_clear(Colony.ROOM_ENTRY, "lupita", "player"), "diagonal fuera de la elipse no bloquea por su caja")
	owner.room = "cesar"
	owner.pos = Colony.ROOM_ENTRY.duplicate()
	expect(world._entry_clear(Colony.ROOM_ENTRY, "lupita", "player"), "una persona en otra habitación no bloquea el portal")
	# Manual player is deliberately ignored by visit-occupancy policy, but not by physics.
	world = fixture()
	visitor = world.get_resident("player")
	owner = world.get_resident("cesar")
	visitor.room = "cesar"
	visitor.pos = Colony.ROOM_ENTRY.duplicate()
	visitor.target = visitor.pos.duplicate()
	owner.room = Layout.home_area("cesar")
	owner.pos = Colony.HOME_DOORS.cesar.duplicate()
	owner.target = owner.pos.duplicate()
	owner.travel_intent = "casa"
	world.on_arrival("cesar")
	expect(owner.room == Layout.home_area("cesar") and owner.pos == Colony.HOME_DOORS.cesar and owner.travel_intent == "casa", "dueño espera si jugador manual ocupa el interior sin perder intención")
	visitor.pos = Colony.HOME_REST.duplicate()
	visitor.target = visitor.pos.duplicate()
	world.on_arrival("cesar")
	expect(owner.room == "cesar" and owner.pos == Colony.ROOM_ENTRY and owner.target == Colony.HOME_REST, "dueño reintenta y retoma descanso cuando jugador se aparta")
	# Outbound crossing must not place an NPC on top of somebody in the street.
	owner.pos = Colony.ROOM_EXIT.duplicate()
	owner.target = owner.pos.duplicate()
	owner.travel_intent = "cafe"
	visitor.room = Layout.home_area("cesar")
	visitor.pos = Colony.HOME_DOORS.cesar.duplicate()
	visitor.target = visitor.pos.duplicate()
	original_residents = world.residents.duplicate(true)
	revisions = world._room_revisions.duplicate(true)
	expect(not world.leave_home("cesar"), "salida ocupada en la calle espera")
	expect(world.residents == original_residents and world._room_revisions == revisions, "salida fallida conserva habitación, intención y posiciones")
	visitor.pos[0] += 16
	visitor.target = visitor.pos.duplicate()
	expect(world.leave_home("cesar") and owner.room == Layout.home_area("cesar") and owner.pos == Colony.HOME_DOORS.cesar, "salida despejada usa la puerta exacta sin mover a nadie")
	expect(owner.travel_intent == "cafe" and owner.travel_route.room == Layout.place_area("cafe") and Layout.point(owner.travel_route.position).distance_to(Layout.point(Colony.PLACES.cafe)) < Colony.MAX_DISTANCE and Navigation.is_walkable(Layout.point(owner.target), owner.room), "salida reanuda destino final y tramo local transitable")
	expect(visitor.pos[0] == Colony.HOME_DOORS.cesar[0] + 16, "cruce nunca empuja ni recoloca al ocupante")
	# A blocked attempt does not extend the lifetime of a previous invitation.
	world = fixture()
	visitor = world.get_resident("player")
	owner = world.get_resident("lupita")
	visitor.room = Layout.home_area("lupita")
	visitor.pos = Colony.HOME_DOORS.lupita.duplicate()
	owner.pos = Colony.ROOM_ENTRY.duplicate()
	world.apply_visit_decision("player", "lupita", true, "fixture local")
	world.enter_home("player", "lupita")
	world.minute += 16
	owner.pos = Colony.HOME_REST.duplicate()
	expect(not world.enter_home("player", "lupita") and visitor.room == Layout.home_area("lupita"), "permiso vencido continúa inválido aunque luego se despeje el portal")
	print("Portal spacing: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
