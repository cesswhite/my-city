extends SceneTree
## Modular riding, native source pixels, four facings and bounded pose caching.
const Sprites = preload("res://scripts/sprite_art.gd")
const Rider = preload("res://scripts/bicycle_rider.gd")
const DIRECTIONS = [Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2.UP]
var checks := 0
var failures: Array[String] = []

class ContactSheet:
	extends Node2D
	func _draw() -> void:
		for row in 4:
			var direction: Vector2 = DIRECTIONS[row]
			var appearance := {"skin":row,"shirt":row,"pants":row,"hair_style":row,"hair":row,"hat":row,"beard":row%3,"eyes":row}
			var y: float = 48+row*53
			Sprites.draw_person(self,Vector2(24,y),appearance,1,false,0,direction)
			var frame: Dictionary = Sprites.frame_info("bicycle_riding",false,0,direction)
			Sprites._paint(self,frame,Rect2(Vector2(52,y)-Vector2(20,30),Vector2(40,32)),Color.WHITE)
			for phase in 4:
				Sprites.draw_bicycle(self,Vector2(94+phase*40,y),appearance,true,phase,direction)

static func appearance_for(index: int) -> Dictionary:
	return {"skin":index%6,"shirt":index%6,"pants":index%5,"hair_style":index%4,"hair":index%6,"hat":index%4,"beard":index%3,"eyes":index%5}

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: "+description)
	else:
		failures.append(description)
		push_error("FAIL: "+description)

func part_signature(parts: Array[Dictionary]) -> int:
	var values: Array = []
	for part in parts: values.append([part.id,part.source,part.rect,part.tint])
	return hash(values)

func capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,872)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("65736b")
	background.size = viewport.size
	viewport.add_child(background)
	var sheet := ContactSheet.new()
	sheet.scale = Vector2(4,4)
	viewport.add_child(sheet)
	var font: Font = load("res://assets/fonts/PixelOperator.ttf")
	for row in 4:
		var label := Label.new()
		label.position = Vector2(12,6+row*212)
		label.text = ["Abajo","Izquierda","Derecha","Arriba"][row]
		label.add_theme_font_override("font",font)
		label.add_theme_font_size_override("font_size",16)
		viewport.add_child(label)
	for index in 6:
		var label := Label.new()
		label.position = Vector2([54,172,328,488,648,808][index],850)
		label.text = ["A pie","Bicicleta","Pedal 1","Pedal 2","Pedal 3","Pedal 4"][index]
		label.add_theme_font_override("font",font)
		label.add_theme_font_size_override("font_size",16)
		viewport.add_child(label)
	for _frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var output: String = ProjectSettings.globalize_path("res://../artifacts/bicycle")
	DirAccess.make_dir_recursive_absolute(output)
	var screenshot: Image = viewport.get_texture().get_image()
	expect(screenshot.save_png(output.path_join("bicycle-directions.png")) == OK,"real renderer saved four facings, walking comparison and all sixteen rider frames at integer 4x")
	# Distinct complete frames, including the native bike pedals and customized rider.
	for row in 4:
		var frame_hashes: Dictionary = {}
		for phase in 4:
			var x: int = (94+phase*40-20)*4
			var y: int = (48+row*53-46)*4
			var bytes: PackedByteArray = screenshot.get_region(Rect2i(x,y,160,184)).get_data()
			frame_hashes[hash(bytes)] = true
		expect(frame_hashes.size() == 4,"rendered pedal phases differ for facing "+str(row))
	viewport.free()

