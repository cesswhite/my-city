extends RefCounted
## Shared pixel geometry for artwork, navigation and interaction. Feet are the world anchor.
const SettlementCatalog = preload("res://scripts/settlement_catalog.gd")
static var _data: Dictionary = {}
static var _rooms: Dictionary = {}
static var _neighborhood: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json"))
		if parsed is Dictionary: _data = parsed
	return _data

static func point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func section(room: String) -> Dictionary:
	if _rooms.has(room): return _rooms[room]
	if is_outdoor(room):
		var outdoor: Dictionary = neighborhood().areas[room].duplicate(true)
		var geometry: Dictionary = SettlementCatalog.data().get("geometry", {})
		outdoor.props.append_array(geometry.get("props", {}).get(room, []).duplicate(true))
		for item: Dictionary in outdoor.props:
			item.merge(geometry.get("bindings", {}).get(room, {}).get(str(item.key), {}), true)
		_rooms[room] = outdoor
		return outdoor
	var result: Dictionary = data().get("interior", {}).duplicate(true)
	var variant: Dictionary = data().get("room_variants", {}).get(room, {})
	for key in variant:
		if key not in ["props", "extra_props", "interactions"]: result[key] = variant[key]
	var furniture: Array = []
	for raw in result.get("props", []):
		var item: Dictionary = raw.duplicate(true)
		item.merge(variant.get("props", {}).get(str(item.key), {}), true)
		if item.get("enabled", true): furniture.append(item)
	furniture.append_array(variant.get("extra_props", []).duplicate(true))
	result.props = furniture
	result.interactions.merge(variant.get("interactions", {}), true)
	_rooms[room] = result
	return result

static func bounds(room: String) -> Rect2:
	return rect(section(room).bounds)

static func props(room: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var by_key: Dictionary = {}
	for raw in section(room).props:
		var item: Dictionary = raw.duplicate(true)
		item.rect = rect(raw.rect)
		if raw.has("footprint"): item.footprint = rect(raw.footprint)
		if raw.has("source_rect"): item.source_rect = rect(raw.source_rect)
		result.append(item)
		by_key[str(item.key)] = item
	for item in result:
		var support: String = str(item.get("support", ""))
		if support.is_empty() or not by_key.has(support) or item.get("support_offset", []).size() != 2: continue
		var parent: Dictionary = by_key[support]
		var anchor: Vector2 = parent.rect.position + point(item.support_offset)
		item.support_point = anchor
		item.rect.position = (anchor - Vector2(item.rect.size.x / 2.0, item.rect.size.y)).floor()
		item.y = float(parent.y) + 0.1
	return result

static func obstacles(room: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for item in section(room).props:
		# Ground-level crops are walkable. Raised planters, walls and bed borders
		# remain solid; the environmental simulation observes confirmed footsteps.
		if item.has("footprint") and not item.get("crop_row",false) and not item.has("settlement_plot"): result.append(rect(item.footprint))
	for item in section(room).get("extra_obstacles", []): result.append(rect(item))
	return result

static func interaction(id: String, room: String = "player") -> Dictionary:
	var item: Dictionary = section(room).get("interactions", {}).get(id, {})
	if item.is_empty(): return {}
	for prop in props(room):
		if prop.key == item.key: return {"rect": prop.rect, "stand_at": point(item.stand_at)}
	return {}

static func stand_at(id: String, room: String = "player") -> Vector2:
	return point(section(room).interactions[id].stand_at)

static func door_positions() -> Dictionary:
	var result: Dictionary = {}
	for id in data().doors: result[id] = point(data().doors[id])
	return result


static func neighborhood() -> Dictionary:
	if _neighborhood.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/neighborhood.json"))
		if parsed is Dictionary: _neighborhood = parsed
	return _neighborhood

static func outdoor_ids() -> Array[String]:
	var result: Array[String] = []
	for id in neighborhood().get("areas", {}): result.append(str(id))
	return result

static func is_outdoor(room: String) -> bool:
	return neighborhood().get("areas", {}).has(room)

static func home_area(home: String) -> String:
	return str(neighborhood().get("home_areas", {}).get(home, "street"))

static func place_area(place: String) -> String:
	return str(neighborhood().get("place_areas", {}).get(place, "street"))

static func area_title(room: String) -> String:
	return str(neighborhood().get("areas", {}).get(room, {}).get("title", "Casa"))

static func area_description(room: String) -> String:
	return str(neighborhood().get("areas", {}).get(room, {}).get("description", ""))

static func area_grid(room: String) -> Vector2i:
	return Vector2i(point(neighborhood().get("areas", {}).get(room, {}).get("grid", [0, 0])))

static func resident_spawn(id: String) -> Dictionary:
	var spawn: Dictionary = neighborhood().get("spawns", {}).get(id, {})
	return {"room": str(spawn.get("room", "street")), "position": point(spawn.get("position", [192, 230]))}

static func exits(room: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directions: Dictionary = {"north": Vector2.UP, "south": Vector2.DOWN, "west": Vector2.LEFT, "east": Vector2.RIGHT}
	for raw: Dictionary in neighborhood().get("areas", {}).get(room, {}).get("exits", []):
		var item: Dictionary = raw.duplicate(true)
		item.side = str(raw.direction)
		item.direction = directions.get(item.side, Vector2.ZERO)
		item.at = point(raw.at)
		item.spawn = point(raw.spawn)
		result.append(item)
	return result

static func area_route(from: String, to: String) -> Array[String]:
	var result: Array[String] = []
	if not is_outdoor(from) or not is_outdoor(to): return result
	var pending: Array[String] = [from]
	var previous: Dictionary = {from: ""}
	while not pending.is_empty():
		var current: String = pending.pop_front()
		if current == to:
			while not current.is_empty():
				result.push_front(current)
				current = str(previous[current])
			return result
		for edge: Dictionary in exits(current):
			if previous.has(edge.to): continue
			previous[edge.to] = current
			pending.append(str(edge.to))
	return result

static func next_exit(from: String, to: String) -> Dictionary:
	var route: Array[String] = area_route(from, to)
	if route.size() < 2: return {}
	for edge: Dictionary in exits(from):
		if edge.to == route[1]: return edge
	return {}

static func edge_exit(room: String, at: Vector2, direction: Vector2) -> Dictionary:
	if not at.is_finite() or not direction.is_finite() or direction.is_zero_approx(): return {}
	for edge: Dictionary in exits(room):
		if direction.normalized().dot(edge.direction) < 0.5: continue
		# Trigger only at the opening and only while deliberately moving outward.
		var relative: Vector2 = at - edge.at
		var lateral: float = absf(relative.x) if edge.direction.y != 0 else absf(relative.y)
		if lateral <= 16.0 and absf(relative.dot(edge.direction)) <= 5.0: return edge
	return {}
