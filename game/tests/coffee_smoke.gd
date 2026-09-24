extends SceneTree
## Isolated money, inventory, location and persistence checks. No provider calls.
const Colony = preload("res://scripts/colony.gd")
const Seats = preload("res://scripts/seating.gd")
const Layout = preload("res://scripts/world_layout.gd")
var checks := 0
var failures := 0
var path := "user://test_coffee_%d.json" % OS.get_process_id()

func _init(): call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func fresh():
	var world = Colony.new()
	world.save_path = path
	world.setup(false, true)
	return world

func at_seat(world, seat: Dictionary) -> void:
	world.set_player_autonomy(false)
	world.wake_resident("player")
	world.conversation_holds.clear()
	var player: Dictionary = world.get_resident("player")
	player.room = "street"
	player.pos = [seat.stand_at.x, seat.stand_at.y]
	player.target = player.pos.duplicate()
	player.travel_intent = ""

func clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))

func write_save(content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func run() -> void:
	clean()
	var cafes: Array[Dictionary] = []
	var other_seats: Array[Dictionary] = []
	for seat: Dictionary in Seats.seats():
		if seat.prop_key in ["cafe_table_left", "cafe_table_right"]: cafes.append(seat)
		else: other_seats.append(seat)
	check(cafes.size() == 4 and Colony.COFFEE_PRICE == 3, "cuatro asientos de café comparten precio canónico de tres monedas")
	if cafes.size() != 4:
		quit(1)
		return
	for seat: Dictionary in cafes:
		var seated = fresh()
		at_seat(seated,seat)
		seated.get_resident("player").energy = 37.5
		var before: String = JSON.stringify(seated.progression_state())
		var offer: Dictionary = seated.coffee_offer(seat.id)
		check(offer.ok and offer.price == 3 and offer.coins == 20 and not offer.has_coffee and JSON.stringify(seated.progression_state()) == before and seated.get_resident("player").memories.is_empty(), "consultar oferta es sólo lectura: " + seat.id)
		check(not seated.drink_coffee(seat.id).ok and seated.progression_state().coins == 20 and seated.player_energy() == 37.5, "sin taza no hay consumo, cargo ni energía: " + seat.id)
		check(seated.order_coffee(seat.id).ok and seated.progression_state().coins == 17 and seated.progression_state().inventory.taza_cafe == 1 and seated.player_energy() == 37.5, "compra entrega exactamente una taza por tres monedas sin aumentar energía: " + seat.id)
		var paid: String = JSON.stringify(seated.progression_state())
		check(not seated.order_coffee(seat.id).ok and JSON.stringify(seated.progression_state()) == paid and seated.get_resident("player").memories.size() == 1, "doble clic de compra no cobra ni duplica taza: " + seat.id)
		check(seated.drink_coffee(seat.id).ok and not seated.progression_state().inventory.has("taza_cafe") and seated.progression_state().coins == 17 and seated.player_energy() == 42.5, "beber consume la taza y suma cinco puntos de energía sin otro cargo: " + seat.id)
		var memory: Dictionary = seated.get_resident("player").memories.back()
		check(memory.kind == "consumo" and memory.item_id == "taza_cafe" and memory.seat_id == seat.id and memory.participants == ["player"] and seated.get_resident("ines").memories.is_empty(), "consumo verificado queda sólo como experiencia propia: " + seat.id)
		check(not seated.drink_coffee(seat.id).ok and seated.get_resident("player").memories.size() == 2 and seated.progression_state().coins == 17 and seated.player_energy() == 42.5, "repetir beber no inventa otra taza, experiencia ni energía: " + seat.id)
		check(seated.order_coffee(seat.id).ok and seated.progression_state().coins == 14 and seated.progression_state().inventory.taza_cafe == 1 and seated.player_energy() == 42.5, "puede pedir otra taza después de consumir sin recibir energía por comprar: " + seat.id)
		check(seated.drink_coffee(seat.id).ok and seated.player_energy() == 47.5 and not seated.progression_state().inventory.has("taza_cafe"), "una segunda taza bebida suma otros cinco puntos exactos: " + seat.id)

	for initial_energy in [95.0,98.75,100.0]:
		var capped = fresh()
		at_seat(capped,cafes[0])
		capped.get_resident("player").energy = initial_energy
		check(capped.order_coffee(cafes[0].id).ok and capped.player_energy() == initial_energy, "comprar cerca del máximo no cambia energía: %.2f" % initial_energy)
		check(capped.drink_coffee(cafes[0].id).ok and capped.player_energy() == 100.0 and not capped.progression_state().inventory.has("taza_cafe"), "consumir nunca supera cien y consume la taza incluso al máximo: %.2f" % initial_energy)
	var depleted = fresh()
	at_seat(depleted,cafes[0])
	depleted.order_coffee(cafes[0].id)
	depleted.get_resident("player").energy = 0.0
	var pending: Dictionary = depleted.progression_state()
	var pending_memories: Array = depleted.get_resident("player").memories.duplicate(true)
	check(not depleted.is_exhausted() and not depleted.drink_coffee(cafes[0].id).ok and depleted.progression_state() == pending and depleted.get_resident("player").memories == pending_memories and depleted.player_energy() == 0.0, "café no consume taza ni evita el agotamiento cuando energía llega a cero antes de iniciar el sueño")

	var world = fresh()
	var selected: Dictionary = cafes[0]
	at_seat(world,selected)
	check(world.progression_item_name("taza_cafe") == "Taza de café", "inventario usa nombre de taza del catálogo")
	var appears_in_shop := false
	for item: Dictionary in world.shop_catalog():
		if item.id == "taza_cafe": appears_in_shop = true
	check(not appears_in_shop and not world.buy_item("taza_cafe").ok, "café no aparece como material comprable en tienda de encargos")
	for seat: Dictionary in other_seats:
		at_seat(world,seat)
		check(not world.coffee_offer(seat.id).ok and not world.order_coffee(seat.id).ok and world.progression_state().coins == 20, "banco o fuente no vende café: " + seat.id)
	at_seat(world,selected)
	check(not world.order_coffee("").ok and not world.order_coffee("cafe_table_fake").ok and world.progression_state().coins == 20, "asiento vacío o inventado no autoriza compra")
	var player: Dictionary = world.get_resident("player")
	player.pos[0] += 1.0
	check(not world.order_coffee(selected.id).ok, "llegada pendiente no permite cobrar")
	at_seat(world,selected)
	player.target[1] += 1.0
	check(not world.order_coffee(selected.id).ok, "intención de levantarse invalida pedido aunque aún esté cerca")
	at_seat(world,selected)
	player.room = "player"
	check(not world.order_coffee(selected.id).ok, "mismas coordenadas en casa no equivalen al café")
	at_seat(world,selected)
	world.player_autonomy = true
	check(not world.order_coffee(selected.id).ok, "modo observar no gasta monedas por la API manual")
	at_seat(world,selected)
	world.conversation_holds.append("player")
	check(not world.order_coffee(selected.id).ok, "conversación reservada no cuenta como postura sentada disponible")
	at_seat(world,selected)
	player.pos[0] = NAN
	check(not world.order_coffee(selected.id).ok, "coordenada no finita no supera validación de distancia")
	at_seat(world,selected)
	player.room = "player"
	var bed: Vector2 = Layout.stand_at("bed","player")
	player.pos = [bed.x,bed.y]
	player.target = player.pos.duplicate()
	check(world.start_sleep("player",60) and not world.order_coffee(selected.id).ok, "jugador realmente dormido no compra")
	check(world.progression_state().coins == 20 and not world.progression_state().inventory.has("taza_cafe") and player.memories.is_empty(), "rechazos físicos dejan dinero, inventario y recuerdos intactos")
	at_seat(world,selected)
	world._progression.state.coins = 2
	check(not world.coffee_offer(selected.id).ok and not world.order_coffee(selected.id).ok and world.progression_state().coins == 2, "saldo insuficiente no cobra parcialmente")
	world._progression.state.coins = 3
	player.energy = 64.125
	check(world.order_coffee(selected.id).ok and world.progression_state().coins == 0 and world.coffee_offer(selected.id).ok and world.coffee_offer(selected.id).has_coffee and world.player_energy() == 64.125, "saldo exacto compra y permite beber con cero monedas sin energía anticipada")
	var detached: Dictionary = world.progression_state()
	detached.inventory.taza_cafe = 99
	check(world.progression_state().inventory.taza_cafe == 1, "lectura de inventario no comparte estado mutable")
	check(world.save_game(), "guarda moneda gastada y taza pendiente antes de cerrar")
	var saved: String = FileAccess.get_file_as_string(path)
	var restored = fresh()
	check(restored.load_game() and restored.progression_state().coins == 0 and restored.progression_state().inventory.taza_cafe == 1 and restored.player_energy() == 64.125, "carga conserva pago, taza y energía previa sin restaurar la postura UI")
	var restored_player: Dictionary = restored.get_resident("player")
	restored_player.target[0] += 2.0
	check(not restored.drink_coffee(selected.id).ok and restored.progression_state().inventory.taza_cafe == 1 and restored.player_energy() == 64.125, "caminar no permite consumir taza ni ganar energía")
	at_seat(restored,cafes[3])
	check(restored.drink_coffee(cafes[3].id).ok and restored.progression_state().coins == 0 and restored.player_energy() == 69.125, "taza pendiente en otro asiento suma cinco puntos incluso con cero monedas")
	check(restored.save_game(), "consumo y ausencia de taza también persisten")
	var empty = fresh()
	check(empty.load_game() and not empty.progression_state().inventory.has("taza_cafe") and empty.get_resident("player").memories.back().kind == "consumo" and empty.player_energy() == 69.125, "reinicio conserva energía exacta sin recrear taza ni sumar otra vez")
	for amount in [2, -1, 0.5]:
		var invalid: Dictionary = JSON.parse_string(saved)
		invalid.progression.inventory.taza_cafe = amount
		write_save(JSON.stringify(invalid))
		check(not restored.load_game() and not restored.save_game(), "cantidad inválida de tazas no carga ni sobrescribe archivo corrupto")
	write_save(saved)
	var legacy: Dictionary = JSON.parse_string(saved)
	legacy.progression.inventory.erase("taza_cafe")
	write_save(JSON.stringify(legacy))
	check(restored.load_game() and not restored.progression_state().inventory.has("taza_cafe"), "guardado anterior sin nueva entrada de inventario sigue siendo compatible")
	clean()
	print("COFFEE: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
