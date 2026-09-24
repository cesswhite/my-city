extends RefCounted
const Layout = preload("res://scripts/world_layout.gd")
## Small local crowd: physical feet clearance, bounded rerouting, no provider calls.
const Navigation = preload("res://scripts/navigation.gd")
const CLEARANCE := Vector2(16, 14)
const RETRY_SECONDS := 0.35
const RECOVERY_SECONDS := 1.05
const YIELD_WAIT_SECONDS := 0.7
const PASSING_WAIT_SECONDS := 5.0
const MAX_RECOVERY_QUERIES := 12
var host: Control

func _init(owner: Control) -> void:
	host = owner

func people(resident: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for other: Dictionary in host.colony.active_residents():
		if other.id == resident.id or other.room != resident.room: continue
		result.append(host.position_of(other))
	return result

func can_step(from: Vector2, to: Vector2, room: String, occupied: Array[Vector2]) -> bool:
	if not Navigation._clear_segment(from, to, room): return false
	return Navigation.clear_people_segment(from, to, occupied, CLEARANCE)

func manual_step(resident: Dictionary, direction: Vector2, distance: float) -> Vector2:
	var point: Vector2 = host.position_of(resident)
	var magnitude: float = maxf(absf(direction.x), absf(direction.y))
	if not direction.is_finite() or magnitude <= 0.0 or not is_finite(distance): return point
	var heading: Vector2 = (direction / magnitude).normalized()
	var occupied: Array[Vector2] = people(resident)
	var remaining: float = minf(distance, Navigation.MAX_MANUAL_DISTANCE)
	while remaining > 0.00001:
		var step: Vector2 = heading * minf(1.0, remaining)
		var candidate: Vector2 = Navigation.move_direction(point, step, step.length(), resident.room)
		if can_step(point, candidate, resident.room, occupied): point = candidate
		else:
			var slid := false
			for axis in [Vector2(step.x, 0), Vector2(0, step.y)]:
				if axis.is_zero_approx(): continue
				if can_step(point, point + axis, resident.room, occupied):
					point += axis
					slid = true
			if not slid: break
		remaining -= step.length()
	return point

func recover_overlap(resident: Dictionary) -> void:
	if resident.id == "player" or resident.id in host.colony.conversation_holds or host.colony.is_sleeping(resident.id): return
	if host.colony.daily_state(resident.id).get("kind", "") == "speaking": return
	var point: Vector2 = host.position_of(resident)
	if point.distance_to(Vector2(resident.target[0], resident.target[1])) > 0.1: return
	var should_yield := false
	for other: Dictionary in host.colony.active_residents():
		if other.id == resident.id or other.room != resident.room: continue
		if ((point - host.position_of(other)) / CLEARANCE).length_squared() >= 0.9999: continue
		# Keep the player and held actors still; stable priority avoids pushing both.
		if other.id == "player" or other.id in host.colony.conversation_holds or str(other.id) < str(resident.id): should_yield = true
	if not should_yield: return
	var occupied: Array[Vector2] = people(resident)
	for radius in [18.0, 24.0, 36.0]:
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]:
			var candidate: Vector2 = point + direction * radius
			if not Navigation.is_walkable(candidate, resident.room): continue
			var clear := true
			for other in occupied:
				if ((candidate - other) / CLEARANCE).length_squared() < 1.15: clear = false
			if not clear or Navigation.route(point, candidate, resident.room).is_empty(): continue
			resident.target = [candidate.x, candidate.y]
			host.paths.erase(resident.id)
			return

func route(resident: Dictionary, target: Vector2, occupied: Array[Vector2]) -> Array[Vector2]:
	return Navigation.route_around_people(host.position_of(resident), target, resident.room, occupied, CLEARANCE)

func can_recover(resident: Dictionary) -> bool:
	if not is_instance_valid(host) or resident.is_empty(): return false
	var id: String = str(resident.get("id", ""))
	if id.is_empty() or id in host.colony.conversation_holds or host.colony.is_sleeping(id): return false
	if host.colony.daily_state(id).get("kind", "") == "speaking": return false
	if id == "player":
		if not host.colony.player_autonomy: return false
		if host.seating != null and host.seating.is_seated(): return false
	return true

func passing_priority(resident: Dictionary) -> String:
	# Opposing walkers must not continuously mirror each other's detours. Stable
	# ID ordering chooses one waiter; neither position nor destination is changed.
	if not can_recover(resident): return ""
	var point: Vector2 = host.position_of(resident)
	var heading := Vector2(resident.target[0], resident.target[1]) - point
	if heading.length() < 2.0: return ""
	heading = heading.normalized()
	for other: Dictionary in host.colony.active_residents():
		if str(other.id) >= str(resident.id) or other.room != resident.room or not can_recover(other): continue
		var offset: Vector2 = host.position_of(other) - point
		if offset.length() > 40.0 or offset.dot(heading) < 1.0: continue
		var other_heading: Vector2 = Vector2(other.target[0], other.target[1]) - host.position_of(other)
		if other_heading.length() < 2.0: continue
		if heading.dot(other_heading.normalized()) < -0.4: return str(other.id)
	return ""

