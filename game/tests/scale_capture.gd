extends SceneTree
## Captures existing renderer output only. No save, providers, simulation or generated artwork.
const Layout = preload("res://scripts/world_layout.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const SIZE := Vector2i(500, 330)
var output_dir: String = ""

class ScaleView extends Node2D:
	var room: String = "street"
	var state: Dictionary = {}
	var font: Font
	func _draw() -> void:
		var art = preload("res://scripts/sprite_art.gd")
		var layout = preload("res://scripts/world_layout.gd")
		draw_rect(Rect2(0, 0, 500, 330), Color("f8efd9"))
		var title: String = "ESCALA 1:1 / CALLE" if room == "street" else "ESCALA 1:1 / " + room.to_upper() + (" / TERMINADO" if not state.is_empty() else " / INICIAL")
		draw_string(font, Vector2(14, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("303e37"))
		if room == "street": art.draw_world(self, font, false)
		else: art.draw_interior(self, font, room, state, false)
		var draws: Array[Dictionary] = []
		for item in art.scenery_objects(room, state): draws.append({"type": "object", "object": item, "y": item.y})
		var positions: Array[Vector2] = []
		if room == "street":
			for door in layout.door_positions().values(): positions.append(door + Vector2(0, 8))
			positions.append(layout.point(layout.data().places.huerto))
			positions.append(layout.stand_at("shop", "street"))
		else:
			for key in ["bed", "tea_station", "planting", "bicycle"]: positions.append(layout.stand_at(key, room))
			positions.append(layout.point(layout.data().entry))
		for index in range(positions.size()): draws.append({"type": "actor", "at": positions[index], "index": index, "y": positions[index].y})
		draws.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.y) < float(b.y))
		for command in draws:
			if command.type == "object": art.draw_object(self, command.object, font)
			else: art.draw_person(self, command.at, {"skin": command.index % 6, "hair_style": command.index % 4, "shirt": command.index % 6, "hat": 0}, 1, false, 0, Vector2.DOWN)
		draw_string(font, Vector2(14, 316), "PNG nativo + personajes de 22 px visibles. Sin partida ni red.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("303e37"))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("scale_capture needs a graphical renderer; use scale_smoke for headless checks.")
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path("res://../artifacts/world-scale")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--output-dir": output_dir = args[index + 1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	if Sprites.reload_manifest() != OK or not Sprites.validation_errors().is_empty():
		push_error("Cannot capture missing or invalid sprites.")
		quit(1)
		return
	for spec in [
		{"name": "street", "room": "street", "state": {}},
		{"name": "player-initial", "room": "player", "state": {}},
		{"name": "player-completed", "room": "player", "state": {"garden_planted": true, "tea_ready": true, "bicycle_repaired": true}},
		{"name": "neighbor", "room": "cesar", "state": {}},
	]:
		var viewport := SubViewport.new()
		viewport.size = SIZE
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var view := ScaleView.new()
		view.room = str(spec.room)
		view.state = spec.state
		view.font = load("res://assets/fonts/PixelifySans.ttf")
		viewport.add_child(view)
		await process_frame
		await RenderingServer.frame_post_draw
		var captured: Image = viewport.get_texture().get_image()
		var path: String = output_dir.path_join(str(spec.name) + ".png")
		if captured.is_empty() or captured.save_png(path) != OK:
			push_error("Could not save scale capture: " + path)
			quit(1)
			return
		print("CAPTURE: " + path)
		viewport.queue_free()
		await process_frame
	quit(0)
