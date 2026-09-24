extends RefCounted
## Physical targets only. Offers never roll events or change a saved environmental state.
const Layout = preload("res://scripts/world_layout.gd")
const Catalog = preload("res://scripts/environmental_catalog.gd")
const HomeDetails = preload("res://scripts/home_details.gd")
const Navigation = preload("res://scripts/navigation.gd")

static func _target(room: String, object: Dictionary, item: Dictionary, index: int, kind: String = "environment") -> Dictionary:
	var value: Dictionary = item.duplicate(true)
	value.room = room
	value.rect = object.rect
	return {"key":room+":environment:"+str(object.key), "kind":kind,
		"title":str(value.title), "action":str(value.get("action","mirar")),
		"item":value, "object":object.duplicate(true), "rect":object.rect,
		"_index":index, "_y":float(object.y)}

static func targets(room: String, state: Dictionary, objects: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var originals := {}
	for prop: Dictionary in Layout.props(room): originals[str(prop.key)] = prop
	for index in range(objects.size()):
		var object: Dictionary = objects[index]
		var key: String = str(object.get("key",""))
		if object.has("environment_fruit"):
			var golden: bool = str(object.get("fruit_kind","")) == "golden"
			var item := {"id":key,"prop_key":key,"environment":true,"fruit_id":str(object.environment_fruit),
				"title":"Una manzana dorada" if golden else "Una manzana caída", "action":"recoger",
				"text":"Un brillo entre las hojas." if golden else "Una pequeña sorpresa a la sombra del árbol.",
				"stand_at":object.rect.get_center()}
			result.append(_target(room,object,item,index,"fruit"))
			continue
		if Layout.is_outdoor(room):
			var observation: Dictionary = _outdoor_detail(object,room,state)
			if not observation.is_empty():
				observation.stand_at = Catalog.stand_for(room,key) if originals.has(key) else Navigation.recover_position(object.support_point+Vector2(12,6),room)
				var target: Dictionary = _target(room,object,observation,index,"item")
				if str(object.id) == "fountain":
					# Water is distinct from the four usable stone-rim seats.
					var water := Rect2(object.rect.position+Vector2(22,20),Vector2(17,8))
					target.rect = water
					target.object.glow_rect = water
					target.object.source_rect = Rect2(22,20,17,8)
				result.append(target)
			continue
		if not originals.has(key): continue
		var item: Dictionary = HomeDetails.for_object(originals[key],room)
		if item.is_empty(): continue
		item.stand_at = Catalog.stand_for(room,key)
		item.action = "mirar"
		if not item.get("actions",[]).is_empty():
			item.action = {"water":"cuidar", "curtains":"usar cortinas", "album":"ver recuerdos", "details":"examinar"}.get(str(item.actions[0].id),"mirar")
		result.append(_target(room,object,item,index))
	return result

static func _outdoor_detail(object: Dictionary, room: String, state: Dictionary) -> Dictionary:
	if object.has("settlement_node") or object.has("settlement_building") or object.has("construction_stage"): return {}
	var minute: int = int(state.get("environment",{}).get("minute",720)) % 1440
	var night: bool = minute >= 1140 or minute < 360
	var result := {"id":str(object.key),"title":"","text":"","action":"observar"}
	if object.has("environment_tree"):
		var stage: int = int(object.environment_tree.stage)
		result.title = "Un árbol que crece"
		result.text = ["Una semilla descansa bajo la tierra. El lugar seguirá cambiando cuando vuelvas.","Asoman dos hojas nuevas. Todavía es un brote muy pequeño.","El tallo empieza a sostener sus primeras ramas.","Ya tiene un tronco joven. Conviene dejar espacio alrededor de sus raíces.","La copa empieza a dar sombra al sendero.","Las ramas forman una copa amplia. Este rincón ha cambiado desde que empezó a crecer."][clampi(stage,0,5)]
		return result
	match str(object.id):
		"tree", "tree_small":
			result.title = "Sombra del huerto" if room == "gardens" else "Un rincón entre árboles"
			result.text = "Las hojas guardan un rincón de sombra. De vez en cuando cae una fruta madura junto a alguno de los árboles del barrio."
			if night: result.text = "Entre las hojas se ve un poco de cielo. A esta hora las sombras se confunden con el sendero."
		"flowerpot", "plant":
			result.title = "Flores junto al camino"
			result.text = "Una maceta marca la entrada sin bloquear el paso. Sus hojas se mueven un poco cuando llega una ráfaga."
		"lamp":
			result.title = "La luz del barrio"
			result.text = "La farola ilumina el suelo con una luz cálida. Se apagará al amanecer." if night else "La farola está apagada. Al caer la tarde volverá a iluminar este camino."
		"bunting":
			result.title = "Papel de colores"
			result.text = "Cada banderín tiene sus propios recortes. La cuerda permanece tensa mientras el papel responde a las ráfagas."
		"fountain":
			result.title = "El agua de la plaza"
			result.text = "Las ondas se cruzan alrededor del surtidor y vuelven a deshacerse. Puedes sentarte en los bordes de piedra."
			if night and int(state.get("environment",{}).get("minute",0)) / 1440 % 7 == 3:
				result.text = "Por un instante, el reflejo de una farola parece una estrella dentro del agua. La siguiente onda se la lleva."
		_: return {}
	return result
