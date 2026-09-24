extends SceneTree
## A small visual state review of the compact statistics panel; isolated world only.
## -- --ui-test runs metrics headless; --capture also exports six full-view PNGs.
const Layout = preload("res://scripts/world_layout.gd")
const CASES := [
	{"name":"manual","mode":"manual","energy":100.0,"coins":20,"minute":480,"size":Vector2i(768,432)},
	{"name":"observing","mode":"observing","energy":35.0,"coins":9999,"minute":600,"size":Vector2i(768,432)},
	{"name":"paused-extremes","mode":"paused","energy":100.0,"coins":1000000,"minute":1438559,"size":Vector2i(768,432)},
	{"name":"sleeping","mode":"sleeping","energy":25.0,"coins":0,"minute":1320,"size":Vector2i(768,432)},
	{"name":"exhausted","mode":"exhausted","energy":0.0,"coins":999999,"minute":720,"size":Vector2i(768,432)},
	{"name":"paused-extremes","mode":"paused","energy":100.0,"coins":1000000,"minute":1438559,"size":Vector2i(960,540)},
]

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_resident: String, _speaker: String, _utterance: String) -> void: provider_calls += 1

var checks := 0
var failures: Array[String] = []
var captures := 0
var save_path := "user://unused_stats_ui_%d.json" % OS.get_process_id()
var directory := ""
var capture_enabled := false

func _initialize() -> void: call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in range(5): await process_frame

func fixture(viewport: SubViewport, scenario: Dictionary) -> MainProbe:
	var scene := MainProbe.new()
	scene.managed_by_shell = true
	scene.start_new_game = true
	scene.colony.save_path = save_path
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false)
	scene.use_jev = false
	scene.save_allowed = false
	scene.service_token = ""
	scene.service_url = ""
	scene.controls_active = true
	scene.paused = false
	for resident: Dictionary in scene.colony.residents:
		resident.room = resident.id
		resident.pos = Layout.data().home_rest.duplicate()
		resident.target = resident.pos.duplicate()
		resident.travel_intent = ""
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = "street"
	player.pos = [264.0,180.0]
	player.target = player.pos.duplicate()
	player.energy = scenario.energy
	scene.colony.minute = scenario.minute
	scene.colony._progression.state.coins = scenario.coins
	match str(scenario.mode):
		"observing": scene.toggle_autonomy()
		"paused": scene.paused = true
		"sleeping":
			var bed: Vector2 = Layout.stand_at("bed","player")
			player.room = "player"
			player.pos = [bed.x,bed.y]
			player.target = player.pos.duplicate()
			scene.update_room()
			expect(scene.sleep_ui.start(480),"sleep capture begins actual stationary rest in the player's bed")
		"exhausted": expect(scene.sync_exhaustion(),"zero-energy capture begins actual forced rest")
	scene.update_room()
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	scene.interaction_hover.clear()
	scene.refresh_status()
	return scene

func snapshot(scene: MainProbe) -> String:
	return JSON.stringify({"residents":scene.colony.residents,"minute":scene.colony.minute,"progression":scene.colony.progression_state(),"events":scene.colony.events})

