extends SceneTree
## Isolated seat renderer. No saves, input, providers, or colony instance.
const Seating = preload("res://scripts/seating.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const PixelFont = preload("res://assets/fonts/PixelifySans.ttf")

class Preview extends Node2D:
	var appearances: Array[Dictionary] = []
	func _init() -> void:
		for index in range(12):
			appearances.append({"skin":index%6,"shirt":index%6,"pants":index%5,"hair":index%6,"eyes":index%5,"hair_style":index%4,"hat":index%4,"beard":index%3})
	func _draw() -> void:
		Sprites.draw_world(self,PixelFont,false)
		var items: Array[Dictionary] = Sprites.scenery_objects("street")
		var index := 0
		for seat: Dictionary in Seating.seats():
			items.append({"actor":true,"seat":seat,"appearance":appearances[index],"y":seat.sort_y})
			index += 1
		items.sort_custom(func(a: Dictionary,b: Dictionary):return a.y<b.y)
		for item: Dictionary in items:
			if item.get("actor",false): Seating.draw_person(self,item.seat,item.appearance)
			else: Sprites.draw_object(self,item,PixelFont)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var directory: String = OS.get_environment("MY_CITY_SEATING_CAPTURE")
	if directory.is_empty():
		push_error("MY_CITY_SEATING_CAPTURE must name an existing output directory.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1404,732)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := Preview.new()
	preview.scale = Vector2(3,3)
	preview.position = Vector2(-36,-144)
	viewport.add_child(preview)
	for _frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = viewport.get_texture().get_image().save_png(directory.path_join("all-seats.png"))
	print("Seating capture: ",error_string(result))
	viewport.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
