extends RefCounted
## Voluntary player posture. The saved position remains on the accessible approach.
const Seats = preload("res://scripts/seating.gd")
const Navigation = preload("res://scripts/navigation.gd")
var host: Control
var active_id := ""
var pending_id := ""

func _init(owner: Control) -> void:
	host = owner

func is_seated() -> bool:
	return not active_id.is_empty()

func active_seat() -> Dictionary:
	return Seats.get_seat(active_id) if is_seated() else {}

func _changed() -> void:
	if is_instance_valid(host.actors): host.actors.queue_redraw()
	if is_instance_valid(host.world_labels): host.world_labels.queue_redraw()
	host.update_hint()
	if host.cafe_service != null: host.cafe_service.refresh()

func stand(stop_movement: bool = true) -> bool:
	var had_seat: bool = is_seated() or not pending_id.is_empty()
	active_id = ""
	pending_id = ""
	if not had_seat: return false
	var player: Dictionary = host.colony.get_resident("player")
	if stop_movement:
		player.target = player.pos.duplicate()
		player.travel_intent = ""
		host.paths.erase("player")
	if str(player.get("activity", "")).begins_with("Sentado") or str(player.get("activity", "")).begins_with("Buscando asiento"):
		player.activity = "Bajo tu control"
	_changed()
	return true

func request(id: String) -> bool:
	if host.sync_exhaustion(): return false
	var seat: Dictionary = Seats.get_seat(id)
	var player: Dictionary = host.colony.get_resident("player")
	if seat.is_empty() or player.room != seat.get("room", "street") or host._menu_suspended: return false
	if active_id == id:
		stand()
		return true
	var route: Array = Navigation.route(host.position_of(player), seat.stand_at, player.room)
	if route.is_empty() or route[-1].distance_to(seat.stand_at) > 0.5:
		host.message("No puedes llegar a ese asiento desde aquí.")
		return false
	host.take_control()
	host.hide_inspector()
	host.riding_bicycle = false
	host.hud.sync_actions()
	pending_id = id
	player.target = [seat.stand_at.x, seat.stand_at.y]
	player.travel_intent = ""
	player.activity = "Buscando asiento"
	host.paused = false
	host.paths.erase("player")
	update()
	_changed()
	return true

func update() -> void:
	if active_id.is_empty() and pending_id.is_empty(): return
	var player: Dictionary = host.colony.get_resident("player")
	if host.colony.player_autonomy or host.colony.is_sleeping("player") or host.riding_bicycle or not host.chat_partner_id.is_empty():
		stand(false)
		return
	var seat: Dictionary = Seats.get_seat(active_id if is_seated() else pending_id)
	if seat.is_empty() or player.room != seat.get("room", "street"):
		stand(false)
		return
	var position: Vector2 = host.position_of(player)
	var target := Vector2(float(player.target[0]), float(player.target[1]))
	if target.distance_to(seat.stand_at) > 0.75:
		stand(false)
		return
	if is_seated():
		if position.distance_to(seat.stand_at) > 0.75:
			stand(false)
			return
		player.activity = "Sentado · " + str(seat.title)
		return
	if host.paused or host._menu_suspended or position.distance_to(seat.stand_at) > 0.5: return
	# Only snap the subpixel arrival tolerance, never walk through the furniture.
	player.pos = [seat.stand_at.x, seat.stand_at.y]
	player.target = player.pos.duplicate()
	player.activity = "Sentado · " + str(seat.title)
	host.facing.player = seat.facing
	host.keyboard_walking = false
	host.paths.erase("player")
	active_id = pending_id
	pending_id = ""
	_changed()
