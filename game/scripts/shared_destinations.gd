extends RefCounted
## Deterministic standing places for shared activities. Assignment only, never movement.
const Navigation = preload("res://scripts/navigation.gd")
const Layout = preload("res://scripts/world_layout.gd")
const SEPARATION := 18.0
const PLACE_RADIUS := 44.0 # Venue interactions require less than Colony.MAX_DISTANCE (45).
const COLUMNS := [0, -1, 1, -2, 2, -3, 3]
const ROWS := [0, 1, -1, 2, -2]
static var _rows: Dictionary = {}

static func _candidate_rows(place: String) -> Array:
	if _rows.has(place): return _rows[place]
	var places: Dictionary = Layout.data().places
	if not places.has(place): return []
	var base: Vector2 = Layout.point(places[place])
	var room: String = Layout.place_area(place)
	var result: Array = []
	if place == "huerto":
		# One worker at the far end; visitors stand outside the planting beds.
		# No stationary goal may occupy this garden's single-file access aisle.
		for offsets in [[Vector2(36, 0)], [Vector2(0, -36), Vector2(-18, -36), Vector2(18, -36)], [Vector2(0, 36), Vector2(-18, 36), Vector2(18, 36)]]:
			var garden_row: Array[Vector2] = []
			for offset: Vector2 in offsets:
				var candidate: Vector2 = base + offset
				if Navigation.is_walkable(candidate, room) and not Navigation.route(base, candidate, room).is_empty(): garden_row.append(candidate)
			if not garden_row.is_empty(): result.append(garden_row)
		_rows[place] = result
		return result
	for row_offset in ROWS:
		var row: Array[Vector2] = []
		for column_offset in COLUMNS:
			var candidate: Vector2 = base + Vector2(column_offset, row_offset) * SEPARATION
			if candidate.distance_to(base) > PLACE_RADIUS: continue
			if Navigation.is_walkable(candidate, room) and not Navigation.route(base, candidate, room).is_empty(): row.append(candidate)
		if not row.is_empty(): result.append(row)
	_rows[place] = result
	return result

static func candidates(place: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for row in _candidate_rows(place): result.append_array(row)
	return result

static func choose(world, resident: Dictionary, place: String, phase: int = 0) -> Vector2:
	var rows: Array = _candidate_rows(place)
	if rows.is_empty(): return Layout.point(resident.pos)
	var room: String = Layout.place_area(place)
	var rank: int = world.RESIDENT_IDS.find(str(resident.id))
	if rank < 0: rank = 0
	var fallback: Vector2 = Layout.point(resident.pos)
	var best_clearance_squared := -1.0
	# Prefer a lateral row before adding depth; the ID/phase order prevents everyone
	# requesting the middle first, while checking live positions and assigned goals.
	for row in rows:
		var first: int = posmod(rank + phase * 2, row.size())
		for index in range(row.size()):
			var candidate: Vector2 = row[(first + index) % row.size()]
			if place == "huerto" and resident.id != "cesar" and is_equal_approx(candidate.y, float(Layout.data().places.huerto[1])): continue
			var clearance_squared := INF
			for other: Dictionary in world.residents:
				if other.id == resident.id or not world.is_present(other.id): continue
				if other.get("room", "street") == room:
					clearance_squared = minf(clearance_squared, candidate.distance_squared_to(Layout.point(other.pos)))
					clearance_squared = minf(clearance_squared, candidate.distance_squared_to(Layout.point(other.target)))
				var journey: Dictionary = other.get("travel_route", {})
				if journey.get("room", "") == room:
					clearance_squared = minf(clearance_squared, candidate.distance_squared_to(Layout.point(journey.position)))
			if clearance_squared >= SEPARATION * SEPARATION: return candidate
			if clearance_squared > best_clearance_squared:
				best_clearance_squared = clearance_squared
				fallback = candidate
	# A crowded place still gets the best available valid point, never an obstacle.
	return fallback
