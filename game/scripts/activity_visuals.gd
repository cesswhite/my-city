extends RefCounted
## Presentation only: daily_state and is_sleeping remain authoritative in Colony.
const Sprites = preload("res://scripts/sprite_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Icons = preload("res://scripts/hud_icons.gd")
const WORLD := Rect2(12, 48, 468, 244)
const PAPER := Color("f4edda")
const FONT_SIZE := 16
const HEAD_SOURCE := Rect2(6, 7, 12, 12)
const REST_FONT = preload("res://assets/fonts/PixelOperator.ttf")
static var _badge_skin: StyleBoxTexture
static var _emoji_font: SystemFont
const THOUGHT_NAME := Color("c3c8b6")
const THOUGHT_BACKGROUND := Color(0.10, 0.16, 0.12, 0.78)

static func bed_rect(room: String) -> Rect2:
	if Layout.is_outdoor(room) or not Layout.door_positions().has(room): return Rect2()
	for item: Dictionary in Layout.props(room):
		if item.get("key", "") == "bed": return item.rect
	return Rect2()

static func is_bed_sleep(resident: Dictionary, state: Dictionary, room: String) -> bool:
	return resident.get("sleep", {}).get("kind", "") != "exhaustion" and state.get("kind", "") == "sleeping" and not Layout.is_outdoor(room) and resident.get("room", "street") == room and resident.get("home_id", "") == room and bed_rect(room).has_area()

static func exhaustion_layout(resident: Dictionary, state: Dictionary, room: String) -> Dictionary:
	if state.get("kind", "") != "sleeping" or resident.get("sleep", {}).get("kind", "") != "exhaustion" or resident.get("room", "street") != room: return {}
	var position = resident.get("pos", [])
	if not position is Array or position.size() != 2: return {}
	var at := Vector2(float(position[0]), float(position[1]))
	if not at.is_finite(): return {}
	# The whole native sprite turns onto its side; its visible body stays centered
	# over the actual floor position. No movement or bed coordinate is inferred.
	return {"origin": at.round() + Vector2(11, -5), "rotation": -PI / 2.0, "anchor": at, "rect": Rect2(at.round() + Vector2(-19, -17), Vector2(32, 24)), "zzz": at.round() + Vector2(-12, -15)}

static func _draw_exhausted(canvas: CanvasItem, resident: Dictionary, geometry: Dictionary) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_set_transform(geometry.origin, geometry.rotation)
	for layer: Dictionary in Sprites.character_layers(resident.get("appearance", {}), false, 0, Vector2.DOWN):
		var origin: Vector2 = Vector2(-12, -30) + layer.get("offset", Vector2.ZERO)
		if layer.id == "char_eyes":
			# Two native eye pixels form each closed eyelid; no generated bitmap or
			# stretched face. This keeps the chosen eye tint and every other layer.
			for eye: Vector2 in [Vector2(10, 14), Vector2(13, 14)]:
				for offset in 2:
					_paint_region(canvas, layer, Rect2(eye, Vector2.ONE), Rect2(origin + eye + Vector2(offset, 0), Vector2.ONE))
		else:
			_paint_region(canvas, layer, Rect2(0, 0, 24, 32), Rect2(origin, Vector2(24, 32)))
	canvas.draw_set_transform(Vector2.ZERO)
	# The font's native 16 px glyphs are drawn at half world scale: each logical
	# pixel stays sharp while the gameplay camera supplies its normal enlargement.
	canvas.draw_set_transform(geometry.zzz, 0, Vector2(0.5, 0.5))
	canvas.draw_string(REST_FONT, Vector2(1, 1), "Zzz", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("34433b"))
	canvas.draw_string(REST_FONT, Vector2.ZERO, "Zzz", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PAPER)
	canvas.draw_set_transform(Vector2.ZERO)

static func sleep_layout(room: String) -> Dictionary:
	var bed: Rect2 = bed_rect(room)
	if not bed.has_area(): return {}
	if Sprites.uses_revised_art("bed"):
		# Replacement pillow center is (15,13), two pixels right/below the old
		# one. Head layers stay native; the blue quilt begins at row 19.
		return {"bed": bed, "head": Rect2(bed.position + Vector2(9, 7), HEAD_SOURCE.size), "head_source": HEAD_SOURCE, "quilt_source": Rect2(1, 19, 24, 11), "quilt": Rect2(bed.position + Vector2(1, 19), Vector2(24, 11)), "anchor": bed.position + Vector2(15, 18), "sort_y": bed.end.y + 0.25}
	# Measured on bed.png (26×38): pillow y7..12, white fold y15..17,
	# quilt y18..29. The existing head sits on the pillow under that fold.
	return {"bed": bed, "head": Rect2(bed.position + Vector2(7, 5), HEAD_SOURCE.size), "head_source": HEAD_SOURCE, "quilt_source": Rect2(3, 17, 23, 13), "quilt": Rect2(bed.position + Vector2(3, 17), Vector2(23, 13)), "anchor": bed.position + Vector2(13, 16), "sort_y": bed.end.y + 0.25}

static func sort_y(resident: Dictionary, state: Dictionary, room: String, feet: Vector2) -> float:
	return float(sleep_layout(room).sort_y) if is_bed_sleep(resident, state, room) else feet.y

static func visual_anchor(resident: Dictionary, state: Dictionary, room: String, feet: Vector2) -> Vector2:
	return sleep_layout(room).anchor if is_bed_sleep(resident, state, room) else feet

static func _paint_region(canvas: CanvasItem, frame: Dictionary, source: Rect2, destination: Rect2) -> void:
	if frame.is_empty(): return
	var texture: Texture2D = frame.texture
	var region: Rect2 = source
	region.position += frame.source.position
	if not frame.source.encloses(region): return
	canvas.draw_texture_rect_region(texture, destination, region, frame.get("tint", Color.WHITE))

static func draw_sleeping(canvas: CanvasItem, resident: Dictionary, state: Dictionary, room: String) -> bool:
	var exhausted: Dictionary = exhaustion_layout(resident, state, room)
	if not exhausted.is_empty():
		_draw_exhausted(canvas, resident, exhausted)
		return true
	if not is_bed_sleep(resident, state, room): return false
	var geometry: Dictionary = sleep_layout(room)
	var appearance: Dictionary = resident.get("appearance", {}).duplicate()
	# No hat in bed. The saved appearance is left untouched, and eyes are omitted
	# rather than inventing a new face or a closed-eye sprite.
	appearance.hat = 0
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for layer: Dictionary in Sprites.character_layers(appearance, false, 0, Vector2.DOWN):
		if layer.id in ["char_shirt", "char_pants", "char_eyes"]: continue
		if layer.key == "hat": continue
		var destination: Rect2 = geometry.head
		destination.position += layer.get("offset", Vector2.ZERO)
		_paint_region(canvas, layer, HEAD_SOURCE, destination)
	# Reuse the real quilt, covering any hair/beard at the mattress edge.
	_paint_region(canvas, Sprites.frame_info("bed"), geometry.quilt_source, geometry.quilt)
	return true

static func active_pose(resident: Dictionary, state: Dictionary, feet: Vector2, phase: int, direction: Vector2 = Vector2.DOWN) -> Dictionary:
	if not feet.is_finite() or state.get("kind", "") not in ["working", "eating"]: return {}
	var target = resident.get("target", [])
	if target is Array and target.size() == 2 and feet.distance_to(Vector2(float(target[0]), float(target[1]))) > 2.0: return {}
	var facing: Vector2 = direction if direction.is_finite() and not direction.is_zero_approx() else Vector2.DOWN
	var step: int = posmod(phase, 4)
	# The walk atlas supplies small existing arm gestures. Legs always stay idle.
	# A slower 450 ms phase supplied by the caller avoids walking in place.
	var pose: Dictionary = {"direction": facing, "frame": [0, 1, 0, 3][step], "origin": feet.round() - Vector2(12, 30), "cup": Rect2()}
	if state.get("action", "") == "drink":
		# A front-facing sip keeps the actual cup visible, including its steam.
		pose.direction = Vector2.DOWN
		pose.cup = Rect2(feet.round() + Vector2(1, -14 - (3 if step in [1, 2] else 0)), Vector2(8, 10))
	return pose

static func active_layers(appearance: Dictionary, pose: Dictionary) -> Array[Dictionary]:
	# The renderer and hover share exactly these cropped layers: idle legs with
	# a moving torso, plus a cup when drinking. A walking outline would not fit.
	var result: Array[Dictionary] = []
	if pose.is_empty(): return result
	var idle: Array[Dictionary] = Sprites.character_layers(appearance, false, 0, pose.direction)
	var gesture: Array[Dictionary] = Sprites.character_layers(appearance, true, int(pose.frame), pose.direction)
	for index in idle.size():
		var layer: Dictionary = idle[index]
		if layer.id == "char_body":
			result.append(_active_crop(layer, Rect2(0, 0, 24, 19)))
			result.append(_active_crop(gesture[index], Rect2(0, 19, 24, 7)))
		elif layer.id == "char_shirt":
			result.append(_active_crop(gesture[index], Rect2(0, 0, 24, 32)))
		else:
			result.append(_active_crop(layer, Rect2(0, 0, 24, 32)))
	if pose.cup.has_area():
		var cup: Dictionary = Sprites.frame_info("tea_ready")
		if not cup.is_empty():
			cup.offset = pose.cup.position - pose.origin
			cup.flip_h = false
			result.append(cup)
	return result

static func _active_crop(layer: Dictionary, crop: Rect2) -> Dictionary:
	var result: Dictionary = layer.duplicate()
	result.source = Rect2(layer.source.position + crop.position, crop.size)
	result.offset = layer.get("offset", Vector2.ZERO) + crop.position
	# _paint_region displays the native crop, without mirroring it.
	result.flip_h = false
	return result

static func draw_active(canvas: CanvasItem, resident: Dictionary, state: Dictionary, feet: Vector2, phase: int, direction: Vector2 = Vector2.DOWN) -> bool:
	var pose: Dictionary = active_pose(resident, state, feet, phase, direction)
	if pose.is_empty(): return false
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for layer: Dictionary in active_layers(resident.get("appearance", {}), pose):
		_paint_region(canvas, layer, Rect2(Vector2.ZERO, layer.source.size), Rect2(pose.origin + layer.get("offset", Vector2.ZERO), layer.source.size))
	return true

static func short_activity(state: Dictionary) -> String:
	var action: String = str(state.get("action", ""))
	match str(state.get("kind", "")):
		"sleeping": return "Zzz"
		"speaking": return "Charlando"
		"working": return {"farm":"Cultivando", "gather":"Recogiendo", "build":"Construyendo", "explore":"Explorando", "craft":"Preparando materiales", "cook":"Cocinando", "water": "Regando", "check_soil": "Revisando tierra", "repair": "Reparando", "sort_tools": "Ordenando útiles", "serve": "Atendiendo", "tidy_cups": "Ordenando tazas", "sketch": "Dibujando", "plan_meeting": "Organizando", "huerto": "Cultivando", "taller": "En el taller", "cafe": "En el café"}.get(action, "Trabajando")
		"eating": return "Bebiendo" if action == "drink" else "Comiendo"
		"resting": return "Descansando"
		"leisure": return "Tiempo libre"
		"walking": return "En camino"
	return ""

static func _icon(state: Dictionary) -> String:
	match str(state.get("kind", "")):
		"sleeping", "resting": return "home"
		"speaking": return "people"
		"working":
			var action: String = str(state.get("action", ""))
			return "seed" if action in ["huerto", "water", "check_soil"] else ("bicycle" if action in ["taller", "repair", "sort_tools"] else ("people" if action == "plan_meeting" else "journal"))
		"eating": return "energy"
		"leisure": return "eye"
		"walking": return "person"
	return "person"

static func _skin() -> StyleBoxTexture:
	if _badge_skin == null:
		var info: Dictionary = Sprites.frame_info("ui_tooltip")
		if info.is_empty(): return null
		_badge_skin = StyleBoxTexture.new()
		_badge_skin.texture = info.texture
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: _badge_skin.set_texture_margin(side, 2)
	return _badge_skin

static func _fit_text(font: Font, content: String, available: float) -> String:
	if font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= available: return content
	var clipped: String = content
	while not clipped.is_empty() and font.get_string_size(clipped + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > available:
		clipped = clipped.left(clipped.length() - 1)
	return clipped + "..."

static func badge_spec(font: Font, resident: Dictionary, state: Dictionary, at: Vector2, selected: bool, nearby: bool, occupied: Array = [], bounds: Rect2 = WORLD) -> Dictionary:
	# Anchor, occupied areas, and bounds share the caller's coordinate space.
	# The screen overlay keeps this font/icon geometry independent of world zoom.
	if font == null or not at.is_finite() or not (selected or nearby or state.get("kind", "") == "sleeping"): return {}
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 48 or bounds.size.y < 26: return {}
	var activity: String = short_activity(state)
	if activity.is_empty(): return {}
	var content: String = (str(resident.get("name", "")) + " · " + activity) if selected else activity
	content = _fit_text(font, content, minf(142, bounds.size.x - 32))
	var dimensions := Vector2(ceilf(font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x) + 28, 22)
	var preferred := Vector2(at.x - dimensions.x / 2.0, at.y - 48)
	if state.get("kind", "") == "sleeping": preferred.y = at.y - 38
	for offset: Vector2 in [Vector2.ZERO, Vector2(-24, 0), Vector2(24, 0), Vector2(0, -26), Vector2(-48, -26), Vector2(48, -26)]:
		var position: Vector2 = preferred + offset
		position.x = clampf(position.x, bounds.position.x + 2, bounds.end.x - dimensions.x - 2)
		position.y = clampf(position.y, bounds.position.y + 2, bounds.end.y - dimensions.y - 2)
		var rectangle := Rect2(position.round(), dimensions)
		var clear := true
		for reserved in occupied:
			if reserved is Rect2 and rectangle.grow(2).intersects(reserved):
				clear = false
				break
		if clear: return {"rect": rectangle, "text": content, "icon": _icon(state)}
	return {}

static func draw_badge(canvas: CanvasItem, font: Font, resident: Dictionary, state: Dictionary, at: Vector2, selected: bool, nearby: bool, occupied: Array = [], bounds: Rect2 = WORLD) -> Rect2:
	var spec: Dictionary = badge_spec(font, resident, state, at, selected, nearby, occupied, bounds)
	var skin: StyleBoxTexture = _skin()
	if spec.is_empty() or skin == null: return Rect2()
	var rectangle: Rect2 = spec.rect
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_style_box(skin, rectangle)
	var icon: Texture2D = Icons.texture(spec.icon)
	if icon != null: canvas.draw_texture(icon, rectangle.position + Vector2(4, 3))
	var baseline: Vector2 = rectangle.position + Vector2(23, floorf((rectangle.size.y - font.get_height(FONT_SIZE)) / 2.0) + font.get_ascent(FONT_SIZE))
	canvas.draw_string(font, baseline, spec.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, PAPER)
	return rectangle

static func emoji_font() -> SystemFont:
	if _emoji_font == null:
		_emoji_font = SystemFont.new()
		_emoji_font.font_names = PackedStringArray(["Apple Color Emoji", "Noto Color Emoji", "Segoe UI Emoji"])
		_emoji_font.allow_system_fallback = false
	return _emoji_font

static func _thought_line(value: String) -> String:
	var cleaned := ""
	for character: String in value.left(256):
		var code: int = character.unicode_at(0)
		cleaned += " " if code < 32 or code in [0x85, 0xa0, 0x2028, 0x2029] else character
	return " ".join(cleaned.split(" ", false)).strip_edges()

static func _thought_emoji(value: String) -> String:
	var candidate: String = value.strip_edges()
	if candidate.is_empty() or candidate.length() > 8: return ""
	var font: SystemFont = emoji_font()
	var visible := 0
	for index in candidate.length():
		var code: int = candidate.unicode_at(index)
		if code in [0xfe0f, 0xfe0e, 0x200d]:
			if index == 0 or (code == 0x200d and index == candidate.length() - 1): return ""
			continue
		if not ((code >= 0x1f000 and code <= 0x1faff) or (code >= 0x2600 and code <= 0x27bf)): return ""
		if not font.has_char(code): return ""
		visible += 1
	return candidate if visible > 0 else ""

static func _thought_fit(font: Font, text: String, width: float) -> String:
	if width < font.get_string_size("...", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x: return ""
	return _fit_text(font, text, width)

static func thought_spec(font: Font, resident: Dictionary, thought: Dictionary, at: Vector2, occupied: Array = [], bounds: Rect2 = WORLD) -> Dictionary:
	if font == null or not at.is_finite() or thought.is_empty(): return {}
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 64 or bounds.size.y < 26: return {}
	var alpha: float = float(thought.get("alpha", 1.0))
	if not is_finite(alpha) or alpha <= 0.0: return {}
	alpha = minf(alpha, 1.0)
	var text: String = _thought_line(str(thought.get("text", "")))
	if text.is_empty(): return {}
	var name: String = _thought_line(str(resident.get("name", "Vecino")))
	if name.is_empty(): name = "Vecino"
	var emoji: String = _thought_emoji(str(thought.get("emoji", "")))
	var emoji_width: float = 0.0 if emoji.is_empty() else ceilf(emoji_font().get_string_size(emoji, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var available: float = minf(268.0, bounds.size.x - 4.0) - 12.0
	# Optional decoration yields its space before the actual thought does.
	if emoji_width > minf(40.0, available * 0.25):
		emoji = ""
		emoji_width = 0.0
	var words_width: float = available - (emoji_width + 4 if emoji_width > 0 else 0)
	name = _thought_fit(font, name, minf(80.0, words_width * 0.35))
	if name.is_empty(): return {}
	var prefix: String = name + ": "
	var prefix_width: float = ceilf(font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	text = _thought_fit(font, text, words_width - prefix_width)
	if text.is_empty(): return {}
	var text_width: float = ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var dimensions := Vector2(prefix_width + text_width + (emoji_width + 4 if emoji_width > 0 else 0) + 12, 22)
	var preferred := Vector2(at.x - dimensions.x / 2.0, at.y - 48)
	for offset: Vector2 in [Vector2.ZERO, Vector2(-24, 0), Vector2(24, 0), Vector2(0, -26), Vector2(-48, -26), Vector2(48, -26)]:
		var position: Vector2 = preferred + offset
		position.x = clampf(position.x, bounds.position.x + 2, bounds.end.x - dimensions.x - 2)
		position.y = clampf(position.y, bounds.position.y + 2, bounds.end.y - dimensions.y - 2)
		var rectangle := Rect2(position.round(), dimensions)
		var clear := true
		for reserved in occupied:
			if reserved is Rect2 and rectangle.grow(2).intersects(reserved):
				clear = false
				break
		if clear:
			return {"rect": rectangle, "prefix": prefix, "text": text, "emoji": emoji, "alpha": alpha, "prefix_width": prefix_width, "text_width": text_width, "emoji_width": emoji_width}
	return {}

static func draw_thought(canvas: CanvasItem, font: Font, resident: Dictionary, thought: Dictionary, at: Vector2, occupied: Array = [], bounds: Rect2 = WORLD) -> Rect2:
	var spec: Dictionary = thought_spec(font, resident, thought, at, occupied, bounds)
	if spec.is_empty(): return Rect2()
	var rectangle: Rect2 = spec.rect
	var alpha: float = spec.alpha
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw_rect(rectangle, Color(THOUGHT_BACKGROUND, THOUGHT_BACKGROUND.a * alpha))
	var baseline: Vector2 = rectangle.position + Vector2(6, floorf((rectangle.size.y - font.get_height(FONT_SIZE)) / 2.0) + font.get_ascent(FONT_SIZE))
	canvas.draw_string(font, baseline, spec.prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(THOUGHT_NAME, alpha))
	baseline.x += spec.prefix_width
	canvas.draw_string(font, baseline, spec.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(PAPER, alpha))
	if not str(spec.emoji).is_empty():
		var emoji: SystemFont = emoji_font()
		var emoji_baseline := Vector2(baseline.x + spec.text_width + 4, rectangle.position.y + floorf((rectangle.size.y - emoji.get_height(FONT_SIZE)) / 2.0) + emoji.get_ascent(FONT_SIZE))
		canvas.draw_string(emoji, emoji_baseline, spec.emoji, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, alpha))
	return rectangle
