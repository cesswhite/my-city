extends RefCounted
## Interaction descriptions are independent of generated visual assets.
const Sprites = preload("res://scripts/sprite_art.gd")
const SettlementWorld = preload("res://scripts/settlement_world.gd")
const Layout = preload("res://scripts/world_layout.gd")
const SKIN_COLORS = Sprites.SKIN_COLORS
const HAIR_COLORS = Sprites.HAIR_COLORS
const EYE_COLORS = Sprites.EYE_COLORS
const SHIRT_COLORS = Sprites.SHIRT_COLORS
const PANTS_COLORS = Sprites.PANTS_COLORS

static func _with_geometry(item: Dictionary, key: String, room: String) -> Dictionary:
	item.merge(Layout.interaction(key, room), true)
	return item

static func street_items(room: String = "street", state: Dictionary = {}) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if room == "street":
		items.append(_with_geometry({"id": "shop", "type": "shop", "title": "Tienda de la colonia", "text": "Un pequeño mostrador de herramientas, semillas e ingredientes para poner en práctica lo aprendido."}, "shop", room))
	if not Layout.is_outdoor(room): return items
	for id in Layout.section(room).get("interactions", {}):
		var detail: Dictionary = Layout.section(room).interactions[id]
		var blocked := false
		for prop in Layout.props(room):
			if prop.key == detail.key and not SettlementWorld.building_ready(str(prop.get("settlement_building","")),state): blocked = true
		if blocked: continue
		if not detail.has("title") or not detail.has("text"): continue
		items.append(_with_geometry({"id": str(id), "type": str(detail.get("type", "lore")), "title": str(detail.title), "text": str(detail.text)}, str(id), room))
	return items

static func interior_items(home_id: String) -> Array[Dictionary]:
	if home_id == "player":
		return [
			_with_geometry({"id": "bed", "type": "sleep", "title": "Tu cama", "text": "Duerme para recuperar energía y empezar el día descansado."}, "bed", home_id),
			_with_geometry({"id": "closet", "type": "closet", "title": "Tu clóset", "text": "Personaliza tu aspecto y prueba ropa y accesorios."}, "closet", home_id),
			_with_geometry({"id": "bicycle", "type": "bicycle", "station": "bicycle", "title": "Tu bicicleta", "text": "Una bicicleta espera en el soporte de reparación. Revisa su estado y aplica lo que aprendas en el taller."}, "bicycle", home_id),
			_with_geometry({"id": "planting", "type": "station", "station": "planting", "title": "Tu jardinera", "text": "Tres espacios para empezar un pequeño huerto. Las semillas necesitan tierra, agua y los pasos adecuados."}, "planting", home_id),
			_with_geometry({"id": "tea_station", "type": "station", "station": "tea_station", "title": "Tu mesa de té", "text": "Una tetera y dos tazas esperan la primera receta que puedas preparar por tu cuenta."}, "tea_station", home_id),
			_with_geometry({"id": "postcard", "type": "lore", "title": "Una postal de bienvenida", "text": "Alguien deslizó una postal bajo tu puerta: «No hace falta saberlo todo al llegar. Aquí podemos aprender juntos»."}, "postcard", home_id),
		]
	var stories: Dictionary = {
		"cesar": ["Semillas del campo", "César guarda semillas en sobres fechados. En uno escribió: «Las primeras que sembré con papá».", "Foto del amanecer", "Una foto pequeña muestra a César y a su papá junto a un huerto. La esquina está reparada con cinta.", "Cuaderno de plantas", "Dibujos de hojas, fechas de riego y una nota: «Preguntar a Lupita qué le gustaría cultivar»."],
		"lupita": ["La mesa para todos", "Una canasta contiene manteles y tarjetas en blanco. Lupita dejó un lugar libre para alguien que todavía no conoce.", "Retrato de familia", "Lupita aparece con su mamá y su papá en una plaza de ciudad. Detrás hay una invitación a su primera comida vecinal.", "Libreta de encuentros", "Una libreta llena de ideas para reunir al barrio. En la última página: «También reservar una tarde tranquila»."],
		"mateo": ["Herramientas de los abuelos", "Mateo conserva las herramientas del taller familiar en su mesa de trabajo. Una nota dice: «Bicicleta de César: revisar frenos juntos».", "El taller de los abuelos", "Una fotografía antigua del primer taller familiar. Mateo conserva el mismo delantal colgado junto a ella.", "Manual con anotaciones", "Un manual de reparación tiene una nota al margen: «Explicarlo despacio también es parte del oficio»."],
		"ines": ["La tetera viajera", "Esta tetera acompañó a Inés en varias mudanzas. La receta a su lado termina con: «Servir y escuchar». ", "Postales de otros cafés", "Tres postales de ciudades distintas comparten una palabra escrita a mano: hogar.", "Recetas e historias", "Entre recetas de té hay pequeñas historias de visitantes. Cada entrada conserva el nombre de quien la contó."],
		"alma": ["El barrio que cambia", "Un caballete sostiene una pintura de esta misma colonia. Hay un rectángulo vacío para pintar al nuevo habitante.", "La primera fotografía", "Alma guardó una foto del barrio antes de abrir el café. Detrás escribió: «Recordar también es cuidar». ", "Álbum de la colonia", "Un álbum mezcla fotos, dibujos y recortes. En una esquina aparece un diminuto gato naranja escondido."],
	}
	var entry: Array = stories.get(home_id, stories.alma)
	return [
		_with_geometry({"title": "Un rincón para descansar", "text": "Una cama con una manta doblada. Cada casa conserva su propio ritmo, sus recuerdos y un espacio de calma."}, "bed", home_id),
		_with_geometry({"title": entry[0], "text": entry[1]}, "project", home_id),
		_with_geometry({"title": entry[2], "text": entry[3]}, "postcard", home_id),
		_with_geometry({"title": entry[4], "text": entry[5]}, "storage", home_id),
		_with_geometry({"title": "La mesa del comedor", "text": "Una tetera y sus tazas esperan sobre la mesa. Las sillas dejan sitio para una visita."}, "tea_station", home_id),
	]

static func draw_world(canvas: CanvasItem, font: Font, include_objects: bool = true, room: String = "street", state: Dictionary = {}) -> void:
	Sprites.draw_world(canvas, font, include_objects, room, state)

static func draw_interior(canvas: CanvasItem, font: Font, home_id: String, state: Dictionary = {}, include_objects: bool = true) -> void:
	Sprites.draw_interior(canvas, font, home_id, state, include_objects)

static func draw_person(canvas: CanvasItem, pos: Vector2, appearance: Dictionary, scale_px: int = 1, walking: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN) -> void:
	Sprites.draw_person(canvas, pos, appearance, scale_px, walking, phase, direction)

static func draw_bicycle(canvas: CanvasItem, pos: Vector2, appearance: Dictionary, walking: bool = false, phase: int = 0, direction: Vector2 = Vector2.DOWN) -> void:
	Sprites.draw_bicycle(canvas, pos, appearance, walking, phase, direction)
