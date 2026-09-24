extends RefCounted
## Pixel-grid walking. Points describe feet, and furniture footprints include clearance.

const CELL: int = 4
const MAX_MANUAL_DISTANCE: float = 512.0
const HOMES = ["cesar", "lupita", "mateo", "ines", "alma", "player"]
const Layout = preload("res://scripts/world_layout.gd")
static var STREET_BOUNDS: Rect2 = Layout.bounds("street")
static var INTERIOR_BOUNDS: Rect2 = Layout.bounds("player")
static var STREET_OBSTACLES: Array[Rect2] = Layout.obstacles("street")
static var INTERIOR_OBSTACLES: Array[Rect2] = Layout.obstacles("player")
static var _grids: Dictionary = {}
static var _room_geometry: Dictionary = {}
static var _environment_obstacles: Dictionary = {}

static func set_environment_obstacles(value: Dictionary) -> void:
	# Only growth-stage changes invalidate routes; moving leaves never do.
	if _environment_obstacles == value: return
	var affected: Dictionary = _environment_obstacles.duplicate()
	for room in value: affected[room] = true
	_environment_obstacles = value.duplicate(true)
	for room in affected: _grids.erase(room)

static func door_positions(room: String = "") -> Dictionary:
	var result: Dictionary = Layout.door_positions()
	if room.is_empty(): return result
	for home in result.keys():
		if Layout.home_area(home) != room: result.erase(home)
	return result

static func home_spawns() -> Dictionary:
	var result: Dictionary = {}
	for home in HOMES:
		result[home] = Layout.point(Layout.data().entry)
	return result

static func recover_position(point: Vector2, room: String = "street") -> Vector2:
	## Load-time migration only. Normal route() deliberately never moves an invalid origin.
	if is_walkable(point, room):
		return point
	var fallback := Vector2(192, 230) if Layout.is_outdoor(room) else Layout.point(Layout.data().entry)
	# Room IDs are validated by the save loader. Avoid building a cache for bad IDs.
	if not Layout.is_outdoor(room) and room not in HOMES:
		return fallback
	if not point.is_finite():
		return fallback
	var grid: AStarGrid2D = _grid(room)
	var center := Vector2i(roundi(point.x / CELL), roundi(point.y / CELL))
	var nearest: Vector2 = fallback
	var best_distance: float = 64.001
	for y in range(maxi(center.y - 16, 0), mini(center.y + 17, 77)):
		for x in range(maxi(center.x - 16, 0), mini(center.x + 17, 120)):
			var cell := Vector2i(x, y)
			if grid.is_point_solid(cell):
				continue
			var candidate := Vector2(x * CELL, y * CELL)
			var distance: float = point.distance_to(candidate)
			if distance < best_distance:
				nearest = candidate
				best_distance = distance
	return nearest

static func is_walkable(point: Vector2, room: String = "street") -> bool:
	if not point.is_finite():
		return false
	if not Layout.is_outdoor(room) and room not in HOMES:
		return false
	# Each house has its own furniture plan. Cache its immutable shared geometry
	# once, because walking and path sampling query this for every small step.
	if not _room_geometry.has(room):
		_room_geometry[room] = {"bounds": Layout.bounds(room), "obstacles": Layout.obstacles(room)}
	var bounds: Rect2 = _room_geometry[room].bounds
	if not bounds.has_point(point):
		return false
	for obstacle: Rect2 in _environment_obstacles.get(room,[]):
		if obstacle.has_point(point): return false
	var obstacles: Array = _room_geometry[room].obstacles
	for obstacle: Rect2 in obstacles:
		if obstacle.has_point(point):
			return false
	return true

static func move_direction(from: Vector2, direction: Vector2, distance: float, room: String = "street") -> Vector2:
	## Manual movement only: no pathfinding, position recovery or portal transitions.
	if not from.is_finite() or not direction.is_finite() or not is_finite(distance) or distance <= 0.0:
		return from
	if not is_walkable(from, room):
		return from
	# Scale before normalizing, so very large finite inputs cannot overflow length().
	var magnitude: float = maxf(absf(direction.x), absf(direction.y))
	if magnitude <= 0.0:
		return from
	var heading: Vector2 = (direction / magnitude).normalized()
	var position: Vector2 = from
	# Bound frame work even for almost-parallel wall sliding with absurd time deltas.
	var remaining: float = minf(distance, MAX_MANUAL_DISTANCE)
	while remaining > 0.0:
		var step_length: float = minf(remaining, 1.0)
		var step: Vector2 = heading * step_length
		var next: Vector2 = position + step
		var along_x: Vector2 = position + Vector2(step.x, 0)
		var along_y: Vector2 = position + Vector2(0, step.y)
		var before: Vector2 = position
		# Checking both axis approaches prevents diagonals from cutting a solid corner.
		if is_walkable(next, room) and is_walkable(along_x, room) and is_walkable(along_y, room):
			position = next
		else:
			if is_walkable(along_x, room):
				position = along_x
			along_y = position + Vector2(0, step.y)
			if is_walkable(along_y, room):
				position = along_y
		if position == before:
			break
		remaining -= step_length
	return position