func run() -> void:
	var metadata: Dictionary = Sprites.manifest_data().assets.bicycle_riding
	expect(int(metadata.frames) == 4 and str(metadata.directions[0]) == "down" and str(metadata.directions[1]) == "left" and str(metadata.directions[2]) == "right" and str(metadata.directions[3]) == "up" and Vector2(metadata.frame_size[0],metadata.frame_size[1]) == Vector2(40,32),"bike atlas declares four native facings and four actual pedal frames")
	var direction_regions: Dictionary = {}
	for direction: Vector2 in DIRECTIONS:
		var pose: Dictionary = Sprites.bicycle_pose(direction)
		var at := Vector2(304,180)
		var click_bounds: Rect2 = Sprites.bicycle_actor_rect(at,direction)
		var ground: Vector2 = at+Vector2(18,-20) if direction in [Vector2.DOWN,Vector2.UP] else at+Vector2(19,-15)
		expect(not click_bounds.has_point(ground), "transparent bike padding leaves adjacent ground clickable for "+str(direction))
		expect(click_bounds.has_point(at+Vector2(0,-10)), "mounted rider stays selectable for "+str(direction))
		var layers: Array[Dictionary] = Sprites.character_layers(appearance_for(3),false,0,direction)
		var frame: Dictionary = Sprites.frame_info("bicycle_riding",false,0,direction)
		direction_regions[frame.source.position] = true
		var variants: Dictionary = {}
		var stationary: int = part_signature(Rider.parts(Vector2.ZERO,layers,false,0,direction,pose))
		var unchanged_head: int = 0
		for phase in 4:
			var pieces: Array[Dictionary] = Rider.parts(Vector2.ZERO,layers,true,phase,direction,pose)
			var native := not pieces.is_empty()
			var contained := true
			var head: Array = []
			for part: Dictionary in pieces:
				var source: Rect2 = part.source
				var expected_size := Vector2(source.size.y,source.size.x) if part.transpose else source.size
				native = native and part.rect.size == expected_size and part.rect.position == part.rect.position.round() and Rect2(Vector2.ZERO,part.texture.get_size()).encloses(source)
				contained = contained and Rider.actor_rect(Vector2.ZERO,direction,pose).encloses(part.rect)
				if source.size.y == 20: head.append([part.id,source,part.rect,part.tint])
			expect(native and contained,"native regions and picking bounds cover facing %s phase %d" % [direction,phase])
			if phase == 0: unchanged_head = hash(head)
			expect(hash(head) == unchanged_head,"head, face and accessories stay undistorted through pedal phase %d / %s" % [phase,direction])
			variants[part_signature(pieces)] = true
			expect(part_signature(Rider.parts(Vector2.ZERO,layers,false,phase,direction,pose)) == stationary,"stopped rider freezes pedaling for phase %d / %s" % [phase,direction])
		expect(variants.size() == 4,"bent legs make four distinct phases for "+str(direction))
	expect(direction_regions.size() == 4,"left, right, front and back use independent PNG atlas rows")
	var customization := true
	for index in 12:
		var appearance: Dictionary = appearance_for(index)
		var layers: Array[Dictionary] = Sprites.character_layers(appearance,false,0,Vector2.RIGHT)
		var pieces: Array[Dictionary] = Rider.parts(Vector2.ZERO,layers,true,index%4,Vector2.RIGHT)
		for layer: Dictionary in layers:
			var found := false
			for part: Dictionary in pieces:
				if part.id == layer.id and part.tint == layer.tint: found = true
			customization = customization and found
	expect(customization,"all twelve appearance combinations retain each original skin, clothing, eye, hair, beard and hat layer")
	var stable_layers: Array[Dictionary] = Sprites.character_layers(appearance_for(0))
	Rider.parts(Vector2.ZERO,stable_layers,true,0)
	var size: int = Rider._poses.size()
	for frame in 120: Rider.parts(Vector2(frame,frame),stable_layers,true,0)
	expect(Rider._poses.size() == size,"moving the actor reuses its pose cache instead of reading or rebuilding textures")
	for index in 100:
		Rider.parts(Vector2.ZERO,stable_layers,true,0,Vector2.DOWN,{"hand_span":index%12+1,"hip_offset":Vector2(index,-23)})
	expect(Rider._poses.size() <= 64,"pose cache is bounded across changed appearance metadata")
	expect(Rider.parts(Vector2(INF,0),stable_layers).is_empty() and not Rider.actor_rect(Vector2(NAN,0)).has_area(),"invalid world positions cannot emit corrupt draw commands")
	if "--capture-bicycle" in OS.get_cmdline_user_args(): await capture()
	print("BICYCLE VISUAL: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
