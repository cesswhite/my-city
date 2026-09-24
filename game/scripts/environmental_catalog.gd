extends RefCounted
## Physical environmental sites; no random rolls, simulation or renderer dependency.
const Layout = preload("res://scripts/world_layout.gd")
const TREE_STAGES := [0, 45, 180, 720, 1440, 2880]
const HOMES := ["player", "cesar", "lupita", "mateo", "ines", "alma"]
static var _stands: Dictionary = {}
static var _trees: Array[Dictionary] = []
static var _fruit_trees: Array[Dictionary] = []
static var _crop_cells: Array[Dictionary] = []

static func prop(room: String, key: String) -> Dictionary:
	if not Layout.is_outdoor(room) and room not in HOMES: return {}
	for item: Dictionary in Layout.props(room):
		if str(item.key) == key: return item
	return {}

static func tree_sites() -> Array[Dictionary]:
	if not _trees.is_empty(): return _trees.duplicate(true)
	var result: Array[Dictionary] = []
	for raw: Array in [["homes_sapling", "homes", "lupita_shade", Vector2(72,38)], ["forest_sapling_west", "forest", "forest_tree_1", Vector2(6,104)], ["forest_sapling_east", "forest", "forest_tree_4", Vector2(30,100)]]:
		var anchor: Dictionary = prop(raw[1],raw[2])
		if anchor.is_empty(): continue
		var at: Vector2 = anchor.rect.position + raw[3]
		result.append({"id":raw[0],"room":raw[1],"at":at,"rect":Rect2(at-Vector2(21,56),Vector2(42,56)),"footprint":Rect2(at-Vector2(3,4),Vector2(6,4))})
	_trees = result
	return result.duplicate(true)

static func tree_site(id: String) -> Dictionary:
	for item: Dictionary in tree_sites():
		if item.id == id: return item
	return {}

static func fruit_trees() -> Array[Dictionary]:
	if not _fruit_trees.is_empty(): return _fruit_trees.duplicate(true)
	var result: Array[Dictionary] = []
	for raw: Array in [["homes_apple", "homes", "homes_shade"], ["garden_apple", "gardens", "orchard_east"], ["forest_apple", "forest", "forest_tree_12"]]:
		var object: Dictionary = prop(raw[1],raw[2])
		if object.is_empty(): continue
		var at: Vector2 = Vector2(object.rect.end.x - 6,object.rect.end.y + 28)
		if raw[0] == "forest_apple": at.x += 4 # Clear the existing resource basket, including the fruit sprite.
		result.append({"id":raw[0],"tree_id":raw[0],"room":raw[1],"prop_key":raw[2],"at":at,"rect":object.rect})
	_fruit_trees = result
	return result.duplicate(true)

static func fruit_tree(id: String) -> Dictionary:
	for item: Dictionary in fruit_trees():
		if item.id == id: return item
	return {}

static func crop_cells() -> Array[Dictionary]:
	if not _crop_cells.is_empty(): return _crop_cells.duplicate(true)
	var result: Array[Dictionary] = []
	for room: String in Layout.outdoor_ids():
		for item: Dictionary in Layout.props(room):
			if not item.has("settlement_plot"): continue
			for index: int in range(8):
				var cell := Rect2(item.rect.position + Vector2(index*14,0),Vector2(14,item.rect.size.y))
				result.append({"id":str(item.settlement_plot)+":"+str(index),"plot_id":str(item.settlement_plot),"index":index,"room":room,"rect":cell,"at":cell.position+Vector2(8,13)})
	_crop_cells = result
	return result.duplicate(true)

static func stand_for(room: String, prop_key: String) -> Vector2:
	var cache_key: String = room+":"+prop_key
	if _stands.has(cache_key): return _stands[cache_key]
	var object: Dictionary = prop(room,prop_key)
	if object.is_empty(): return Vector2.INF
	var target: Vector2 = Vector2(object.rect.get_center().x, object.rect.end.y+8)
	for interaction: Dictionary in Layout.section(room).get("interactions",{}).values():
		if str(interaction.get("key","")) == prop_key:
			target = Layout.point(interaction.stand_at)
			break
	var bounds: Rect2 = Layout.bounds(room)
	target = target.clamp(bounds.position+Vector2(4,4),bounds.end-Vector2(4,4)).round()
	var obstacles: Array[Rect2] = Layout.obstacles(room)
	for radius: int in range(0,65,4):
		for direction: Vector2 in [Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
			var candidate: Vector2 = target + direction*radius
			if not bounds.has_point(candidate): continue
			var clear := true
			for obstacle: Rect2 in obstacles:
				if obstacle.grow(1).has_point(candidate): clear = false; break
			if clear:
				_stands[cache_key] = candidate
				return candidate
	return Vector2.INF
