extends RefCounted
## Bounded, persistent environmental changes. Reads never roll or advance time.
const Catalog = preload("res://scripts/environmental_catalog.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Details = preload("res://scripts/home_details.gd")
const DAMAGE_WINDOW := 30
const REGROW_MINUTES := 360
var _world: WeakRef
var state: Dictionary = {}
var _inside: Dictionary = {}
## Test seam only; never serialized. Production uses the saved seed/tree/day hash.
var _fruit_roll: Callable
var _cells: Array[Dictionary] = []
var _view_key: String = ""
var _view_cache: Dictionary = {}

func setup(world) -> void:
	_world = weakref(world)
	_view_key = ""
	_view_cache.clear()
	_cells = Catalog.crop_cells()
	state = {"version":1,"revision":0,"seed":int(randi()%2147483647),"cells":{},"trees":{},"fruit":{},"golden":{},"households":{}}
	_reset_footsteps()
	tick()

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(value: Dictionary) -> void:
	state = value.duplicate(true)
	# JSON numbers are floating-point; normalize the bounded integer schema.
	for field: String in ["version","revision","seed"]: state[field] = int(state[field])
	for entry: Dictionary in state.cells.values():
		entry.planted_at = int(entry.planted_at)
		entry.destroyed_at = int(entry.destroyed_at)
		for index: int in range(entry.entries.size()): entry.entries[index] = int(entry.entries[index])
	for entry: Dictionary in state.trees.values(): entry.planted_at = int(entry.planted_at)
	for entry: Dictionary in state.fruit.values(): entry.day = int(entry.day)
	if not state.golden.is_empty(): state.golden.day = int(state.golden.day)
	for household: Dictionary in state.households.values():
		for key: String in household.watered: household.watered[key] = int(household.watered[key])
	_view_key = ""
	_view_cache.clear()
	_reset_footsteps()

func _changed() -> void:
	state.revision = int(state.revision)+1

func _reset_footsteps() -> void:
	_inside.clear()
	if _world == null or _world.get_ref() == null: return
	var player: Dictionary = _world.get_ref().get_resident("player")
	if player.is_empty(): return
	for cell: Dictionary in _cells:
		if cell.room == player.get("room","") and cell.rect.grow(2).has_point(Layout.point(player.pos)): _inside[cell.id] = true

func tick() -> void:
	if _world == null or _world.get_ref() == null: return
	var world = _world.get_ref()
	var now: int = world.minute
	var changed := false
	for id: String in state.cells.keys():
		var entry: Dictionary = state.cells[id]
		var plot: Dictionary = world.settlement.state.plots.get(id.get_slice(":",0),{})
		if plot.get("status", "empty") != "growing" or int(plot.get("planted_at",-1)) != int(entry.planted_at):
			state.cells.erase(id); changed = true; continue
		var fresh: Array = []
		for stamp in entry.entries:
			if now-int(stamp) <= DAMAGE_WINDOW: fresh.append(stamp)
		if fresh != entry.entries: entry.entries = fresh; changed = true
		if int(entry.destroyed_at) >= 0 and now-int(entry.destroyed_at) >= REGROW_MINUTES:
			entry.destroyed_at = -1; changed = true
		if entry.entries.is_empty() and int(entry.destroyed_at) < 0:
			state.cells.erase(id); changed = true
	for site: Dictionary in Catalog.tree_sites():
		if world.area_open(site.room) and not state.trees.has(site.id):
			state.trees[site.id] = {"planted_at":now}; changed = true
	var day: int = int(now/1440)
	for tree: Dictionary in Catalog.fruit_trees():
		if not world.area_open(tree.room): continue
		if int(state.fruit.get(tree.id,{}).get("day",-1)) == day: continue
		var roll: int = _roll(tree.id,day)
		var kind := "none"
		if roll == 0 and state.golden.is_empty():
			kind = "golden"
			state.golden = {"tree_id":tree.id,"day":day}
		elif roll > 0 and roll <= 12000: kind = "apple"
		state.fruit[tree.id] = {"day":day,"kind":kind,"collected":false}
		changed = true
	if changed: _changed()

func _roll(tree_id: String, day: int) -> int:
	if _fruit_roll.is_valid(): return clampi(int(_fruit_roll.call(tree_id,day)),0,99999)
	return ("%d:%s:%d" % [int(state.seed),tree_id,day]).sha256_text().substr(0,12).hex_to_int()%100000

func view() -> Dictionary:
	if _world == null or _world.get_ref() == null: return {}
	var world = _world.get_ref()
	var cache_key: String = "%d:%d:%d:%d" % [world.minute,int(state.revision),int(world.settlement.state.revision),world.settlement.state.plots.hash()]
	if cache_key == _view_key: return _view_cache.duplicate(true)
	var result := {"minute":world.minute,"revision":int(state.revision),"cropcells":[],"treeplants":[],"fruit":[],"households":state.households.duplicate(true)}
	for cell: Dictionary in _cells:
		if not world.area_open(cell.room): continue
		var plot: Dictionary = world.settlement.state.plots.get(cell.plot_id,{})
		var requirements: Dictionary = world.settlement.catalog.plots.get(cell.plot_id,{})
		var base_age: int = world.minute-int(plot.get("planted_at",world.minute))
		var growing: bool = plot.get("status","empty") == "growing"
		var mature: bool = growing and bool(plot.get("tended",false)) and base_age >= int(requirements.get("growth_minutes",180))
		var stage: int = 3 if mature else (2 if base_age >= 60 else 1)
		if not growing: stage = 0
		var record: Dictionary = state.cells.get(cell.id,{})
		if int(record.get("planted_at",-1)) != int(plot.get("planted_at",0)): record = {}
		var destroyed_at: int = int(record.get("destroyed_at",-1))
		var damaged: bool = growing and destroyed_at >= 0 and world.minute-destroyed_at < REGROW_MINUTES
		var bent := false
		var recent := 0
		for stamp in record.get("entries",[]):
			if world.minute-int(stamp) <= DAMAGE_WINDOW: recent += 1
		bent = growing and not damaged and recent >= 3
		if damaged:
			var age: int = world.minute-destroyed_at
			stage = mini(stage,0 if age < 45 else (1 if age < 120 else 2))
		var item: Dictionary = cell.duplicate(true)
		item.merge({"stage":stage,"bent":bent,"destroyed":damaged,"condition":"destroyed" if damaged and stage == 0 else ("regrowing" if damaged else ("bent" if bent else "healthy")),"harvestable":mature and not damaged})
		result.cropcells.append(item)
	for site: Dictionary in Catalog.tree_sites():
		if not world.area_open(site.room) or not state.trees.has(site.id): continue
		var item: Dictionary = site.duplicate(true)
		var planted: int = int(state.trees[site.id].planted_at)
		var stage := 0
		for index: int in range(Catalog.TREE_STAGES.size()):
			if world.minute-planted >= int(Catalog.TREE_STAGES[index]): stage = index
		item.merge({"stage":stage,"planted_at":planted})
		result.treeplants.append(item)
	var day: int = int(world.minute/1440)
	for tree: Dictionary in Catalog.fruit_trees():
		var entry: Dictionary = state.fruit.get(tree.id,{})
		if not world.area_open(tree.room) or int(entry.get("day",-1)) != day or entry.get("kind","none") == "none" or entry.get("collected",false): continue
		result.fruit.append({"id":tree.id+":"+str(day),"tree_id":tree.id,"room":tree.room,"at":tree.at,"kind":entry.kind,"expires_at":(day+1)*1440})
	_view_key = cache_key
	_view_cache = result
	return result.duplicate(true)

func record_motion(room: String, before: Vector2, after: Vector2) -> bool:
	var world = _world.get_ref() if _world != null else null
	if world == null or not before.is_finite() or not after.is_finite(): return false
	var player: Dictionary = world.get_resident("player")
	if player.get("room","") != room or Layout.point(player.pos).distance_to(after) > 0.1: return false
	# Portals, load recovery and teleports are not footsteps. Also reset hysteresis.
	if before.distance_to(after) > 16.0:
		_reset_footsteps(); return false
	if before.is_equal_approx(after) or world.is_sleeping("player") or "player" in world.conversation_holds: return false
	var changed := false
	for cell: Dictionary in _cells:
		if cell.room != room:
			_inside.erase(cell.id); continue
		if _inside.has(cell.id):
			if not cell.rect.grow(2).has_point(after): _inside.erase(cell.id)
			continue
		if cell.rect.has_point(before):
			_inside[cell.id] = true; continue
		if not cell.rect.has_point(after): continue
		_inside[cell.id] = true
		var plot: Dictionary = world.settlement.state.plots.get(cell.plot_id,{})
		if plot.get("status","empty") != "growing" or not world.area_open(room): continue
		var entry: Dictionary = state.cells.get(cell.id,{"planted_at":int(plot.planted_at),"entries":[],"destroyed_at":-1})
		if int(entry.planted_at) != int(plot.planted_at): entry = {"planted_at":int(plot.planted_at),"entries":[],"destroyed_at":-1}
		if int(entry.destroyed_at) >= 0 and world.minute-int(entry.destroyed_at) < REGROW_MINUTES: continue
		entry.destroyed_at = -1
		var recent: Array = []
		for stamp in entry.entries:
			if world.minute-int(stamp) <= DAMAGE_WINDOW: recent.append(stamp)
		recent.append(world.minute)
		entry.entries = recent.slice(maxi(0,recent.size()-5))
		if entry.entries.size() >= 5: entry.destroyed_at = world.minute
		state.cells[cell.id] = entry
		changed = true
	if changed: _changed()
	return changed

func reset_plot(plot_id: String) -> void:
	var changed := false
	for id: String in state.cells.keys():
		if id.get_slice(":",0) == plot_id: state.cells.erase(id); changed = true
	if changed: _changed()

func harvest_outputs(plot_id: String, outputs: Dictionary) -> Dictionary:
	var count := 0
	for cell: Dictionary in view().get("cropcells",[]):
		if cell.plot_id == plot_id and cell.harvestable: count += 1
	var result := {}
	for id: String in outputs:
		var quantity: int = int(floor(float(outputs[id])*float(count)/8.0))
		if quantity > 0: result[id] = quantity
	return result

func _player_ready(room: String, at: Vector2, distance: float, require_still: bool = true) -> bool:
	var world = _world.get_ref()
	var player: Dictionary = world.get_resident("player")
	return player.get("room","") == room and world.is_present("player") and not world.is_sleeping("player") and world.player_energy() > 0.0 and not world.player_autonomy and "player" not in world.conversation_holds and at.is_finite() and Layout.point(player.pos).distance_to(at) <= distance and (not require_still or Layout.point(player.pos).distance_to(Layout.point(player.target)) <= 1.0)

func collect_fruit(tree_id: String) -> Dictionary:
	var world = _world.get_ref()
	var tree: Dictionary = Catalog.fruit_tree(tree_id)
	if tree.is_empty() or not world.area_open(tree.room) or not _player_ready(tree.room,tree.at,12.0,false): return _result(false,"Acércate a la fruta para recogerla.")
	var entry: Dictionary = state.fruit.get(tree_id,{})
	if int(entry.get("day",-1)) != int(world.minute/1440) or entry.get("kind","none") == "none" or entry.get("collected",false): return _result(false,"Ya no hay fruta en este punto.")
	var player: Dictionary = world.get_resident("player")
	var before: float = float(player.energy)
	player.energy = minf(100.0,before+(100.0 if entry.kind == "golden" else 1.0))
	entry.collected = true
	_changed()
	return {"ok":true,"message":"Una manzana dorada: te sientes renovado." if entry.kind == "golden" else "Comiste una manzana recién caída.","energy_gained":float(player.energy)-before}

func house_action(room: String, prop_key: String, action: String) -> Dictionary:
	var world = _world.get_ref()
	var object: Dictionary = Catalog.prop(room,prop_key)
	if object.is_empty() or room not in Catalog.HOMES or not world.home_available(room) or not _player_ready(room,Catalog.stand_for(room,prop_key),18.0): return _result(false,"Acércate al objeto dentro de la casa.")
	var details: Dictionary = Details.for_object(object,room)
	if details.is_empty(): return _result(false,"Este objeto tiene su propia interacción.")
	if action.begins_with("page:"):
		var page: Dictionary = Details.page_for(room,prop_key,action.substr(5))
		if page.is_empty(): return _result(false,"Esa página no está a la vista.")
		var observed: bool = world.observe_house_item("player",room,str(page.title),str(page.text))
		return _result(observed,"Miraste esta página." if observed else "No se pudo leer esta página.")
	if action == "inspect":
		return _result(world.observe_house_item("player",room,str(details.title),str(details.text)),str(details.text))
	var allowed := false
	for option: Dictionary in details.get("actions",[]):
		if option.id == action and action in ["water","curtains"]: allowed = true
	if not allowed: return _result(false,"Esa acción no corresponde al objeto.")
	var household: Dictionary = state.households.get(room,{"watered":{},"curtains":{}})
	if action == "water":
		if household.watered.has(prop_key) and world.minute-int(household.watered[prop_key]) < 180: return _result(false,"La tierra sigue húmeda; no hace falta más agua.")
		household.watered[prop_key] = world.minute
	else: household.curtains[prop_key] = not bool(household.curtains.get(prop_key,false))
	state.households[room] = household
	_changed()
	return _result(true,"Regaste la planta." if action == "water" else ("Cerraste las cortinas." if household.curtains[prop_key] else "Abriste las cortinas."))

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message,"energy_gained":0.0}