func inspect(scene: MainProbe, viewport: SubViewport, scenario: Dictionary) -> void:
	var prefix := "%dx%d %s: " % [viewport.size.x,viewport.size.y,scenario.name]
	var hud = scene.hud
	var panel: Rect2 = hud.stats_panel.get_global_rect()
	expect(panel == Rect2(12,12,232,32),prefix+"statistics keep the compact single-row footprint")
	var fits := true
	var fit_errors: Array[String] = []
	var groups: Array[Control] = [hud.mode_group,scene.clock_label,hud.energy_group,hud.coin_group]
	for group: Control in groups:
		if not group.is_visible_in_tree() or not panel.encloses(group.get_global_rect()): fits = false
		for other: Control in groups:
			if other != group and group.get_global_rect().intersects(other.get_global_rect()): fits = false
	for label: Label in [scene.clock_label,hud.energy_value,hud.coin_value]:
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		var text_width: float = font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		if font_size != 14 or text_width > label.size.x+0.1 or font.get_height(font_size) > label.size.y+0.1:
			fits = false
			fit_errors.append("'%s' needs %sx%s; available %s" % [label.text,text_width,font.get_height(font_size),label.size])
	expect(fits,prefix+"visible values fit their resolved font without overlapping or clipping: "+"; ".join(fit_errors))
	expect(hud.energy_bar.value == scenario.energy and hud.energy_value.text == "%d%%" % roundi(scenario.energy),prefix+"energy reads the actual isolated resident including exact zero and one hundred")
	expect(hud.coin_group.accessibility_name.contains(str(scenario.coins)) and not hud.coin_value.text.is_empty(),prefix+"compact money retains the exact amount in its accessible name")
	if scenario.coins == 1000000:
		expect(hud.coin_value.text == "1M" and scene.clock_label.text.contains("999") and scene.clock_label.text.contains("23:59"),prefix+"maximum valid money and day 999 remain readable")
	var mode: String = hud.mode_group.accessibility_name
	expect(not mode.is_empty() and not hud.mode_group.tooltip_text.is_empty() and hud.mode_group.focus_mode == Control.FOCUS_ALL,prefix+"the status icon retains a named keyboard and hover target")
	match str(scenario.mode):
		"manual": expect(mode.contains("manual") and not hud.mode_sleep_label.visible,prefix+"manual state is represented and named")
		"observing": expect(mode.contains("Observ") and scene.colony.player_autonomy and not hud.mode_sleep_label.visible,prefix+"observation follows the actual autonomy state")
		"paused": expect(mode.contains("pausa") and scene.paused and not hud.mode_sleep_label.visible,prefix+"paused state remains explicit")
		_: expect(scene.colony.is_sleeping("player") and hud.mode_sleep_label.is_visible_in_tree(),prefix+"sleep displays Zz for actual normal or forced rest")
	expect(not panel.intersects(hud.controls_panel.get_global_rect()) and (not scene.home_ui.location_panel.visible or not panel.intersects(scene.home_ui.location_panel.get_global_rect())),prefix+"statistics remain separate from controls and the house location")
	var before := snapshot(scene)
	for _iteration in range(5): hud.refresh_stats()
	expect(snapshot(scene) == before and scene.provider_calls == 0 and scene.dialogue_job.is_empty() and scene.visit_job.is_empty() and not FileAccess.file_exists(save_path),prefix+"rendering statistics changes no progress and creates no request or save")

func capture(viewport: SubViewport, scene: MainProbe, scenario: Dictionary) -> void:
	if not capture_enabled: return
	scene.actors.queue_redraw()
	await settle()
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var filename := "%dx%d-%s.png" % [viewport.size.x,viewport.size.y,scenario.name]
	if picture == null or picture.is_empty() or picture.save_png(directory.path_join(filename)) != OK:
		failures.append("Could not save " + filename)
		push_error("Could not save " + filename)
	else:
		captures += 1
		print("CAPTURE: " + directory.path_join(filename))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ui-test" not in args:
		push_error("Requires -- --ui-test; real progress must remain untouched.")
		quit(1)
		return
	capture_enabled = "--capture" in args
	if capture_enabled and DisplayServer.get_name() == "headless":
		push_error("Captures require a graphical renderer.")
		quit(1)
		return
	directory = ProjectSettings.globalize_path("res://../artifacts/stats-ui")
	if capture_enabled: DirAccess.make_dir_recursive_absolute(directory)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for scenario: Dictionary in CASES:
		viewport.size = scenario.size
		var scene := fixture(viewport,scenario)
		await settle()
		inspect(scene,viewport,scenario)
		await capture(viewport,scene,scenario)
		scene.free()
		await process_frame
	viewport.free()
	await process_frame
	print("STATS UI: %d/%d checks passed; %d captures" % [checks-failures.size(),checks,captures])
	quit(0 if failures.is_empty() else 1)
