extends RefCounted
## Lighting uses the saved simulation clock; presentation never advances time.
const Layout = preload("res://scripts/world_layout.gd")
const SettlementWorld = preload("res://scripts/settlement_world.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const NIGHT := Color(0.38, 0.46, 0.66)
# Measured glass only, grouped by window. Frames, shutters and plants stay dark.
const WINDOW_PANES := {
	"cafe": [
		[[19,59,4,5],[24,59,4,5],[29,59,3,5],[19,65,4,4],[24,65,4,4],[29,65,3,4]],
		[[72,59,4,5],[77,59,4,5],[82,59,4,5],[72,65,4,4],[77,65,4,4],[82,65,4,4]]],
	"homes": [[[44,45,3,4],[48,45,4,4],[44,51,3,3],[48,51,4,3]]],
	"alma_home": [[[46,47,2,4],[49,47,3,4],[46,52,2,3],[49,52,3,3]]],
	"workshop": [[[79,39,4,5],[84,39,4,5],[89,39,3,5],[93,39,4,5],[79,45,4,5],[84,45,4,5],[89,45,3,5],[93,45,4,5],[79,51,4,2],[84,51,4,2],[89,51,3,2],[93,51,4,2]]],
	"player_home": [
		[[12,41,3,4],[16,41,2,4],[12,46,3,3],[16,46,2,3]],
		[[52,41,3,4],[56,41,2,4],[52,46,3,3],[56,46,2,3]]]
}
const INDOOR_PANES := [[9,6,4,7],[15,6,4,7],[7,15,6,7],[15,15,6,7],[8,11,1,2],[19,10,1,3]]
# Native replacement panes, measured between the actual mullions. The new café
# has two columns per window and the workshop three; neither uses the old grid.
const REVISED_WINDOW_PANES := {
	"cafe": [
		[[21,59,4,5],[27,59,4,5],[21,66,4,3],[27,66,4,3]],
		[[73,59,4,5],[79,59,4,5],[73,66,4,3],[79,66,4,3]]],
	"homes": [[[43,44,4,4],[48,44,4,4],[43,50,4,2],[48,50,4,2]]],
	"alma_home": [[[44,46,3,4],[48,46,3,4],[44,52,3,3],[48,52,3,3]]],
	"workshop": [[[78,38,4,5],[83,38,6,5],[90,38,5,5],[78,44,4,5],[83,44,6,5],[90,44,5,5],[78,50,4,2],[83,50,6,2],[90,50,5,2]]],
	"player_home": [
		[[11,40,3,4],[15,40,3,4],[11,45,3,3],[15,45,3,3]],
		[[51,40,3,4],[55,40,3,4],[51,45,3,3],[55,45,3,3]]]
}
# Curtain edges taper across the view. Keep both cloth and wooden crossbars out
# of the night mask, including the diagonal lower curtains.
const REVISED_INDOOR_PANES := [[9,7,4,5],[10,12,3,1],[11,13,2,1],[15,7,4,3],[15,10,3,1],[15,11,2,1],[15,12,1,2],[7,16,6,1],[11,17,2,1],[12,18,1,4],[15,16,3,2],[15,18,4,1],[15,19,5,1],[15,20,6,1],[15,21,4,1]]
const REVISED_LAMP_CORE := Rect2(4, 11, 2, 4)
static var _emitters: Dictionary = {}
static var _pools: Dictionary = {}
static var _source_runs: Dictionary = {}
static var _light_regions: Dictionary = {}
static var _manifest_revision: int = -1
const LAMP_CORE := Rect2(4, 5, 2, 4)

static func window_panes(id: String) -> Array:
	return REVISED_WINDOW_PANES.get(id, []) if Sprites.uses_revised_art(id) else WINDOW_PANES.get(id, [])

static func indoor_panes() -> Array:
	return REVISED_INDOOR_PANES if Sprites.uses_revised_art("window") else INDOOR_PANES

static func lamp_core() -> Rect2:
	return REVISED_LAMP_CORE if Sprites.uses_revised_art("lamp") else LAMP_CORE

static func _emitter_key(room: String) -> String:
	_ensure_profile()
	return room

static func _ensure_profile() -> void:
	var revision: int = Sprites.manifest_revision()
	if revision == _manifest_revision: return
	_manifest_revision = revision
	_emitters.clear()
	_light_regions.clear()
	_source_runs.clear()

static func phase_at(minute: float) -> Dictionary:
	var local: float = fposmod(minute, 1440.0)
	var darkness := 1.0
	var warmth := 0.0
	if local >= 390.0 and local < 480.0:
		var dawn: float = smoothstep(390.0, 480.0, local)
		darkness = 1.0 - dawn
		warmth = sin(dawn * PI) * 0.24
	elif local >= 480.0 and local < 1050.0:
		darkness = 0.0
	elif local >= 1050.0 and local < 1200.0:
		var dusk: float = smoothstep(1050.0, 1200.0, local)
		darkness = dusk
		warmth = sin(dusk * PI) * 0.36
	var ambient: Color = Color.WHITE.lerp(NIGHT, darkness).lerp(Color(1.0, 0.73, 0.51), warmth)
	var lamp_power: float = smoothstep(0.10, 0.72, darkness)
	return {"darkness": darkness, "ambient": ambient, "lamp_power": lamp_power, "lamps_on": lamp_power > 0.01}

static func ambient_for(minute: float, room: String) -> Color:
	var phase: Dictionary = phase_at(minute)
	return phase.ambient if Layout.is_outdoor(room) else Color.WHITE.lerp(Color(0.72, 0.68, 0.61), phase.darkness)

static func _visible_source(object: Dictionary) -> Rect2:
	var frame: Dictionary = Sprites.frame_info(str(object.id))
	var source: Rect2 = object.get("source_rect", Rect2(Vector2.ZERO, frame.get("source", Rect2()).size))
	if object.has("edge_finish"):
		var width: float = float(object.edge_finish.width)
		source.size.x -= width
		if str(object.edge_finish.side) == "left": source.position.x += width
	return source

static func emitters(room: String, state: Dictionary = {}) -> Array[Dictionary]:
	var cache_key := _emitter_key(room)
	if _emitters.has(cache_key): return _available_emitters(_emitters[cache_key],state)
	var result: Array[Dictionary] = []
	for object: Dictionary in Layout.props(room):
		var rect: Rect2 = object.rect
		var requirement: String = str(object.get("settlement_building",""))
		if Layout.is_outdoor(room):
			if object.id == "lamp":
				var core_at: Vector2 = lamp_core().get_center() if Sprites.uses_revised_art("lamp") else Vector2(5, 6)
				result.append({"kind": "lamp", "at": rect.position + core_at, "ground": rect.position + Vector2(5, 36), "radius": 30.0,"building":requirement})
			elif WINDOW_PANES.has(object.id):
				for window: Array in window_panes(str(object.id)):
					var panes: Array[Rect2] = []
					var bounds := Rect2()
					for raw: Array in window:
						var pane: Rect2 = Layout.rect(raw)
						if object.has("source_rect"):
							pane = pane.intersection(_visible_source(object))
							if not pane.has_area(): continue
							pane.position -= object.source_rect.position
						pane.position += rect.position
						bounds = pane if panes.is_empty() else bounds.merge(pane)
						panes.append(pane)
					if panes.is_empty(): continue
					result.append({"kind": "window", "rect": bounds, "panes": panes, "at": bounds.get_center(), "radius": 14.0,"building":requirement})
		elif object.id == "window":
			result.append({"kind": "inside_window", "at": rect.position + Vector2(14, 15), "radius": 20.0, "room":room, "prop_key":str(object.key)})
	if not Layout.is_outdoor(room):
		var wall: Rect2 = Layout.rect(Layout.section(room).wall)
		# Reuse the existing lantern head as two small wall sconces.
		for x in [wall.position.x + 76, wall.end.x - 70]:
			result.append({"kind": "sconce", "at": Vector2(x, wall.end.y - 20), "radius": 45.0})
	_emitters[cache_key] = result
	return _available_emitters(result,state)

static func _available_emitters(base: Array[Dictionary], state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in base:
		if item.kind == "inside_window" and _curtains_closed(str(item.get("room","")),str(item.get("prop_key","")),state): continue
		if SettlementWorld.building_ready(str(item.get("building","")),state): result.append(item)
	return result

static func _curtains_closed(room: String, key: String, state: Dictionary) -> bool:
	var households: Dictionary = state.get("environment",{}).get("households",{})
	return bool(households.get(room,{}).get("curtains",{}).get(key,false))

static func draw_fixtures(canvas: CanvasItem, room: String) -> void:
	if Layout.is_outdoor(room): return
	var lamp: Dictionary = Sprites.frame_info("lamp")
	if lamp.is_empty(): return
	# The fixture belongs to the opaque world layer. Only emitted light is additive.
	for emitter: Dictionary in emitters(room):
		if emitter.kind != "sconce": continue
		var crop := Rect2(1, 4, 8, 12) if Sprites.uses_revised_art("lamp") else Rect2(1, 1, 8, 14)
		var origin: Vector2 = emitter.at - lamp_core().get_center() if Sprites.uses_revised_art("lamp") else emitter.at - Vector2(5, 8)
		canvas.draw_texture_rect_region(lamp.texture, Rect2(origin + crop.position, crop.size), Rect2(lamp.source.position + crop.position, crop.size))

static func draw_window_view(canvas: CanvasItem, object: Dictionary, minute: float) -> void:
	if object.get("curtains_closed",false): return
	var darkness: float = phase_at(minute).darkness
	if darkness <= 0.001: return
	for raw: Array in indoor_panes():
		var pane: Rect2 = Layout.rect(raw)
		pane.position += object.rect.position
		canvas.draw_rect(pane, Color(0.10, 0.17, 0.28, darkness * 0.86))

static func _light_runs(id: String, regions: Array[Rect2]) -> Array[Dictionary]:
	var frame: Dictionary = Sprites.frame_info(id)
	if frame.is_empty(): return []
	var key: String = id + ":" + str(frame.texture.get_rid())
	if _source_runs.has(key): return _source_runs[key]
	var runs: Array[Dictionary] = []
	var bitmap: Image = frame.texture.get_image()
	if bitmap == null: return runs
	if bitmap.is_compressed() and bitmap.decompress() != OK: return runs
	# Cache native source colors once. A normal-alpha draw can then reproduce the
	# previous additive intensity locally, without a luminous pane over an actor.
	for region: Rect2 in regions:
		for y in range(int(region.position.y), int(region.end.y)):
			var x: int = int(region.position.x)
			while x < int(region.end.x):
				var color: Color = bitmap.get_pixel(x + int(frame.source.position.x), y + int(frame.source.position.y))
				var end: int = x + 1
				while end < int(region.end.x) and bitmap.get_pixel(end + int(frame.source.position.x), y + int(frame.source.position.y)) == color: end += 1
				if color.a > 0.0: runs.append({"rect": Rect2(x, y, end - x, 1), "color": color})
				x = end
	_source_runs[key] = runs
	return runs

static func object_light_regions(id: String, room: String = "street") -> Array[Rect2]:
	_ensure_profile()
	var key: String = id + ":" + room + (":revised" if Sprites.uses_revised_art(id) else ":legacy")
	if _light_regions.has(key): return _light_regions[key]
	var result: Array[Rect2] = []
	if id == "lamp":
		result.append(lamp_core())
	elif Layout.is_outdoor(room) and WINDOW_PANES.has(id):
		for window: Array in window_panes(id):
			for raw: Array in window: result.append(Layout.rect(raw))
	_light_regions[key] = result
	return result

static func _paint_local_light(canvas: CanvasItem, object: Dictionary, room: String, minute: float, tint: Color, intensity: float) -> void:
	var power: float = phase_at(minute).lamp_power
	if power <= 0.001: return
	var regions: Array[Rect2] = object_light_regions(str(object.id), room)
	if regions.is_empty(): return
	var ambient: Color = ambient_for(minute, room)
	var emission := Color(tint.r / ambient.r, tint.g / ambient.g, tint.b / ambient.b)
	var visible_source: Rect2 = _visible_source(object) if object.has("source_rect") else Rect2()
	for run: Dictionary in _light_runs(str(object.id), regions):
		var source: Color = run.color * object.get("tint", Color.WHITE)
		# These measured glass pixels are opaque. Replace them with their final
		# lit color: alpha-blending an overbright intermediate would clamp before
		# blending on an SDR viewport and dim the red channel of bright panes.
		var amount: float = power * intensity
		var lit := Color(source.r + emission.r * amount, source.g + emission.g * amount, source.b + emission.b * amount, source.a)
		var rect: Rect2 = run.rect
		if object.has("source_rect"):
			rect = rect.intersection(visible_source)
			if not rect.has_area(): continue
			rect.position -= object.source_rect.position
		rect.position += object.rect.position
		canvas.draw_rect(rect, lit)

static func draw_object_lights(canvas: CanvasItem, object: Dictionary, room: String, minute: float) -> void:
	## Call immediately after the object, within the same depth-sorted actor layer.
	if not Layout.is_outdoor(room): return
	var id: String = str(object.get("id", ""))
	if id == "lamp":
		_paint_local_light(canvas, object, room, minute, Color(1.0, 0.66, 0.24), 0.72)
	elif WINDOW_PANES.has(id):
		_paint_local_light(canvas, object, room, minute, Color(1.0, 0.59, 0.20), 0.33)

static func draw_fixture_lights(canvas: CanvasItem, room: String, minute: float) -> void:
	## Wall sconces are behind every walkable interior actor, like their fixtures.
	if Layout.is_outdoor(room): return
	for emitter: Dictionary in emitters(room):
		if emitter.kind != "sconce": continue
		var origin: Vector2 = emitter.at - lamp_core().get_center() if Sprites.uses_revised_art("lamp") else emitter.at - Vector2(5, 8)
		var object := {"id": "lamp", "rect": Rect2(origin, Vector2(10, 39))}
		_paint_local_light(canvas, object, room, minute, Color(1.0, 0.69, 0.28), 0.68)

static func _pool(canvas: CanvasItem, at: Vector2, radius: Vector2, power: float, tint := Color(1.0, 0.62, 0.28)) -> void:
	if power <= 0.001: return
	# Eight faint, hard-pixel rings keep light soft without a blur pass or texture.
	var key := Rect2(at, radius)
	if not _pools.has(key):
		var rings: Array[PackedVector2Array] = []
		for ring in range(8, 0, -1):
			var scale: float = ring / 8.0
			var points := PackedVector2Array()
			for point in range(24):
				var angle: float = point * TAU / 24.0
				points.append((at + Vector2(cos(angle), sin(angle)) * radius * scale).round())
			rings.append(points)
		_pools[key] = rings
	for points: PackedVector2Array in _pools[key]:
		canvas.draw_colored_polygon(points, Color(tint, 0.018 * power))

static func draw(canvas: CanvasItem, room: String, minute: float, animation_seconds: float = 0.0, state: Dictionary = {}) -> void:
	var phase: Dictionary = phase_at(minute)
	var power: float = phase.lamp_power
	for emitter: Dictionary in emitters(room,state):
		var at: Vector2 = emitter.at
		if emitter.kind == "inside_window":
			# Quiet daylight cast across the floor; no sunshine after dark.
			if phase.darkness < 0.8:
				canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 10), at + Vector2(6, 10), at + Vector2(25, 58), at + Vector2(-7, 58)]), Color(1, 0.84, 0.50, (1.0 - phase.darkness) * 0.08))
			continue
		if power <= 0.001: continue
		var flicker: float = 0.97 + 0.03 * sin(animation_seconds * 1.6 + at.x)
		_pool(canvas, at, Vector2(emitter.radius, emitter.radius * 0.82), power * flicker)
		if emitter.kind == "lamp":
			_pool(canvas, emitter.ground, Vector2(35, 13), power * 0.8)
