extends SceneTree
const Colony = preload("res://scripts/colony.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks: int = 0
var failed: int = 0
var test_path: String = "user://test_autonomy_%d.json" % OS.get_process_id()

func _init():
	call_deferred("_run")

func check(condition: bool, label: String):
	checks += 1
	if condition: print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func arrive(world):
	# Movement/navigation has separate integration tests. Here arrivals exercise room transitions.
	for resident in world.residents:
		if resident.id == "player" and not world.player_autonomy: continue
		arrive_one(world, resident)

func arrive_one(world, resident: Dictionary):
	for _leg in range(8):
		resident.pos = resident.target.duplicate()
		world.on_arrival(resident.id)
		if not resident.has("travel_route") and resident.pos == resident.target: break

func assigned_to(resident: Dictionary, place: String) -> bool:
	var final: Array = resident.get("travel_route", {}).get("position", resident.target)
	var target := Layout.point(final)
	var center := Vector2(float(Colony.PLACES[place][0]), float(Colony.PLACES[place][1]))
	return resident.travel_intent == place and target.distance_to(center) < Colony.MAX_DISTANCE and Navigation.is_walkable(target, Layout.place_area(place)) and Navigation.is_walkable(Layout.point(resident.target), resident.room)

func _run():
	clean()
	var manual = Colony.new()
	manual.setup(false, true)
	var player: Dictionary = manual.get_resident("player")
	var original_position: Array = player.pos.duplicate()
	var original_target: Array = player.target.duplicate()
	check(not manual.player_autonomy and not manual.decision_due("player"), "autonomía comienza desactivada")
	for index in range(288):
		manual.tick(true)
		arrive(manual)
	check(player.pos == original_position and player.target == original_target, "un día completo no mueve al jugador manual")
	check(player.memories.is_empty(), "NPC no inventan conversaciones con el jugador manual")
	check(player.skills.is_empty() and manual.progression_state().quests.is_empty(), "modo manual no concede aprendizajes ni encargos")
	player.pos = Colony.HOME_DOORS.player.duplicate()
	player.target = player.pos.duplicate()
	player.travel_intent = "casa"
	manual.on_arrival("player")
	check(player.room == Layout.home_area("player"), "llegada manual a puerta no entra sola")
	manual.minute = 480
	var progress_before: String = JSON.stringify(manual.progression_state())
	manual.set_player_autonomy(true)
	check(manual.player_autonomy, "activación explícita habilita vida propia")
	check(player.schedule.size() == 8 and player.routine_place == "cafe", "agenda personal de desayuno se aplica al activar")
	check(assigned_to(player, "cafe"), "agenda propone una plaza transitable dentro del café")
	check(not manual.decision_due("player"), "no pide IA mientras el jugador autónomo camina")
	arrive_one(manual, player)
	check(manual.decision_due("player"), "al llegar queda listo para decidir como un vecino")
	manual.apply_decision("player", "plaza")
	var decided_target: Array = player.target.duplicate()
	player.pos = player.target.duplicate()
	check(not manual.decision_due("player"), "decisión del jugador comparte enfriamiento de IA")
	manual.set_player_autonomy(true)
	check(player.target == decided_target and assigned_to(player, "plaza"), "activación repetida no reinicia una decisión en curso")
	manual.minute = 1380
	manual.tick(false)
	check(player.routine_place == "casa" and player.travel_route.room == Layout.home_area("player") and player.travel_route.position == Colony.HOME_DOORS.player, "noche envía al protagonista a casa por su área")
	arrive_one(manual, player)
	check(player.room == "player" and player.target == Colony.HOME_REST, "jugador autónomo cruza puerta propia y va a descansar")
	check(not manual.decision_due("player"), "durante descanso en casa no pide decisiones innecesarias")
	manual.get_resident("cesar").room = Layout.home_area("player")
	manual.get_resident("cesar").pos = Colony.HOME_DOORS.player.duplicate()
	var home_presence: Dictionary = manual.visit_context("cesar", "player")
	check(home_presence.occupied and home_presence.resident_id == "player", "jugador autónomo cuenta como habitante presente en su casa")
	# The visitor steps away after knocking; an occupied street portal correctly
	# blocks departure, which is covered separately by the crowd/portal tests.
	manual.get_resident("cesar").pos = [441.0, 184.0]
	manual.get_resident("cesar").target = manual.get_resident("cesar").pos.duplicate()
	player.pos = player.target.duplicate()
	manual.minute = 1440 + 480
	manual.tick(false)
	check(player.target == Colony.ROOM_EXIT, "desayuno siguiente pasa primero por salida interior")
	player.pos = player.target.duplicate()
	manual.on_arrival("player")
	check(player.room == Layout.home_area("player") and assigned_to(player, "cafe"), "al salir continúa por su área hacia una plaza del café")
	check(JSON.stringify(manual.progression_state()) == progress_before and player.skills.is_empty(), "activar y seguir horarios no otorga objetos, monedas, habilidades ni encargos")
	manual.set_player_autonomy(false)
	var stopped: Array = player.pos.duplicate()
	check(not manual.player_autonomy and player.target == stopped and player.travel_intent.is_empty(), "desactivar detiene movimiento e intención pendientes")
	check(not manual.decision_due("player"), "desactivar elimina elegibilidad de IA")
	for index in range(60):
		manual.tick(true)
		arrive(manual)
	check(player.pos == stopped and player.target == stopped, "rutinas posteriores respetan devolución de control")
	var community = Colony.new()
	community.save_path = test_path
	community.setup(false, true)
	community.set_player_autonomy(true)
	var visited: Dictionary = {}
	for index in range(288 * 14):
		community.tick(true)
		arrive(community)
		var actor: Dictionary = community.get_resident("player")
		visited[actor.get("routine_place", "")] = true
	var autonomous_player: Dictionary = community.get_resident("player")
	var conversations: int = 0
	var initiatives: int = 0
	for memory in autonomous_player.memories:
		if memory.kind == "conversacion": conversations += 1
		if memory.kind == "iniciativa": initiatives += 1
	check(visited.has("cafe") and visited.has("plaza") and visited.has("taller") and visited.has("huerto") and visited.has("casa"), "vida propia recorre todas las rutinas sin UI")
	check(conversations > 0 and not autonomous_player.known_people.is_empty(), "jugador autónomo conversa y forma recuerdos compartidos")
	check(initiatives > 0, "jugador autónomo participa en iniciativas de la colonia")
	check(community.progression_state().quests.is_empty() and autonomous_player.skills.is_empty(), "visitar taller durante semanas no equivale a completar aprendizaje")
	check(community.save_game(), "guarda biografía, horarios, posición y recuerdos de vida propia")
	var stored = JSON.parse_string(FileAccess.get_file_as_string(test_path))
	check(not stored.has("player_autonomy"), "partida no almacena autorización de autonomía")
	var memory_count: int = autonomous_player.memories.size()
	var saved_room: String = autonomous_player.room
	var saved_position: Array = autonomous_player.pos.duplicate()
	var reopened = Colony.new()
	reopened.save_path = test_path
	reopened.setup(true)
	var reopened_player: Dictionary = reopened.get_resident("player")
	check(not reopened.player_autonomy and not reopened.decision_due("player"), "abrir partida nunca reactiva autonomía ni consultas pagadas")
	check(reopened_player.room == saved_room and reopened_player.pos == saved_position, "recarga conserva habitación y posición")
	check(reopened_player.memories.size() == memory_count and reopened_player.schedule.size() == 8, "recarga conserva experiencias y agenda")
	check(reopened_player.target == reopened_player.pos and reopened_player.travel_intent.is_empty(), "recarga cancela trayecto automático anterior")
	reopened.set_player_autonomy(true)
	check(reopened.player_autonomy, "usuario puede volver a activar tras abrir")
	check(reopened.load_game() and not reopened.player_autonomy, "cargar sobre sesión activa devuelve control manual")
	var remote_mode = Colony.new()
	remote_mode.setup(false, true)
	remote_mode.set_player_autonomy(true)
	for index in range(288):
		remote_mode.tick(false)
		arrive(remote_mode)
	var remote_local_chat: int = 0
	for memory in remote_mode.get_resident("player").memories:
		if memory.kind == "conversacion": remote_local_chat += 1
	check(remote_local_chat == 0, "autonomía con Jev conserva horarios sin introducir conversaciones plantilla")
	clean()
	print("RESULT AUTONOMY: %d/%d comprobaciones correctas" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)

func clean():
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(test_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + suffix))
