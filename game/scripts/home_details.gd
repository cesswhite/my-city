extends RefCounted
## Authored, publicly displayed household content. No biography or social ledger reads.
const Art = preload("res://scripts/pixel_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
const HOMES := ["player", "cesar", "lupita", "mateo", "ines", "alma"]
static var _profiles: Dictionary = {}
static var _objects: Dictionary = {}

static func profiles() -> Dictionary:
	if _profiles.is_empty(): _profiles = _build_profiles()
	return _profiles.duplicate(true)

static func _build_profiles() -> Dictionary:
	var result := {}
	for room: String in HOMES:
		var items: Array[Dictionary] = Art.interior_items(room)
		if room == "player":
			result[room] = {"pages": [
				_page("welcome", items[5].title, items[5].text, ["photo", "notebooks"]),
				_page("practice", "Un lugar para aprender", "Tu casa tiene una bicicleta, una jardinera y una mesa de té para practicar lo aprendido paso a paso.", ["bicycle_broken", "planter", "tea_set"]),
			]}
			continue
		result[room] = {"pages": [
			_page("photograph", items[2].title, items[2].text, ["photo", _project_asset(room)]),
			_page("project", items[1].title, items[1].text, [_project_asset(room), "notebooks"]),
			_page("notebook", items[3].title, items[3].text, ["notebooks", "photo"]),
		]}
	# These are compositions of existing sprites, not invented documentary photos.
	# The descriptions remain exactly the displayed lore of Alma's three objects.
	result.alma.pages[0].scene = _vignette("tile_grass", "tile_grass", [
		{"asset":"tile_sand", "at":[64,32]}, {"asset":"tree_small", "at":[8,0]},
		{"asset":"flowerpot", "at":[136,28]}, {"asset":"bench", "at":[88,42]}])
	result.alma.pages[1].scene = _vignette("tile_wall_lavender", "tile_wood", [
		{"asset":"plant", "at":[12,33]}, {"asset":"project_painting", "at":[72,24]},
		{"asset":"table", "at":[110,35]}, {"asset":"notebooks", "at":[114,14]}])
	result.alma.pages[2].scene = _vignette("tile_wood", "tile_wood", [
		{"asset":"photo", "at":[25,18]}, {"asset":"notebooks", "at":[66,26]},
		{"asset":"project_painting", "at":[118,20]}])
	return result

static func _vignette(upper: String, lower: String, objects: Array) -> Array:
	var result: Array = []
	for row in range(2):
		for column in range(5):
			result.append({"asset":upper if row == 0 else lower, "at":[column * 32, row * 32]})
	result.append_array(objects)
	return result

static func _project_asset(room: String) -> String:
	return {"cesar":"project_seeds", "lupita":"project_basket", "mateo":"project_tools", "ines":"tea_set", "alma":"project_painting"}.get(room, "notebooks")

static func _scene(assets: Array) -> Array:
	var result: Array = []
	for asset: String in assets: result.append({"asset": asset})
	return result

static func _page(id: String, title: String, text: String, assets: Array) -> Dictionary:
	return {"id": id, "title": title, "text": text.strip_edges(), "scene": _scene(assets)}

static func for_object(object: Dictionary, room: String) -> Dictionary:
	var cache_key: String = room + ":" + str(object.get("key", object.get("prop_key", ""))) + ":" + str(object.get("id", ""))
	if not _objects.has(cache_key): _objects[cache_key] = _details(object, room)
	return _objects[cache_key].duplicate(true)

static func _details(object: Dictionary, room: String) -> Dictionary:
	if room not in HOMES: return {}
	var key: String = str(object.get("key", object.get("prop_key", "")))
	var asset: String = str(object.get("id", ""))
	# The original player routes own sleep, appearance, verified practice and brewing.
	if key == "bed" or (room == "player" and key in ["cabinet", "project", "storage", "table", "tea"]): return {}
	var result := {"id": key, "prop_key": key, "room": room, "environment": true, "actions": [], "pages": []}
	if asset == "plant":
		result.merge({"title":"Una planta junto a ti", "text":"Mira la tierra antes de regar. Si sigue húmeda, la planta no necesita más agua.", "actions":[{"id":"water", "label":"Regar"}]}, true)
	elif asset == "window":
		result.merge({"title":"Ventana del dormitorio" if key == "window" else "Ventana del rincón de trabajo", "text":"Las cortinas de esta ventana se pueden abrir o cerrar por separado.", "actions":[{"id":"curtains", "label":"Cerrar cortinas"}]}, true)
	elif key in ["photo", "storage", "library", "notebooks"]:
		var pages: Array = profiles()[room].pages
		result.merge({"title":"Recuerdos de tu casa" if room == "player" else ("Álbum de la colonia" if room == "alma" else "Fotos y recuerdos"), "text":"Puedes mirar las páginas y los recuerdos que están a la vista.", "actions":[{"id":"album", "label":"Ver recuerdos"}], "pages":pages}, true)
	elif key == "project":
		var detail: Dictionary = Art.interior_items(room)[1]
		result.merge({"title":detail.title, "text":detail.text.strip_edges(), "actions":[{"id":"details", "label":"Mirar detalles"}], "pages":[profiles()[room].pages[1]]}, true)
	elif key == "cabinet":
		result.merge({"title":"El armario de la casa", "text":"La ropa y los objetos personales están guardados. Puedes mirar el mueble sin abrir los cajones."}, true)
	else: return {}
	return result

static func page_for(room: String, prop_key: String, page_id: String) -> Dictionary:
	for object: Dictionary in Layout.props(room):
		if str(object.key) != prop_key: continue
		for page: Dictionary in for_object(object, room).get("pages", []):
			if page.id == page_id: return page.duplicate(true)
	return {}
