extends SceneTree
## Pointer geometry and semantic targets only: no scene, save, timer or network.
const Interactions = preload("res://scripts/world_interactions.gd")
const Art = preload("res://scripts/pixel_art.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func object_for(room: String, key: String, state: Dictionary = {}) -> Dictionary:
	for object in Sprites.scenery_objects(room, state):
		if object.key == key: return object
	return {}

func run() -> void:
	var layout_before: String = JSON.stringify(Layout.data())
	expect(Sprites.reload_manifest() == OK, "real sprite manifest loads for native pointer geometry")
	for room in ["player", "mateo", "cesar", "lupita", "ines", "alma"]:
		var semantic_keys: Dictionary = {}
		for item in Art.interior_items(room):
			var interaction_id: String = Interactions._interaction_id(item,room)
			var prop_key: String = str(Layout.section(room).interactions[interaction_id].key)
			var matching: Array[Dictionary] = []
			for target in Interactions._targets(room, {}):
				if (target.kind == "item" and target.item == item) or (target.kind == "environment" and target.object.key == prop_key): matching.append(target)
			expect(not matching.is_empty(), "every described item has a visible target or household card: " + room + ":" + str(item.title))
			if matching.is_empty(): continue
			var selectable := false
			var actual_visuals := true
			var accessible := true
			var lore_retained := false
			var stable_keys := true
			for candidate in matching:
				var native: Dictionary = object_for(room, str(candidate.object.key))
				actual_visuals = actual_visuals and candidate.rect == native.rect and candidate.object == native
				var picked: Dictionary = Interactions.pick(candidate.rect.get_center(), room)
				selectable = selectable or picked.get("key") == candidate.key
				var expected_key: String = room+":environment:"+prop_key if candidate.kind == "environment" else room+":item:"+interaction_id
				stable_keys = stable_keys and candidate.key == expected_key
				lore_retained = lore_retained or str(candidate.item.text).strip_edges() == str(item.text).strip_edges()
				for page: Dictionary in candidate.item.get("pages",[]):
					lore_retained = lore_retained or (str(page.title) == str(item.title) and str(page.text).strip_edges() == str(item.text).strip_edges())
				var entry: Vector2 = Layout.point(Layout.data().entry)
				var route: Array[Vector2] = Navigation.route(entry,candidate.item.stand_at,room)
				accessible = accessible and not route.is_empty() and route[-1].distance_to(candidate.item.stand_at) < 0.01
				semantic_keys[prop_key] = true
			expect(actual_visuals and selectable and stable_keys, "item uses the actual native sprite, stable identity and selectable surface: " + room + ":" + str(item.title))
			expect(accessible and lore_retained, "target retains accessible approach and its original lore, directly or as an album page: " + room + ":" + str(item.title))
		var exit_target: Dictionary = Interactions.pick(Layout.rect(Layout.section(room).exit_mat).get_center(), room)
		expect(exit_target.get("kind") == "exit" and exit_target.get("action") == "salir" and exit_target.item.stand_at == Layout.point(Layout.data().exit), "interior exit mat is a real leave action: " + room)
		expect(semantic_keys.size() == (6 if room == "player" else 5), "each original semantic prop remains represented once: " + room)
	var closet: Dictionary = object_for("player", "cabinet")
	var closet_hit: Dictionary = Interactions.pick(closet.rect.get_center(), "player")
	expect(closet_hit.get("key") == "player:item:closet" and closet_hit.get("kind") == "item" and closet_hit.get("action") == "personalizar" and closet_hit.get("title") == "Tu clóset", "the existing player cabinet is the real customization target")
	expect(closet_hit.object == closet and closet_hit.item.id == "closet" and closet_hit.item.type == "closet" and closet_hit.item.stand_at == Layout.stand_at("closet", "player"), "closet payload keeps native sprite, stable identity and physical approach together")
	var closet_point: Vector2 = Layout.stand_at("closet", "player")
	expect(Navigation.is_walkable(closet_point, "player") and not Navigation.is_walkable(Vector2(346,143), "player"), "closet approach stays walkable while the actual cabinet remains solid")
	for room in ["mateo", "cesar", "lupita", "ines", "alma"]:
		var has_closet := false
		for item: Dictionary in Art.interior_items(room):
			if item.get("type", "") == "closet" or item.get("id", "") == "closet": has_closet = true
		var cabinet: Dictionary = object_for(room, "cabinet")
		expect(not has_closet and Layout.interaction("closet", room).is_empty() and Interactions.pick(cabinet.rect.get_center(), room).get("action", "") != "personalizar", "neighbor's cabinet never grants customization: " + room)
	var bed: Dictionary = object_for("player", "bed")
	expect(Interactions.pick(bed.rect.get_center(), "player").action == "dormir" and Interactions.pick(bed.rect.get_center(), "mateo").action == "inspeccionar", "only the player's bed advertises sleeping")
	var tea: Dictionary = object_for("player", "tea")
	var cup: Dictionary = Interactions.pick(tea.rect.get_center(), "player")
	expect(cup.object.key == "tea" and cup.action == "preparar té", "the cup wins its overlap with the table according to visible depth")
	var table: Dictionary = object_for("player", "table")
	var table_hit: Dictionary = Interactions.pick(table.rect.position + Vector2(2, table.rect.size.y - 2), "player")
	expect(table_hit.object.key == "table" and table_hit.key == cup.key, "the supporting table remains part of the same tea interaction")
	var project_table: Dictionary = object_for("mateo", "project_table")
	var support_hit: Dictionary = Interactions.pick(project_table.rect.position + Vector2(2, project_table.rect.size.y - 2), "mateo")
	expect(support_hit.get("kind") == "item" and support_hit.object.key == "project_table" and support_hit.action == "inspeccionar", "a neighbor's project support remains inspectable across its visible table")
	for state in [{}, {"bicycle_repaired": true, "garden_planted": true, "tea_ready": true}]:
		for spec in [["project", "bicycle_fixed" if state.get("bicycle_repaired", false) else "bicycle_broken", "ver bicicleta"], ["storage", "planter_seeded" if state.get("garden_planted", false) else "planter", "cultivar"], ["tea", "tea_ready" if state.get("tea_ready", false) else "tea_set", "preparar té"]]:
			var object: Dictionary = object_for("player", spec[0], state)
			var target: Dictionary = Interactions.pick(object.rect.get_center(), "player", state)
			expect(target.object.id == spec[1] and target.rect == object.rect and target.action == spec[2], "project state picks its currently rendered PNG: " + str(spec[1]))
	var bicycle: Dictionary = object_for("player", "project")
	expect(Interactions.pick(bicycle.rect.get_center(), "player", {"bicycle_away": true}).is_empty(), "an absent bicycle cannot be hovered through its old layout slot")
	for home_id in Layout.data().door_openings:
		var opening: Dictionary = Layout.data().door_openings[home_id]
		var area: String = Layout.home_area(home_id)
		var building: Dictionary = object_for(area, opening.building)
		var local: Rect2 = Layout.rect(opening.rect)
		var rect: Rect2 = Rect2(building.rect.position + local.position, local.size)
		var target: Dictionary = Interactions.pick(rect.get_center(), area)
		expect(target.get("kind") == "door" and target.get("home_id") == home_id and target.rect == rect, "door selection matches the measured visual opening: " + str(home_id))
		var frame: Dictionary = Sprites.object_frame(building)
		expect(target.object.rect == building.rect and target.object.glow_rect == rect and target.object.source_rect == Rect2(frame.source.position + local.position, local.size), "door glow keeps the real building but crops only the doorway: " + str(home_id))
		expect(not Interactions.pick(building.rect.position + Vector2(3, 3), area).get("kind", "") == "door", "the roof cannot select or illuminate an entire house: " + str(home_id))
	var shop: Dictionary = object_for("street", "shop")
	var shop_target: Dictionary = Interactions.pick(shop.rect.get_center(), "street")
	expect(shop_target.kind == "shop" and shop_target.action == "comprar" and shop_target.item == Art.street_items()[0], "the shop shares one complete target for hovering and buying")
	var tree: Dictionary = object_for("street", "tree_west")
	var covered_shop: Rect2 = shop.rect.intersection(tree.rect)
	var covered_hit: Dictionary = Interactions.pick(covered_shop.get_center(), "street")
	expect(covered_shop.has_area() and covered_hit.get("object",{}).get("key") == tree.key and covered_hit.key != shop_target.key, "foreground tree observation occludes the shop behind it")
	for spec in [["street", "fountain"], ["street", "lamp"], ["street", "tree_south"]]:
		var key: String = spec[1]
		var observable: Dictionary = object_for(spec[0],key)
		var hit: Dictionary = Interactions.pick(observable.rect.get_center(),spec[0])
		expect(hit.get("kind") == "item" and hit.get("action") == "observar" and hit.get("key") == str(spec[0])+":environment:"+key and not str(hit.get("item",{}).get("text","")).is_empty(), "outdoor observation describes its real prop without advertising a seat or transaction: "+key)
	var row: Dictionary = object_for("gardens","garden_row_north")
	expect(Interactions.pick(row.rect.get_center(),"gardens").is_empty(),"a crop row without an active settlement offer has no invented action")
	for spec in [["window","curtains","usar cortinas"],["plant","water","cuidar"]]:
		var object: Dictionary = object_for("player",spec[0])
		var target: Dictionary = Interactions.pick(object.rect.get_center(),"player")
		var actions: Array = target.get("item",{}).get("actions",[])
		expect(target.get("kind") == "environment" and target.get("key") == "player:environment:"+str(spec[0]) and target.get("action") == spec[2] and actions.size() == 1 and actions[0].id == spec[1],"household target exposes exactly the object's supported action: "+str(spec[0]))
	var chair: Dictionary = object_for("player","chair")
	expect(Interactions.pick(chair.rect.get_center(),"player").is_empty(),"decorative chair still does not advertise a made-up action")
	expect(Interactions.pick(Vector2.INF, "street").is_empty() and Interactions.pick(Vector2(NAN, 100), "street").is_empty(), "nonfinite pointer positions produce no target")
	expect(Interactions.pick(Vector2.ZERO, "street").is_empty() and Interactions.pick(bed.rect.get_center(), "unknown").is_empty(), "outside-world positions and unknown rooms produce no target")
	shop_target.item.title = "changed by a caller"
	shop_target.object.rect = Rect2()
	expect(Interactions.pick(shop.rect.get_center(), "street").item.title == Art.street_items()[0].title, "returned targets cannot mutate subsequent interaction state")
	expect(JSON.stringify(Layout.data()) == layout_before, "resolving all interactions never mutates shared layout data")
	print("WORLD INTERACTIONS: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
