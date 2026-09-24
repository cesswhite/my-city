extends SceneTree
## Isolated presentation checks. No saves, live providers, or accelerated rest fixture.
const Visuals = preload("res://scripts/activity_visuals.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Sprites = preload("res://scripts/sprite_art.gd")

class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_a: String, _b: String, _text: String) -> void: provider_calls += 1

class PosePreview extends Node2D:
	var rendered := 0
	func _draw() -> void:
		rendered = 0
		draw_rect(Rect2(0, 0, 240, 74), Color("d6c495"))
		for index in 4:
			var appearance := {"skin": index, "hair": index, "hair_style": index, "hat": index, "beard": index % 3, "eyes": index, "shirt": index, "pants": index}
			var at := Vector2(32 + index * 58, 45)
			var person := {"id": "player", "room": "street", "home_id": "player", "pos": [at.x, at.y], "appearance": appearance, "sleep": {"kind": "exhaustion", "remaining": 8.0}}
			if Visuals.draw_sleeping(self, person, {"kind": "sleeping"}, "street"): rendered += 1

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in 4: await process_frame

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --ui-test to isolate player progress and providers.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := MainProbe.new()
	viewport.add_child(scene)
	await settle()
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	scene.hide_inspector()
	scene.overlay.dismiss_toast()
	var player: Dictionary = scene.colony.get_resident("player")
	player.room = "street"
	player.pos = [306.0, 242.0]
	player.target = player.pos.duplicate()
	player.energy = 0.0
	var fixed_position: Array = player.pos.duplicate()
	var appearance: Dictionary = player.appearance.duplicate(true)
	expect(scene.colony.ensure_exhaustion(), "zero energy begins exhaustion in the isolated world")
	scene.sleep_ui.refresh()
	scene.refresh_status()
	await settle()
	var sleep_ui = scene.sleep_ui
	expect(is_instance_valid(sleep_ui.banner) and sleep_ui.heading.text == "Sin energía", "exhaustion displays its own clear heading")
	expect(sleep_ui.status.text == "Descansando · 8 s" and sleep_ui.progress.value == 0.0, "initial countdown and progress describe eight real seconds")
	expect(not sleep_ui.wake_button.visible and sleep_ui.wake_button.disabled, "exhaustion has no early wake action")
	expect(sleep_ui.banner.size == Vector2(216, 68) and sleep_ui.banner.get_global_rect().encloses(sleep_ui.progress.get_global_rect()), "compact banner contains the complete progress track")
	expect(sleep_ui.status.get_minimum_size().x <= sleep_ui.status.size.x and sleep_ui.banner.get_global_rect().encloses(sleep_ui.status.get_global_rect()), "countdown fits at the actual native UI font size")
	expect(scene.speed_button.disabled and scene.speed_button.tooltip_text.contains("ocho segundos"), "speed control explains real-time exhaustion instead of accelerated hours")
	sleep_ui.wake()
	sleep_ui.wake_button.pressed.emit()
	expect(scene.colony.is_exhausted() and player.sleep.remaining == 8.0, "stale wake callbacks cannot bypass exhaustion")
	expect(not sleep_ui.start(60), "a stale bed-duration callback cannot replace exhaustion")
	sleep_ui.show_choices()
	expect(not is_instance_valid(sleep_ui.panel), "bed choices do not open during exhaustion")
	var state: Dictionary = scene.colony.daily_state("player")
	var geometry: Dictionary = Visuals.exhaustion_layout(player, state, "street")
	expect(not geometry.is_empty() and geometry.anchor == Vector2(306, 242), "floor pose anchors at the exact logical location")
	expect(geometry.rect.size == Vector2(32, 24) and is_equal_approx(geometry.rotation, -PI / 2.0), "sleep pose rotates native sprite pixels horizontally without stretching")
	expect(Visuals.sort_y(player, state, "street", geometry.anchor) == 242.0 and Visuals.visual_anchor(player, state, "street", geometry.anchor) == geometry.anchor, "exhaustion remains in its ordinary floor depth layer")
	var inside: Dictionary = player.duplicate(true)
	inside.room = "player"
	expect(not Visuals.is_bed_sleep(inside, state, "player") and not Visuals.exhaustion_layout(inside, state, "player").is_empty(), "exhaustion in the player's house also stays on the floor")
	expect(Visuals.exhaustion_layout(player, state, "player").is_empty() and Visuals.exhaustion_layout(player, {"kind": "idle"}, "street").is_empty(), "floor pose is limited to the sleeping resident in the visible room")
	expect(player.pos == fixed_position and player.appearance == appearance, "presentation never teleports or modifies the customized appearance")
	if "--capture-exhaustion" in OS.get_cmdline_user_args():
		scene.actors.queue_redraw()
		await settle()
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://../artifacts/exhaustion")
		DirAccess.make_dir_recursive_absolute(directory)
		expect(viewport.get_texture().get_image().save_png(directory.path_join("world-exhaustion.png")) == OK, "isolated world exhaustion capture exported")
		var preview_viewport := SubViewport.new()
		preview_viewport.size = Vector2i(960, 296)
		preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(preview_viewport)
		var preview := PosePreview.new()
		preview.scale = Vector2(4, 4)
		preview_viewport.add_child(preview)
		await settle()
		await RenderingServer.frame_post_draw
		expect(preview.rendered == 4 and preview_viewport.get_texture().get_image().save_png(directory.path_join("floor-poses.png")) == OK, "four customized floor poses rendered with native existing layers")
		preview_viewport.free()
	scene.colony.advance_exhaustion(4.25)
	sleep_ui.refresh()
	expect(sleep_ui.status.text == "Descansando · 4 s" and is_equal_approx(sleep_ui.progress.value, 53.125), "refresh tracks fractional real-time progress without inventing game hours")
	scene.colony.advance_exhaustion(3.75)
	sleep_ui.refresh()
	scene.refresh_status()
	await settle()
	expect(not is_instance_valid(sleep_ui.banner) and not scene.colony.is_sleeping("player") and scene.colony.player_energy() == 5.0, "completed exhaustion removes its banner at five percent energy")
	expect(player.pos == fixed_position and player.appearance == appearance, "waking leaves the player and clothes at the original location")
	player.room = "player"
	var bed: Vector2 = Layout.stand_at("bed", "player")
	player.pos = [bed.x, bed.y]
	player.target = player.pos.duplicate()
	player.energy = 35.0
	scene.update_room()
	expect(sleep_ui.start(60), "ordinary bed sleep remains available afterward")
	expect(sleep_ui.heading.text == "Durmiendo" and sleep_ui.wake_button.visible and not sleep_ui.wake_button.disabled and sleep_ui.banner.size.x == 300, "normal sleep restores its title, width and early wake button")
	expect(sleep_ui.status.text.contains("1h 00m") and scene.speed_button.tooltip_text.contains("hora"), "normal sleep keeps the accelerated-hours explanation")
	expect(Visuals.is_bed_sleep(player, scene.colony.daily_state("player"), "player"), "normal sleep still renders under the bed's actual quilt")
	sleep_ui.wake_button.pressed.emit()
	expect(not scene.colony.is_sleeping("player"), "normal early wake still works")
	expect(scene.provider_calls == 0 and not scene.save_allowed and scene.preview_mode, "UI exercise makes no provider calls and cannot save real progress")
	scene.free()
	viewport.free()
	print("EXHAUSTION UI: %d/%d checks passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
