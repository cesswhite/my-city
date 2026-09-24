extends SceneTree
## A real Control hierarchy isolates reader framing from HomeUI content/network.
const Camera = preload("res://scripts/conversation_camera.gd")
const Colony = preload("res://scripts/colony.gd")

class Reader:
	extends RefCounted
	var reading_panel: Panel
	func is_reading() -> bool: return reading_panel.visible

class Host:
	extends Control
	const WORLD_RECT := Rect2(12,48,468,244)
	var colony = Colony.new()
	var inspector := Panel.new()
	var exit_button := Button.new()
	var location := Panel.new()
	var hud := {"stats_panel":Panel.new(),"dock_panel":Panel.new()}
	var overlay := {"hint":Panel.new(),"toast":Panel.new()}
	var home_ui: RefCounted
	var current_room := "player"
	var selected_id := "mateo"
	var chat_partner_id := ""
	var world_scale := 1.0
	func position_of(person: Dictionary) -> Vector2: return Vector2(person.pos[0],person.pos[1])
	func pointer_actor_rect(person: Dictionary, _state: Dictionary) -> Rect2:
		# The full modular character frame includes all hats and feet, so this
		# visibility assertion is stricter than opaque-layer pointer hit bounds.
		return Rect2(position_of(person)-Vector2(12,30),Vector2(24,32))

var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func panel(host: Host, control: Control, rect: Rect2) -> void:
	if control.get_parent() == null: host.add_child(control)
	control.position = rect.position
	control.size = rect.size

func screen_actor(host: Host, base: Rect2, offset: Vector2) -> Rect2:
	var actor: Rect2 = host.pointer_actor_rect(host.colony.get_resident("player"),{})
	return Rect2(base.position+offset+(actor.position-host.WORLD_RECT.position)*host.world_scale,actor.size*host.world_scale)

func visible(host: Host, actor: Rect2, reader: Reader) -> bool:
	if not Rect2(Vector2.ZERO,host.size).encloses(actor): return false
	var to_host := host.get_global_transform().affine_inverse()
	for control: Control in [reader.reading_panel,host.hud.stats_panel,host.hud.dock_panel,host.location,host.overlay.hint,host.overlay.toast]:
		if control.is_visible_in_tree() and (to_host*control.get_global_rect()).intersects(actor): return false
	return true

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args(): quit(1); return
	root.size = Vector2i(1280,600)
	var host := Host.new()
	root.add_child(host)
	host.position = Vector2(27,13)
	host.colony.save_path = "user://test_reading_camera_%d.json" % OS.get_process_id()
	host.colony.setup(false, true)
	host.inspector.hide()
	host.overlay.hint.hide()
	host.overlay.toast.hide()
	host.location.add_child(host.exit_button)
	host.exit_button.position = Vector2(148,10)
	host.exit_button.size = Vector2(64,28)
	var camera := Camera.new(host)
	var reader := Reader.new()
	reader.reading_panel = Panel.new()
	var player: Dictionary = host.colony.get_resident("player")
	player.room = "player"
	player.travel_intent = ""
	for dimensions in [Vector2(768,432),Vector2(960,600),Vector2(1280,540)]:
		host.size = dimensions
		host.world_scale = minf(dimensions.x/468.0,dimensions.y/244.0)
		var map_size: Vector2 = host.WORLD_RECT.size*host.world_scale
		var base := Rect2(((dimensions-map_size)/2.0).round(),map_size)
		panel(host,host.hud.stats_panel,Rect2(12,12,268,44))
		panel(host,host.hud.dock_panel,Rect2((dimensions.x-286-224)/2,dimensions.y-56,224,44))
		panel(host,host.location,Rect2(12,64,224,48))
		panel(host,host.inspector,Rect2(dimensions.x-270,16,254,dimensions.y-32))
		panel(host,reader.reading_panel,Rect2(dimensions.x-270,80,254,240))
		panel(host,host.overlay.hint,Rect2(40,dimensions.y-100,260,28))
		panel(host,host.overlay.toast,Rect2(12,dimensions.y-160,330,48))
		host.home_ui = null
		check(camera.subjects().is_empty() and camera.advance(0,base,true) == Vector2.ZERO,"%s null HomeUI preserves the centered, closed-panel world" % dimensions)
		host.home_ui = reader
		reader.reading_panel.show()
		check(camera.subjects() == ["player"],"%s reading frames the player rather than a stale selected neighbor" % dimensions)
		var local_exit: Rect2 = host.get_global_transform().affine_inverse()*host.exit_button.get_global_rect()
		check(camera.safe_rect().position.y >= local_exit.end.y+12 and camera.safe_rect().end.x == reader.reading_panel.position.x-20,"%s safe space accounts for the reparented exit and actual reader edge" % dimensions)
		for at in [Vector2(370,228),Vector2(148,228)]:
			player.pos = [at.x,at.y]
			player.target = player.pos.duplicate()
			var before: Dictionary = player.duplicate(true)
			var offset: Vector2 = camera.advance(0,base,true)
			check(visible(host,screen_actor(host,base,offset),reader),"%s reader leaves complete character visible at %s" % [dimensions,at])
			check(player == before and host.world_scale == minf(dimensions.x/468.0,dimensions.y/244.0),"%s reading never moves the player, its goal or map scale" % dimensions)
		var unobstructed: Rect2 = camera.safe_rect()
		var unobstructed_offset: Vector2 = camera.advance(0,base,true)
		for notice: Control in [host.overlay.hint,host.overlay.toast]:
			var original_rect := notice.get_rect()
			notice.position = Vector2(dimensions.x-252,dimensions.y-160)
			notice.size = Vector2(240,58)
			notice.show()
			check(camera.safe_rect() == unobstructed and camera.advance(0,base,true) == unobstructed_offset,"%s notice outside the left framing band does not lift the player" % dimensions)
			notice.position.x = unobstructed.end.x-24
			var moved: Vector2 = camera.advance(0,base,true)
			check(camera.safe_rect().end.y < unobstructed.end.y and visible(host,screen_actor(host,base,moved),reader),"%s partially overlapping notice still reserves room and keeps the player clear" % dimensions)
			notice.hide()
			notice.position = original_rect.position
			notice.size = original_rect.size
		# A transient hint/toast may further reduce the available band.
		host.overlay.hint.show()
		host.overlay.toast.show()
		var offset: Vector2 = camera.advance(0,base,true)
		check(visible(host,screen_actor(host,base,offset),reader),"%s framing also clears the visible hint and toast" % dimensions)
		host.overlay.hint.hide()
		host.overlay.toast.hide()
		reader.reading_panel.hide()
		check(camera.subjects().is_empty() and camera.advance(0,base,true) == Vector2.ZERO,"%s closing the reader restores map centering" % dimensions)
		# Interior's compact dock is vertical only with both side panels closed.
		host.hud.dock_panel.size = Vector2(44,224)
		host.hud.dock_panel.position = Vector2(12,128)
		check(camera.advance(0,base,true) == Vector2.ZERO,"%s closed-reader vertical dock causes no unsolicited framing" % dimensions)
	check(host.colony.minute == 480 and not FileAccess.file_exists(host.colony.save_path),"reading uses no simulation time, provider or saved progress")
	host.free()
	print("READING CAMERA: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
