extends RefCounted
## Cached geometry only. Every visible pixel is sampled from an existing terrain PNG.
## The centre of a path is never eroded; fringes extend into bare grass only.
const MAX_PLANS := 16
const RUN := 16
static var _plans: Dictionary = {}

static func plan(ground: Array, bounds: Rect2) -> Dictionary:
	var key: String = JSON.stringify(ground) + str(bounds)
	if _plans.has(key): return _plans[key]
	var result := {"fringes": [], "base": [], "shore": []}
	var occupied: Array[Rect2] = []
	for item: Dictionary in ground:
		occupied.append(_rect(item.rect))
	for item: Dictionary in ground:
		var area: Rect2 = _rect(item.rect)
		var id: String = str(item.id)
		var tint := Color(str(item.get("tint", "ffffff")))
		var corner: int = int(item.get("corner_cut", 0))
		# A cut-stone plaza deliberately retains its built, orthogonal outline.
		if str(item.get("key", "")) == "stream_bank": corner = 8
		for strip: Rect2 in _corner_strips(area, corner):
			result.base.append({"id": id, "rect": strip, "tint": tint})
		if id == "tile_sand" or str(item.get("key", "")) == "stream_bank":
			_fringe(result.fringes, id, area, tint, corner, occupied, bounds)
		if id == "tile_water" and str(item.get("key", "")) == "stream":
			# Keep all water inside its existing solid footprint. Stone, not bare
			# walkable-looking grass, covers the few pixels at the inward corners.
			for y in range(0, 8, 2):
				var width: int = 8 - y
				for bottom: bool in [false, true]:
					for right: bool in [false, true]:
						var at := Vector2(area.end.x-width if right else area.position.x, area.end.y-y-2 if bottom else area.position.y+y)
						result.shore.append({"id": "tile_stone", "rect": Rect2(at, Vector2(width, 2)), "tint": Color.WHITE})
	if _plans.size() >= MAX_PLANS: _plans.erase(_plans.keys()[0])
	_plans[key] = result
	return result

static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func _corner_strips(area: Rect2, cut: int) -> Array[Rect2]:
	if cut <= 0: return [area]
	cut = mini(cut, mini(floori(area.size.x / 2.0), floori(area.size.y / 2.0)))
	var result: Array[Rect2] = []
	for y in range(0, cut, 2):
		var inset: int = cut - y
		var height: int = mini(2, cut-y)
		result.append(Rect2(area.position+Vector2(inset,y), Vector2(area.size.x-inset*2,height)))
		result.append(Rect2(Vector2(area.position.x+inset,area.end.y-y-height),Vector2(area.size.x-inset*2,height)))
	var middle := Rect2(area.position+Vector2(0,cut),Vector2(area.size.x,area.size.y-cut*2))
	if middle.has_area(): result.append(middle)
	return result

static func _fringe(output: Array, id: String, area: Rect2, tint: Color, cut: int, occupied: Array[Rect2], bounds: Rect2) -> void:
	var inset: int = maxi(1, cut)
	for horizontal: bool in [true, false]:
		var start: int = roundi(area.position.x if horizontal else area.position.y) + inset
		var finish: int = roundi(area.end.x if horizontal else area.end.y) - inset
		for cursor in range(start, finish, RUN):
			var length: int = mini(RUN, finish-cursor)
			# Long, stable 1/2px steps, not random scattered pixels or animation.
			var depth: int = 1 + posmod(floori(float(cursor)/RUN), 2)
			for far_side: bool in [false, true]:
				var strip: Rect2
				if horizontal:
					strip = Rect2(cursor,area.end.y if far_side else area.position.y-depth,length,depth)
				else:
					strip = Rect2(area.end.x if far_side else area.position.x-depth,cursor,depth,length)
				for fragment: Rect2 in _outside_ground(strip.intersection(bounds), occupied):
					output.append({"id": id, "rect": fragment, "tint": tint})

static func _outside_ground(area: Rect2, occupied: Array[Rect2]) -> Array[Rect2]:
	var fragments: Array[Rect2] = []
	if area.has_area(): fragments.append(area)
	for obstacle: Rect2 in occupied:
		var next: Array[Rect2] = []
		for piece: Rect2 in fragments:
			var overlap := piece.intersection(obstacle)
			if not overlap.has_area():
				next.append(piece)
				continue
			for remainder: Rect2 in [
				Rect2(piece.position,Vector2(piece.size.x,overlap.position.y-piece.position.y)),
				Rect2(piece.position.x,overlap.end.y,piece.size.x,piece.end.y-overlap.end.y),
				Rect2(piece.position.x,overlap.position.y,overlap.position.x-piece.position.x,overlap.size.y),
				Rect2(overlap.end.x,overlap.position.y,piece.end.x-overlap.end.x,overlap.size.y)]:
				if remainder.has_area(): next.append(remainder)
		fragments = next
		if fragments.is_empty(): break
	return fragments
