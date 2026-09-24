extends SceneTree
## Saved game time drives world light, never HUD tint, network work or real-world time.
const Lighting = preload("res://scripts/world_lighting.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Main = preload("res://scenes/main.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)

func run() -> void:
	root.size = Vector2i(768,432)
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test; never load or save normal progress.")
		quit(1)
		return
	var noon: Dictionary = Lighting.phase_at(720)
	var midnight: Dictionary = Lighting.phase_at(0)
	expect(noon.darkness == 0.0 and noon.ambient == Color.WHITE and not noon.lamps_on, "daylight leaves the world clear and artificial lights off")
	expect(midnight.darkness == 1.0 and midnight.ambient.v < noon.ambient.v and midnight.lamps_on, "midnight darkens the world and enables local lighting")
	expect(Lighting.phase_at(480).darkness == 0.0 and Lighting.phase_at(1049).darkness == 0.0, "daylight spans eight o'clock through the period before 17:30")
	var dawn := true
	var dusk := true
	var previous := 1.0
	for minute in range(390,481,5):
		var phase: Dictionary = Lighting.phase_at(minute)
		dawn = dawn and phase.darkness <= previous and phase.darkness >= 0.0
		previous = phase.darkness
	previous = 0.0
	for minute in range(1050,1201,5):
		var phase: Dictionary = Lighting.phase_at(minute)
		dusk = dusk and phase.darkness >= previous and phase.darkness <= 1.0
		previous = phase.darkness
	expect(dawn and dusk and Lighting.phase_at(390).darkness == 1.0 and Lighting.phase_at(1200).darkness == 1.0, "dawn 06:30–08:00 and dusk 17:30–20:00 transition monotonically")
	expect(absf(Lighting.phase_at(1199.999).darkness-Lighting.phase_at(1200.001).darkness) < 0.001 and Lighting.phase_at(0) == Lighting.phase_at(1440), "night and the day boundary have no abrupt lighting discontinuity")
	expect(Lighting.ambient_for(0,"player").v > Lighting.ambient_for(0,"street").v and Lighting.ambient_for(720,"player") == Color.WHITE, "indoor lighting remains more readable at night and clear in daytime")
	var lamp_positions: Array[Vector2] = []
	var glass_center: Vector2 = Lighting.lamp_core().get_center() if Lighting.Sprites.uses_revised_art("lamp") else Vector2(5,6)
	for prop: Dictionary in Layout.props("street"):
		if prop.id == "lamp": lamp_positions.append(prop.rect.position+glass_center)
	var actual_lamps: Array[Vector2] = []
	var windows := 0
	for emitter: Dictionary in Lighting.emitters("street"):
		if emitter.kind == "lamp": actual_lamps.append(emitter.at)
		elif emitter.kind == "window": windows += 1
	expect(actual_lamps == lamp_positions and Lighting.lamp_core().has_point(glass_center) and not actual_lamps.is_empty() and windows > 0, "street emitters remain inside the active native lantern glass and follow facade windows")
	var indoor_emitters := true
	for room in Layout.data().doors:
		var sconces := 0
		var daylight_windows := 0
		for emitter: Dictionary in Lighting.emitters(room):
			if emitter.kind == "sconce": sconces += 1
			elif emitter.kind == "inside_window": daylight_windows += 1
		indoor_emitters = indoor_emitters and sconces == 2 and daylight_windows > 0
	expect(indoor_emitters, "each actual home has indoor window light and two wall lamps")
	var scene = Main.instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.colony.minute = 1100
	scene.elapsed = 2.0
	scene.paused = false
	scene.update_environment(0.2)
	expect(is_equal_approx(scene.visual_minute(),1102.5), "visual time interpolates the current saved clock tick without advancing simulation")
	var ambient: Color = Lighting.ambient_for(scene.visual_minute(),scene.current_room)
	expect(scene.scenery.modulate == ambient and scene.actors.modulate == ambient and scene.world_surround.modulate == ambient and scene.atmosphere.modulate == ambient, "world geometry, residents and atmosphere share the same day-night tint")
	expect(scene.modulate == Color.WHITE and scene.inspector.modulate == Color.WHITE and scene.hud.stats_panel.modulate == Color.WHITE and scene.hud.controls_panel.modulate == Color.WHITE and scene.hud.dock_panel.modulate == Color.WHITE, "night lighting never tints the HUD or reading panels")
	expect(scene.world_lights.get_index() > scene.actors.get_index() and scene.world_labels.get_index() > scene.world_lights.get_index() and scene.world_lights.modulate == Color.WHITE, "local lighting renders after the residents and before legible world text")
	scene.paused = true
	var seconds: float = scene.environment_seconds
	var minute: int = scene.colony.minute
	var fraction: float = scene.elapsed
	scene._process(10.0)
	expect(scene.environment_seconds == seconds and scene.colony.minute == minute and scene.elapsed == fraction and scene.actors.modulate == ambient, "pausing freezes environment animation and the interpolated day-night cycle")
	expect(scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not scene.decision_pending, "the light cycle leaves no provider work pending")
	scene.free()
	await process_frame
	print("LIGHTING: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
