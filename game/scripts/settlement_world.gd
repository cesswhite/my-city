extends RefCounted
## Pure presentation of a single colony snapshot. Plans and navigation stay immutable.
const Layout = preload("res://scripts/world_layout.gd")
const Catalog = preload("res://scripts/settlement_catalog.gd")

static func data(state: Dictionary) -> Dictionary:
	var value = state.get("settlement", state if state.has("buildings") and state.has("areas") else {})
	return value if value is Dictionary else {}

static func area_open(room: String, state: Dictionary = {}) -> bool:
	var current: Dictionary = data(state)
	return current.is_empty() or room in current.get("areas", [])

static func building_ready(id: String, state: Dictionary = {}) -> bool:
	var current: Dictionary = data(state)
	return id.is_empty() or current.is_empty() or id in current.get("buildings", [])

static func home_ready(home: String, state: Dictionary = {}) -> bool:
	return building_ready(str(Catalog.data().get("home_buildings", {}).get(home, "")), state)

static func remaining(node_id: String, state: Dictionary) -> int:
	var spec: Dictionary = Catalog.data().get("nodes", {}).get(node_id, {})
	var current: Dictionary = data(state)
	var record: Dictionary = current.get("nodes", {}).get(node_id, {})
	var period: int = int(float(current.get("minute", 0)) / maxf(1.0, float(spec.get("period", 1440))))
	if record.is_empty() or (current.has("minute") and int(record.get("period", -1)) != period): return int(spec.get("stock", 0))
	return maxi(0, int(record.get("remaining", spec.get("stock", 0))))

static func plot_stage(plot_id: String, state: Dictionary) -> String:
	var current: Dictionary = data(state)
	if current.is_empty(): return "ready"
	var spec: Dictionary = Catalog.data().get("plots", {}).get(plot_id, {})
	if not building_ready(str(spec.get("requires", "")), state): return "unprepared"
	var plot: Dictionary = current.get("plots", {}).get(plot_id, {})
	var status: String = str(plot.get("status", "empty"))
	if status in ["ready", "mature", "harvestable"]: return "ready"
	if status in ["empty", "harvested"]: return "empty"
	var age: int = maxi(0, int(current.get("minute", plot.get("planted_at", 0))) - int(plot.get("planted_at", 0)))
	if bool(plot.get("tended", false)) and age >= int(spec.get("growth_minutes", 180)): return "ready"
	return "growing" if age >= int(spec.get("growth_minutes", 180)) / 3 else "seeded"

