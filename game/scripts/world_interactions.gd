extends RefCounted
## One target resolver for pointer feedback and clicking. No world or save mutation.
const Art = preload("res://scripts/pixel_art.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
const SettlementWorld = preload("res://scripts/settlement_world.gd")
const Seating = preload("res://scripts/seating.gd")
const EnvironmentInteractions = preload("res://scripts/environment_interactions.gd")
const HOME_NAMES := {"cesar": "César", "lupita": "Lupita", "mateo": "Mateo", "ines": "Inés", "alma": "Alma", "player": "Tu casa"}

static func _interaction_id(item: Dictionary, room: String) -> String:
	var definitions: Dictionary = Layout.section(room).get("interactions", {})
	var declared: String = str(item.get("id", ""))
	if definitions.has(declared): return declared
	var matching := ""
	for id in definitions:
		var geometry: Dictionary = Layout.interaction(str(id), room)
		if geometry.get("rect") != item.get("rect") or geometry.get("stand_at") != item.get("stand_at"): continue
		# NPC lore has no id. Prefer the semantic prop over its player-only aliases.
		if str(definitions[id].key) == str(id): return str(id)
		matching = str(id)
	return matching

static func _action(item: Dictionary, room: String) -> String:
	if Layout.is_outdoor(room) and item.get("type") == "shop": return "comprar"
	if room != "player": return "inspeccionar"
	match str(item.get("type", "")):
		"sleep": return "dormir"
		"closet": return "personalizar"
		"bicycle": return "ver bicicleta"
	if item.get("station") == "planting": return "cultivar"
	if item.get("station") == "tea_station": return "preparar té"
	return "inspeccionar"

static func _target(key: String, kind: String, title: String, action: String, object: Dictionary, item: Dictionary, index: int) -> Dictionary:
	return {"key": key, "kind": kind, "title": title, "action": action,
		"rect": object.rect, "object": object.duplicate(true), "item": item.duplicate(true),
		"_y": float(object.y), "_index": index}

static func _targets(room: String, state: Dictionary, rendered: Array[Dictionary] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not Layout.is_outdoor(room) and not Layout.data().doors.has(room): return result
	var objects: Array[Dictionary] = rendered if not rendered.is_empty() else Sprites.scenery_objects(room, state)
	var items: Array[Dictionary] = Art.street_items(room,state) if Layout.is_outdoor(room) else Art.interior_items(room)
	var definitions: Dictionary = Layout.section(room).get("interactions", {})
	for item in items:
		var id: String = _interaction_id(item, room)
		if id.is_empty(): continue
		var prop_key: String = str(definitions[id].key)
		var matching_keys: Array[String] = [prop_key]
		# Both the cup and the supporting table belong to the same tea interaction.
		if prop_key == "table": matching_keys.append("tea")
		if prop_key == "project": matching_keys.append("project_table")
		for index in range(objects.size()):
			var object: Dictionary = objects[index]
			if str(object.get("key", "")) not in matching_keys: continue
			var kind: String = "shop" if Layout.is_outdoor(room) and item.get("type") == "shop" else "item"
			result.append(_target(room + ":" + kind + ":" + id, kind, str(item.title), _action(item, room), object, item, index))
	# Contextual household controls replace only the former read-only lore card.
	# Sleep, wardrobe, learning, jobs and seating keep their established routes.
	var details: Array[Dictionary] = EnvironmentInteractions.targets(room,state,objects)
	for detail: Dictionary in details:
		var original_story := false
		for old_index in range(result.size()-1,-1,-1):
			if result[old_index].kind != "item" or int(result[old_index]._index) != int(detail._index): continue
			if detail.kind == "item": original_story = true
			else: result.remove_at(old_index)
		if not original_story: result.append(detail)
	result.append_array(SettlementWorld.targets(room,state,objects))
	if Layout.is_outdoor(room):
		for seat in Seating.seats(room):
			for index in range(objects.size()):
				var object: Dictionary = objects[index]
				if str(object.get("key", "")) != str(seat.prop_key): continue
				# Metadata names usable bench/rim/stool pixels, never a whole decorative prop.
				if str(object.id) not in ["bench", "fountain", "cafe_table"]: break
				var frame: Dictionary = Sprites.frame_info(str(object.id))
				if frame.is_empty(): break
				var crop: Rect2 = seat.source_rect
				if not crop.has_area() or not Rect2(Vector2.ZERO, frame.source.size).encloses(crop) or not object.rect.encloses(seat.rect): break
				var target: Dictionary = _target(room + ":seat:" + str(seat.id), "seat", str(seat.title), "sentarte", object, seat, index)
				target.rect = seat.rect
				target.seat_id = str(seat.id)
				target.object.source_rect = Rect2(frame.source.position + crop.position, crop.size)
				target.object.glow_rect = seat.rect
				result.append(target)
				break
		for home_id in Layout.data().get("door_openings", {}):
			if Layout.home_area(str(home_id)) != room or not SettlementWorld.home_ready(str(home_id),state): continue
			var opening: Dictionary = Layout.data().door_openings[home_id]
			for index in range(objects.size()):
				var building: Dictionary = objects[index]
				if str(building.id) != str(opening.building): continue
				if opening.has("prop_key") and str(building.get("key","")) != str(opening.prop_key): continue
				var frame: Dictionary = Sprites.object_frame(building)
				if frame.is_empty(): continue
				var crop: Rect2 = Layout.rect(opening.rect)
				var door: Rect2 = Rect2(building.rect.position + crop.position, crop.size)
				var title: String = "Tu casa" if home_id == "player" else "Casa de " + str(HOME_NAMES.get(home_id, home_id))
				var target: Dictionary = _target(room + ":door:" + str(home_id), "door", title, "entrar" if home_id == "player" else "tocar", building, {}, index)
				target.rect = door
				target.home_id = str(home_id)
				# Preserve the actual building object; glow reads only its doorway crop.
				target.object.source_rect = Rect2(frame.source.position + crop.position, crop.size)
				target.object.glow_rect = door
				result.append(target)
				break
	else:
		# The exit mat is drawn as ground, outside scenery_objects; use the same native geometry.
		var exit_object: Dictionary = Sprites._native_object(Sprites._object("exit_mat", Layout.rect(Layout.section(room).exit_mat), 108, Sprites._accent(room)))
		exit_object.key = "exit_mat"
		var exit_item := {"id": "exit", "type": "exit", "title": "Salida a la colonia", "rect": exit_object.rect, "stand_at": Layout.point(Layout.data().exit)}
		result.append(_target(room + ":exit", "exit", "Salida a la colonia", "salir", exit_object, exit_item, -1))
	return result

static func pick(point: Vector2, room: String, project_state: Dictionary = {}) -> Dictionary:
	if not point.is_finite() or not Sprites.WORLD_RECT.has_point(point): return {}
	if not Layout.is_outdoor(room) and not Layout.data().doors.has(room): return {}
	if Layout.is_outdoor(room):
		for link in Layout.exits(room):
			var region := Rect2(link.at-Vector2(14,14),Vector2(28,28))
			if region.has_point(point):
				var gate: Dictionary = SettlementWorld.gate_target(room,link,project_state)
				if not gate.is_empty(): return gate
				return {"key":room+":area:"+str(link.id),"kind":"area","title":Layout.area_title(link.to),"action":"ir","exit_id":link.id,"to":link.to,"spawn":link.spawn,"rect":region}
	var objects: Array[Dictionary] = Sprites.scenery_objects(room, project_state)
	var candidates: Array[Dictionary] = _targets(room, project_state, objects)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a._y),float(b._y)) and int(a._index)==int(b._index): return a.kind=="settlement" and b.kind!="settlement"
		return int(a._index) > int(b._index) if is_equal_approx(float(a._y), float(b._y)) else float(a._y) > float(b._y))
	for target in candidates:
		if not target.rect.has_point(point): continue
		# Foreground scenery can hide an action even when it has no action of its own.
		# Native rectangles avoid texture readbacks in this pointer-frequency path.
		for index in range(objects.size()):
			# A doorway or seat is part of its source sprite; that sprite cannot hide itself.
			if index == int(target._index): continue
			var object: Dictionary = objects[index]
			var in_front: bool = index > int(target._index) if is_equal_approx(float(object.y), float(target._y)) else float(object.y) > float(target._y)
			if in_front and object.rect.has_point(point): return {}
		target.erase("_y")
		target.erase("_index")
		return target
	return {}