static func _grid(room: String) -> AStarGrid2D:
	var key: String = room
	if _grids.has(key):
		return _grids[key]
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, 120, 77)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for y in range(77):
		for x in range(120):
			var point := Vector2(x * CELL, y * CELL)
			# A small cross guarantees neighbouring links do not clip thin solids.
			var safe: bool = is_walkable(point, room)
			for margin in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				safe = safe and is_walkable(point + margin, room)
			grid.set_point_solid(Vector2i(x, y), not safe)
	_grids[key] = grid
	return grid

static func _clear_segment(from: Vector2, to: Vector2, room: String) -> bool:
	var samples: int = maxi(1, ceili(from.distance_to(to)))
	for index in range(samples + 1):
		if not is_walkable(from.lerp(to, float(index) / samples), room):
			return false
	return true

static func clear_people_segment(from: Vector2, to: Vector2, people: Array[Vector2], clearance: Vector2) -> bool:
	# Test the whole connector, not just its endpoints. Old overlapping positions
	# may separate gradually, but never pass deeper through the other person's body.
	if not from.is_finite() or not to.is_finite() or clearance.x <= 0.0 or clearance.y <= 0.0: return false
	var motion: Vector2 = (to - from) / clearance
	var length_squared: float = motion.length_squared()
	if length_squared < 0.000000001: return true
	for person: Vector2 in people:
		var relative: Vector2 = (from - person) / clearance
		var before: float = relative.length_squared()
		var approach: float = relative.dot(motion)
		if before < 0.9999:
			if approach < -0.000001: return false
		else:
			var nearest: float = clampf(-approach / length_squared, 0.0, 1.0)
			if (relative + motion * nearest).length_squared() < 0.9999: return false
	return true

static func _nearest_grid(point: Vector2, room: String, grid: AStarGrid2D, require_clear: bool, radius: int = 3, people: Array[Vector2] = [], clearance: Vector2 = Vector2.ONE, incoming: bool = false) -> Vector2i:
	var center := Vector2i(roundi(point.x / CELL), roundi(point.y / CELL))
	var closest := Vector2i(-1, -1)
	var best_distance: float = radius * CELL + 0.001
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):
				continue
			var candidate := Vector2(x * CELL, y * CELL)
			var distance: float = point.distance_to(candidate)
			if distance < best_distance and (not require_clear or _clear_segment(point, candidate, room)) and clear_people_segment(candidate if incoming else point, point if incoming else candidate, people, clearance):
				closest = cell
				best_distance = distance
	return closest

static func route(from: Vector2, to: Vector2, room: String = "street") -> Array[Vector2]:
	if not is_walkable(from, room) or not to.is_finite(): return []
	return _route_grid(from, to, room, _grid(room))

static func route_around_people(from: Vector2, to: Vector2, room: String, people: Array[Vector2], clearance: Vector2) -> Array[Vector2]:
	if not is_walkable(from, room) or not to.is_finite(): return []
	if people.is_empty(): return route(from, to, room)
	var grid: AStarGrid2D = _grid(room)
	var marked: Array[Vector2i] = []
	# Adjacent four-pixel edges must clear the same ellipse as exact movement.
	# A one-pixel planning margin keeps their chords outside physical clearance.
	var planning_clearance := clearance + Vector2.ONE
	# This synchronous query borrows the room grid and restores every changed cell.
	# No cached furniture or navigation geometry is rebuilt for moving people.
	for person in people:
		var first := Vector2i(((person - planning_clearance) / CELL).floor())
		var last := Vector2i(((person + planning_clearance) / CELL).ceil())
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var cell := Vector2i(x, y)
				if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell): continue
				if ((Vector2(cell * CELL) - person) / planning_clearance).length_squared() < 1.0:
					grid.set_point_solid(cell, true)
					marked.append(cell)
	var result: Array[Vector2] = _route_grid(from, to, room, grid, 8, people, clearance)
	for cell in marked: grid.set_point_solid(cell, false)
	return result

static func _route_grid(from: Vector2, to: Vector2, room: String, grid: AStarGrid2D, goal_radius: int = 3, people: Array[Vector2] = [], clearance: Vector2 = Vector2.ONE) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var start: Vector2i = _nearest_grid(from, room, grid, true, 5 if not people.is_empty() else 3, people, clearance)
	var unoccupied := true
	for person in people:
		if ((to - person) / clearance).length_squared() < 1.0: unoccupied = false
	var goal_people: Array[Vector2] = []
	if unoccupied: goal_people = people
	var goal: Vector2i = _nearest_grid(to, room, grid, is_walkable(to, room), goal_radius, goal_people, clearance, true)
	if start.x < 0 or goal.x < 0:
		return result
	var points: PackedVector2Array = grid.get_point_path(start, goal)
	if points.is_empty():
		return result
	for point in points:
		if result.is_empty() or result[-1] != point:
			result.append(point)
	# Preserve an exact valid doorway/click instead of snapping its final position.
	if unoccupied and is_walkable(to, room) and _clear_segment(result[-1], to, room) and clear_people_segment(result[-1], to, people, clearance) and result[-1] != to:
		result.append(to)
	return result