static func objects(room: String, base: Array[Dictionary], state: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current: Dictionary = data(state)
	for raw: Dictionary in base:
		var item: Dictionary = raw.duplicate(true)
		if item.has("settlement_node"):
			item.resource_remaining = remaining(str(item.settlement_node), state)
			item.fixed_size = true
			if item.resource != "fruta": item.tile = true
		elif item.has("settlement_plot"):
			item.crop_stage = plot_stage(str(item.settlement_plot), state)
			item.tile = true
			item.fixed_size = true
			item.erase("crop_row")
		elif item.has("settlement_building") and not building_ready(str(item.settlement_building), state):
			if not item.get("settlement_site", false): continue
			var project: Dictionary = current.get("projects", {}).get(str(item.get("settlement_project", "")), {})
			item.tile = true
			item.construction_stage = "scaffold" if float(project.get("progress", 0.0)) > 0.0 or str(project.get("status", "")) in ["building", "working", "in_progress"] else "foundation"
			item.id = "tile_soil"
			item.fixed_size = true
			for field in ["source_rect", "edge_finish", "label_override"]: item.erase(field)
		result.append(item)
	# Small tools on a work surface share its productive action and prerequisites.
	var parents: Dictionary = {}
	for item: Dictionary in result: parents[str(item.key)] = item
	for item: Dictionary in result:
		var support: String = str(item.get("support",""))
		if parents.has(support) and parents[support].has("settlement_tasks"):
			item.settlement_tasks = parents[support].settlement_tasks.duplicate()
	if Layout.is_outdoor(room):
		for edge: Dictionary in Layout.exits(room):
			if area_open(str(edge.to), state): continue
			var gate: Dictionary = _gate_object(edge)
			result.append(gate)
	return result

static func _gate_object(edge: Dictionary) -> Dictionary:
	var box := Rect2()
	match str(edge.side):
		"north": box = Rect2(edge.at - Vector2(16,6), Vector2(32,17))
		"south": box = Rect2(edge.at - Vector2(16,12), Vector2(32,17))
		"west": box = Rect2(Vector2(12,edge.at.y-18), Vector2(17,36))
		"east": box = Rect2(Vector2(462,edge.at.y-18), Vector2(17,36))
	return {"key":"gate_"+str(edge.id), "id":"fence", "rect":box, "y":box.end.y, "fixed_size":true, "tile":true, "settlement_gate":edge.id, "gate_axis":"vertical" if edge.direction.x != 0 else "horizontal"}

static func gate_target(room: String, edge: Dictionary, state: Dictionary = {}) -> Dictionary:
	if area_open(str(edge.to), state): return {}
	var project_id := ""
	for id in Catalog.data().get("projects", {}):
		if str(Catalog.data().projects[id].get("opens", "")) == str(edge.to): project_id = str(id); break
	var spec: Dictionary = Catalog.data().get("projects", {}).get(project_id, {})
	var discovery: String = str(spec.get("discovery", ""))
	var inspect: bool = not discovery.is_empty() and discovery not in data(state).get("discoveries", [])
	var task_id: String = ("explore:" + discovery) if inspect else ("build:" + project_id if not project_id.is_empty() else "")
	var object: Dictionary = _gate_object(edge)
	return {"key":room+":gate:"+str(edge.id),"kind":"settlement","task_id":task_id,"title":"Paso cerrado · "+Layout.area_title(str(edge.to)),"action":"examinar" if inspect else "restaurar","rect":object.rect.grow(4),"object":object,"exit_id":edge.id}

static func _target(room: String, object: Dictionary, index: int, task_id: String, title: String, action: String) -> Dictionary:
	return {"key":room+":settlement:"+str(object.key),"kind":"settlement","task_id":task_id,"title":title,"action":action,"rect":object.rect,"object":object.duplicate(true),"_index":index,"_y":float(object.y)}

static func targets(room: String, state: Dictionary, rendered: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data(state).is_empty(): return result
	var catalog: Dictionary = Catalog.data()
	for index in rendered.size():
		var item: Dictionary = rendered[index]
		if item.has("settlement_gate"): continue
		if item.get("settlement_board", false):
			result.append(_target(room,item,index,"",str(catalog.board.title),"ver trabajos"))
		elif item.has("settlement_node"):
			var id: String = str(item.settlement_node)
			result.append(_target(room,item,index,"gather:"+id,str(catalog.nodes[id].title),"recoger" if remaining(id,state)>0 else "ver disponibilidad"))
		elif item.has("settlement_plot"):
			var id: String = str(item.settlement_plot)
			var stage: String = plot_stage(id,state)
			var action: String = "build:community_garden" if stage=="unprepared" else "plant:"+id if stage=="empty" else "harvest:"+id if stage=="ready" else "tend:"+id
			result.append(_target(room,item,index,action,str(catalog.plots[id].title),"preparar" if stage=="unprepared" else "sembrar" if stage=="empty" else "cosechar" if stage=="ready" else "cuidar"))
		elif item.has("construction_stage"):
			var id: String = str(item.get("settlement_project", ""))
			if catalog.projects.has(id): result.append(_target(room,item,index,"build:"+id,str(catalog.projects[id].title),"construir"))
		elif item.has("settlement_tasks"):
			var tasks: Array = item.settlement_tasks
			if tasks.is_empty(): continue
			var recipe: String = str(tasks[0]).get_slice(":",1)
			var target: Dictionary = _target(room,item,index,str(tasks[0]),str(catalog.recipes.get(recipe,{}).get("title","Producir")),"producir")
			target.task_ids = tasks.duplicate()
			if item.id == "cafe_table": target.rect = Rect2(item.rect.position + Vector2(12,0),Vector2(15,9))
			result.append(target)
		elif item.has("settlement_project"):
			var id: String = str(item.settlement_project)
			if catalog.projects.has(id) and catalog.projects[id].kind != "house":
				result.append(_target(room,item,index,"",str(catalog.projects[id].title),"ver proyecto"))
	return result
