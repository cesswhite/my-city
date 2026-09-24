extends SceneTree
## Badge geometry stays native in screen space, without saves or providers.
const Visuals = preload("res://scripts/activity_visuals.gd")
const UI_FONT = preload("res://assets/fonts/PixelOperator.ttf")
var checks := 0
var failures: Array[String] = []

class ThoughtPreview extends Node2D:
	var painted: Array[Rect2] = []
	func _draw() -> void:
		painted.clear()
		draw_rect(Rect2(0, 0, 640, 260), Color("9fbb77"))
		draw_rect(Rect2(0, 130, 640, 130), Color("d6c495"))
		var area := Rect2(0, 0, 640, 260)
		painted.append(Visuals.draw_thought(self, UI_FONT, {"name": "Mateo"}, {"text": "Qué gusto verte."}, Vector2(180, 92), [], area))
		painted.append(Visuals.draw_thought(self, UI_FONT, {"name": "Lupita"}, {"text": "Me encantan los perros.", "emoji": "🐶❤️"}, Vector2(270, 148), [], area))
		painted.append(Visuals.draw_thought(self, UI_FONT, {"name": "Alma"}, {"text": "Hoy quiero dibujar.", "alpha": 0.45}, Vector2(430, 212), [], area))

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: " + description)
	else:
		failures.append(description)
		push_error(description)