func exit_waiter(resident: Dictionary) -> Dictionary:
	# A person outside gives way to somebody leaving that very house. People in
	# different rooms are deliberately absent from normal local crowd avoidance.
	if not can_recover(resident) or not Layout.is_outdoor(resident.get("room", "street")) or resident.get("travel_intent", "") != "casa": return {}
	var home: String = str(resident.get("home_id", ""))
	if not host.colony.HOME_DOORS.has(home) or resident.room != Layout.home_area(home): return {}
	var door := Vector2(host.colony.HOME_DOORS[home][0], host.colony.HOME_DOORS[home][1])
	var target := Vector2(resident.target[0], resident.target[1])
	if host.position_of(resident).distance_to(door) > 1.0 or target.distance_to(door) > 0.5: return {}
	var exit_point := Vector2(host.colony.ROOM_EXIT[0], host.colony.ROOM_EXIT[1])
	var entry := Vector2(host.colony.ROOM_ENTRY[0], host.colony.ROOM_ENTRY[1])
	for other: Dictionary in host.colony.active_residents():
		if other.id == resident.id or other.get("room", "street") != home: continue
		if other.id in host.colony.conversation_holds or host.colony.is_sleeping(other.id): continue
		if host.colony.daily_state(other.id).get("kind", "") == "speaking": continue
		var other_target := Vector2(other.target[0], other.target[1])
		var position: Vector2 = host.position_of(other)
		if other_target.distance_to(exit_point) > 0.5 or position.distance_to(exit_point) > 1.0: continue
		if other.id == "player" and not host.colony.player_autonomy and not host.pending_exit: continue
		if ((position - entry) / CLEARANCE).length_squared() < 1.0: return other
	return {}

func recovery_route(resident: Dictionary, target: Vector2, occupied: Array[Vector2], portal_yield: bool = false) -> Array[Vector2]:
	# Return an optional temporary waypoint route. The caller owns its lifetime;
	# this query never changes a person's position, real goal, intent or activity.
	if not can_recover(resident) or not target.is_finite(): return []
	var origin: Vector2 = host.position_of(resident)
	var room: String = str(resident.get("room", "street"))
	if not Navigation.is_walkable(origin, room): return []
	var door: Vector2 = target
	if portal_yield:
		var home: String = str(resident.get("home_id", ""))
		if not Layout.is_outdoor(room) or not host.colony.HOME_DOORS.has(home): return []
		door = Vector2(host.colony.HOME_DOORS[home][0], host.colony.HOME_DOORS[home][1])
	var heading: Vector2 = (target-origin).normalized() if origin.distance_to(target) > 0.01 else Vector2.UP
	var lateral := Vector2(-heading.y,heading.x)
	var directions: Array[Vector2] = [lateral,-lateral,-heading,(-heading+lateral).normalized(),(-heading-lateral).normalized(),heading,Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]
	if portal_yield:
		directions = [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2.UP]
	var queried := 0
	var visited: Dictionary = {}
	for radius: float in [20.0,28.0,36.0]:
		var radius_queries := 0
		for direction: Vector2 in directions:
			var candidate: Vector2 = (origin+direction*radius).round()
			if visited.has(candidate): continue
			visited[candidate] = true
			if not Navigation.is_walkable(candidate,room): continue
			if portal_yield and ((candidate-door)/CLEARANCE).length_squared() < 1.25: continue
			var spaced := true
			for person: Vector2 in occupied:
				if not person.is_finite() or ((candidate-person)/CLEARANCE).length_squared() < 1.15:
					spaced = false
					break
			if not spaced: continue
			queried += 1
			radius_queries += 1
			var points: Array[Vector2] = Navigation.route_around_people(origin,candidate,room,occupied,CLEARANCE)
			if not points.is_empty() and points[-1].distance_to(candidate) <= 0.01:
				var previous: Vector2 = origin
				var length := 0.0
				var valid := true
				for point: Vector2 in points:
					length += previous.distance_to(point)
					if point.distance_to(origin) > radius+12.0 or not can_step(previous,point,room,occupied):
						valid = false
						break
					previous = point
				if valid and length <= radius*3.0: return points
			if queried >= MAX_RECOVERY_QUERIES: return []
			# Reserve searches at every radius rather than exhausting the budget on
			# close candidates separated from the actor by the same piece of furniture.
			if radius_queries >= 4: break
	return []
