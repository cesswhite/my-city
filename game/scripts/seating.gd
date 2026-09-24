extends RefCounted
## Seats are visual anchors. Logical feet always remain at the walkable stand_at.
const Layout = preload("res://scripts/world_layout.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
static var _seats: Dictionary = {}
static var _manifest_revision: int = -1

static func _seat(object: Dictionary, suffix: String, title: String, source: Rect2, hip: Vector2, stand: Vector2, facing: Vector2, behind: bool = false) -> Dictionary:
	var origin: Vector2 = object.rect.position
	return {"id": str(object.key) + "_" + suffix, "prop_key": str(object.key), "title": title,
		"rect": Rect2(origin + source.position, source.size), "source_rect": source,
		"stand_at": origin + stand, "anchor": origin + hip + Vector2(0,5),
		"facing": facing, "sort_y": float(object.y) + (-0.25 if behind else 0.25)}

static func _ensure_seats(room: String = "street") -> void:
	if not Layout.is_outdoor(room): return
	var revision: int = Sprites.manifest_revision()
	if _manifest_revision != revision:
		_manifest_revision = revision
		_seats.clear()
	if not _seats.has(room):
		_seats[room] = []
		for object: Dictionary in Sprites.scenery_objects(room):
			match str(object.id):
				"cafe_table":
					_seats[room].append(_seat(object,"left","Banquito del café",Rect2(3,10,8,6),Vector2(7,12),Vector2(-7,19),Vector2.RIGHT))
					_seats[room].append(_seat(object,"right","Banquito del café",Rect2(28,10,7,6),Vector2(31,12),Vector2(45,19),Vector2.LEFT))
				"bench":
					_seats[room].append(_seat(object,"front","Banco",Rect2(8,8,20,5),Vector2(18,10),Vector2(18,23),Vector2.DOWN))
				"fountain":
					# The central rear rim is hidden by the spout. Its visible left
					# segment is the northern seat; no click area covers the statue.
					var north_rim := Rect2(18,9,5,3) if Sprites.uses_revised_art("fountain") else Rect2(18,9,6,3)
					_seats[room].append(_seat(object,"north","Borde norte de la fuente",north_rim,Vector2(21,10),Vector2(21,13),Vector2.UP,true))
					_seats[room].append(_seat(object,"south","Borde sur de la fuente",Rect2(25,32,11,6),Vector2(30,33),Vector2(30,51),Vector2.DOWN))
					_seats[room].append(_seat(object,"west","Borde izquierdo de la fuente",Rect2(2,19,6,9),Vector2(5,23),Vector2(-8,28),Vector2.LEFT))
					_seats[room].append(_seat(object,"east","Borde derecho de la fuente",Rect2(53,19,6,9),Vector2(55,23),Vector2(69,28),Vector2.RIGHT))

static func seats(room: String = "street") -> Array[Dictionary]:
	_ensure_seats(room)
	var result: Array[Dictionary] = []
	for source in _seats.get(room, []):
		var seat: Dictionary = source.duplicate(true)
		seat.room = room
		if room != "street": seat.id = room + ":" + str(seat.id)
		result.append(seat)
	return result

static func get_seat(id: String) -> Dictionary:
	var room: String = id.get_slice(":",0) if id.contains(":") else "street"
	for seat in seats(room):
		if seat.id == id: return seat
	return {}

static func nearest(point: Vector2, max_distance: float = 16.0, room: String = "street") -> Dictionary:
	if not point.is_finite() or not is_finite(max_distance) or max_distance < 0.0: return {}
	var result: Dictionary = {}
	var closest: float = max_distance
	for seat in seats(room):
		var distance: float = point.distance_to(seat.stand_at)
		if distance <= closest:
			closest = distance
			result = seat
	return result.duplicate()

static func actor_rect(seat: Dictionary) -> Rect2:
	var anchor = seat.get("anchor")
	if not anchor is Vector2 or not anchor.is_finite(): return Rect2()
	return Rect2(anchor.round() - Vector2(12,28), Vector2(24,28))

static func _piece(canvas: CanvasItem, frame: Dictionary, source: Rect2, at: Vector2, transpose: bool = false) -> void:
	var region := Rect2(frame.source.position + source.position, source.size)
	if not frame.source.encloses(region): return
	var size := Vector2(source.size.y, source.size.x) if transpose else source.size
	canvas.draw_texture_rect_region(frame.texture, Rect2(at.round(), size), region, frame.get("tint",Color.WHITE), transpose)

static func draw_person(canvas: CanvasItem, seat: Dictionary, appearance: Dictionary) -> void:
	var bounds: Rect2 = actor_rect(seat)
	if not bounds.has_area(): return
	var facing: Vector2 = seat.get("facing",Vector2.DOWN)
	var hip: Vector2 = seat.anchor.round() - Vector2(0,5)
	var origin: Vector2 = hip - Vector2(12,23)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for layer: Dictionary in Sprites.character_layers(appearance,false,0,facing):
		var offset: Vector2 = layer.get("offset",Vector2.ZERO)
		# Head, hair, beard, hat, arms and shirt keep the exact native proportions.
		_piece(canvas,layer,Rect2(0,0,24,23),origin + offset)
		if layer.id not in ["char_pants","char_details"]: continue
		_piece(canvas,layer,Rect2(9,23,6,2),hip + Vector2(-3,-1))
		if facing in [Vector2.LEFT,Vector2.RIGHT]:
			var side: int = -1 if facing == Vector2.LEFT else 1
			var source_x: int = 10 if side < 0 else 12
			var knee_x: int = -5 if side < 0 else 3
			# A native leg strip transposed into the thigh, then a vertical shin.
			_piece(canvas,layer,Rect2(source_x,24,2,4),hip + Vector2(-5 if side < 0 else 1,0),true)
			_piece(canvas,layer,Rect2(source_x,25,2,3),hip + Vector2(knee_x,1))
			_piece(canvas,layer,Rect2(9 if side < 0 else 12,28,3,2),hip + Vector2(knee_x - (1 if side < 0 else 0),3))
		else:
			# Bent knees sit just beyond the seat; two shortened shins hang down.
			for side in [-1,1]:
				var source_x: int = 10 if side < 0 else 12
				var knee_x: int = -4 if side < 0 else 2
				_piece(canvas,layer,Rect2(source_x,24,2,4),hip + Vector2(-4 if side < 0 else 0,0),true)
				_piece(canvas,layer,Rect2(source_x,25,2,3),hip + Vector2(knee_x,1))
				_piece(canvas,layer,Rect2(9 if side < 0 else 12,28,3,2),hip + Vector2(knee_x,3))