func run() -> void:
	var person := {"name": "Mateo"}
	var speaking := {"kind": "speaking"}
	var anchor := Vector2(236, 210)
	var legacy: Dictionary = Visuals.badge_spec(UI_FONT, person, speaking, anchor, true, false)
	expect(not legacy.is_empty() and Visuals.WORLD.encloses(legacy.rect), "default call still uses the original world bounds")
	expect(legacy.rect.size.y == 22 and legacy.text == "Mateo · Charlando", "activity badge preserves its compact native geometry and copy")
	var screen := Rect2(8, 8, 944, 524)
	var enlarged: Dictionary = Visuals.badge_spec(UI_FONT, person, speaking, anchor * 2, true, false, [], screen)
	expect(enlarged.rect.size == legacy.rect.size, "doubling the screen anchor never enlarges text, icon, or badge")
	expect(enlarged.rect.position.y == anchor.y * 2 - 48, "anchor offset remains a screen-space distance")
	var edge: Dictionary = Visuals.badge_spec(UI_FONT, person, speaking, Vector2(948, 532), true, false, [], screen)
	expect(not edge.is_empty() and screen.encloses(edge.rect), "custom screen bounds constrain badges at the viewport edge")
	expect(edge.rect.position.x > Visuals.WORLD.end.x, "screen-space badges are not clamped back into the old logical map")
	var inspector := Rect2(690, 16, 254, 508)
	var beside: Dictionary = Visuals.badge_spec(UI_FONT, person, speaking, Vector2(645, 250), true, false, [inspector], screen)
	expect(not beside.is_empty() and not beside.rect.grow(2).intersects(inspector), "a nearby badge shifts clear of the reading panel")
	var hidden: Dictionary = Visuals.badge_spec(UI_FONT, person, speaking, Vector2(800, 250), true, false, [inspector], screen)
	expect(hidden.is_empty(), "an occluded actor never paints a label through the inspector")
	var narrow := Rect2(0, 0, 64, 64)
	var abbreviated: Dictionary = Visuals.badge_spec(UI_FONT, {"name": "Un nombre muy largo"}, speaking, Vector2(32, 58), true, false, [], narrow)
	expect(not abbreviated.is_empty() and narrow.encloses(abbreviated.rect) and abbreviated.text.ends_with("..."), "narrow bounds shorten text while containing the complete badge")
	expect(Visuals.badge_spec(UI_FONT, person, speaking, anchor, true, false, [], Rect2(0, 0, 30, 20)).is_empty(), "an area too small for readable content suppresses its badge")
	expect(Visuals.badge_spec(UI_FONT, person, speaking, anchor, true, false, [], Rect2(Vector2.ZERO, Vector2(INF, 100))).is_empty(), "nonfinite bounds cannot leak invalid drawing coordinates")
	expect(Visuals.badge_spec(UI_FONT, person, speaking, Vector2(NAN, 20), true, false, [], screen).is_empty(), "nonfinite anchors are rejected")
	var sleeping: Dictionary = Visuals.badge_spec(UI_FONT, person, {"kind": "sleeping"}, Vector2(300, 250), false, false, [], screen)
	expect(sleeping.text == "Zzz" and sleeping.rect.position.y == 212 and sleeping.rect.size.y == 22, "sleeping badges keep the pillow anchor and native text size")
	expect(Visuals.badge_spec(UI_FONT, person, speaking, anchor, false, false, [], screen).is_empty(), "unselected distant conversations remain visually quiet")
	expect(Visuals.badge_spec(UI_FONT, person, {"kind": "idle"}, anchor, true, true, [], screen).is_empty(), "idle actors do not receive an invented activity")
	var thought := {"text": "Qué gusto verte.", "alpha": 1.0}
	var before: Dictionary = thought.duplicate(true)
	var simple: Dictionary = Visuals.thought_spec(UI_FONT, person, thought, anchor)
	expect(simple.prefix == "Mateo: " and simple.text == thought.text and simple.emoji.is_empty(), "thoughts use a secondary name prefix and the actual thought without a fixed icon")
	expect(simple.rect.size == Vector2(simple.prefix_width + simple.text_width + 12, 22), "plain thoughts reserve only six pixels of horizontal padding")
	var screen_thought: Dictionary = Visuals.thought_spec(UI_FONT, person, thought, anchor * 2, [], screen)
	expect(screen_thought.rect.size == simple.rect.size, "world zoom cannot change thought font, padding, or height")
	expect(thought == before, "presentation leaves the scheduler's thought untouched")
	expect(Visuals.thought_spec(UI_FONT, person, {}, anchor).is_empty() and Visuals.thought_spec(UI_FONT, person, {"text": " \n\t "}, anchor).is_empty(), "empty thoughts never create permanent labels")
	expect(Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "alpha": 0.0}, anchor).is_empty() and Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "alpha": -0.1}, anchor).is_empty(), "fully faded thoughts allocate no visible label")
	var faint: Dictionary = Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "alpha": 0.25}, anchor)
	expect(is_equal_approx(faint.alpha, 0.25), "partial alpha is preserved for the caller's fade")
	expect(Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "alpha": 5.0}, anchor).alpha == 1.0, "excess opacity is safely clamped")
	expect(Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "alpha": NAN}, anchor).is_empty(), "invalid opacity cannot reach drawing")
	var multiline: Dictionary = Visuals.thought_spec(UI_FONT, {"name": "Mateo\nRamírez"}, {"text": "  Qué\n\t gusto   verte. "}, anchor)
	expect(not multiline.prefix.contains("\n") and multiline.text == "Qué gusto verte.", "names and thoughts normalize to exactly one readable line")
	var limited := Rect2(0, 0, 120, 64)
	var long_thought: Dictionary = Visuals.thought_spec(UI_FONT, {"name": "Un nombre muy largo"}, {"text": "Una frase larga que jamás debería cruzar el límite de esta pantalla."}, Vector2(60, 62), [], limited)
	expect(not long_thought.is_empty() and limited.encloses(long_thought.rect) and long_thought.text.ends_with("..."), "long names and thoughts ellipsize within their shared width")
	expect(Visuals.thought_spec(UI_FONT, person, thought, Vector2(800,250), [inspector], screen).is_empty(), "thoughts cannot show through an occupied inspector")
	var offscreen: Dictionary = Visuals.thought_spec(UI_FONT, person, thought, Vector2(970,540), [], screen)
	expect(not offscreen.is_empty() and screen.encloses(offscreen.rect), "thoughts remain contained at screen corners")
	expect(Visuals.thought_spec(UI_FONT, person, thought, anchor, [], Rect2(0,0,40,20)).is_empty(), "too-small surfaces do not draw clipped thoughts")
	expect(Visuals.thought_spec(UI_FONT, person, thought, Vector2(INF,0)).is_empty(), "invalid thought anchors are rejected")
	var emoji_text := "🐶❤️"
	var with_emoji: Dictionary = Visuals.thought_spec(UI_FONT, person, {"text": "Qué bonito.", "emoji": emoji_text}, anchor)
	var emoji_supported: bool = Visuals.emoji_font().has_char(0x1f436) and Visuals.emoji_font().has_char(0x2764)
	expect(with_emoji.emoji == (emoji_text if emoji_supported else ""), "legitimate dog and heart emoji use installed glyphs or disappear safely")
	expect(with_emoji.rect.size.y == 22 and with_emoji.rect.size.x == with_emoji.prefix_width + with_emoji.text_width + with_emoji.emoji_width + (16 if emoji_supported else 12), "optional emoji have measured width without enlarging line height")
	expect(Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "emoji": "missing-glyph"}, anchor).emoji.is_empty(), "ordinary text is not passed through the emoji font")
	expect(Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "emoji": "\ufe0f"}, anchor).emoji.is_empty(), "a standalone variation selector cannot create an empty icon slot")
	expect(Visuals.thought_spec(UI_FONT, person, {"text": "Hola", "emoji": "\U0001faff"}, anchor).emoji.is_empty(), "an unavailable emoji codepoint never renders a missing-glyph square")
	print("System emoji: %s; height at 16 px: %.1f" % ["available" if emoji_supported else "omitted", Visuals.emoji_font().get_height(16)])
	var preview := ThoughtPreview.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 260)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(preview)
	for _frame in range(4): await process_frame
	expect(preview.painted.size() == 3 and preview.painted.all(func(rect: Rect2): return rect.has_area()), "the draw API paints plain, emoji, and fading thought variants")
	if "--capture-thought" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var capture: String = OS.get_environment("MY_CITY_THOUGHT_CAPTURE")
		expect(not capture.is_empty() and viewport.get_texture().get_image().save_png(capture) == OK, "isolated thought preview exported")
	viewport.queue_free()
	await process_frame
	print("Activity labels: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