func _whole(value: Variant, maximum: int = 2147483647, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

func validate(value: Variant, minute: int = 2147483647, settlement_value: Dictionary = {}) -> bool:
	if not _keys(value,["version","revision","seed","cells","trees","fruit","golden","households"]) or value.version != 1: return false
	if not _whole(value.revision) or not _whole(value.seed): return false
	for field in ["cells","trees","fruit","golden","households"]:
		if not value[field] is Dictionary: return false
	var cell_ids: Array = []
	for cell: Dictionary in Catalog.crop_cells(): cell_ids.append(cell.id)
	if value.cells.size() > cell_ids.size(): return false
	for id in value.cells:
		var entry = value.cells[id]
		if id not in cell_ids or not _keys(entry,["planted_at","entries","destroyed_at"]): return false
		if not _whole(entry.planted_at,minute) or not _whole(entry.destroyed_at,minute,-1) or not entry.entries is Array or entry.entries.size() > 5: return false
		var previous: int = int(entry.planted_at)
		for stamp in entry.entries:
			if not _whole(stamp,minute) or int(stamp) < previous: return false
			previous = int(stamp)
		if int(entry.destroyed_at) >= 0 and int(entry.destroyed_at) < int(entry.planted_at): return false
		if entry.entries.size() == 5 and int(entry.destroyed_at) < 0: return false
		if not settlement_value.is_empty():
			var plot: Dictionary = settlement_value.get("plots",{}).get(str(id).get_slice(":",0),{})
			if plot.get("status", "empty") != "growing" or int(plot.get("planted_at",-1)) != int(entry.planted_at): return false
	for id in value.trees:
		if Catalog.tree_site(str(id)).is_empty() or not _keys(value.trees[id],["planted_at"]) or not _whole(value.trees[id].planted_at,minute): return false
		if not settlement_value.is_empty() and Catalog.tree_site(str(id)).room not in settlement_value.get("areas",[]): return false
	var max_day: int = int(minute/1440)
	if not value.golden.is_empty():
		if not _keys(value.golden,["tree_id","day"]) or Catalog.fruit_tree(str(value.golden.tree_id)).is_empty() or not _whole(value.golden.day,max_day): return false
	var gold_count := 0
	for id in value.fruit:
		var entry = value.fruit[id]
		if Catalog.fruit_tree(str(id)).is_empty() or not _keys(entry,["day","kind","collected"]) or not _whole(entry.day,max_day) or entry.kind not in ["none","apple","golden"] or not entry.collected is bool: return false
		if entry.kind == "none" and entry.collected: return false
		if not settlement_value.is_empty() and Catalog.fruit_tree(str(id)).room not in settlement_value.get("areas",[]): return false
		if entry.kind == "golden":
			gold_count += 1
			if value.golden.is_empty() or value.golden.tree_id != id or int(value.golden.day) != int(entry.day): return false
	if gold_count > 1: return false
	for room in value.households:
		var household = value.households[room]
		if room not in Catalog.HOMES or not _keys(household,["watered","curtains"]) or not household.watered is Dictionary or not household.curtains is Dictionary: return false
		for key in household.watered:
			if Catalog.prop(room,str(key)).get("id","") != "plant" or not _whole(household.watered[key],minute): return false
		for key in household.curtains:
			if Catalog.prop(room,str(key)).get("id","") != "window" or not household.curtains[key] is bool: return false
	return true
