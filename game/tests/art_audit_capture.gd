extends SceneTree
## Deterministic presentation audit. No Colony, save loading, simulation, network or asset writes.
## --capture --output=artifacts/art-direction/before (run with a real rendering driver).
## Optional --manifest=res://assets/sprites/art-v2/manifest.json previews staged art only.
const Sprites = preload("res://scripts/sprite_art.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Registry = preload("res://scripts/resident_catalog.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Lighting = preload("res://scripts/world_lighting.gd")
const Ambient = preload("res://scripts/ambient_environment.gd")
const Seats = preload("res://scripts/seating.gd")
const Crops = preload("res://scripts/crop_sprites.gd")
const Activities = preload("res://scripts/activity_visuals.gd")
const FontAsset = preload("res://assets/fonts/PixelifySans.ttf")
const ROOMS := ["street","gardens","homes","workshops","atelier","forest","cesar","lupita","mateo","ines","alma","player"]
const SCENE_SIZE := Vector2i(936,488)
const MAGENTA := Color("ff68c8")
const CYAN := Color("54e7ff")
const GOLD := Color("ffe47d")
var checks := 0
var failures: Array[String] = []
var output := "artifacts/art-direction/before"
var manifest_path: String = Sprites.MANIFEST_PATH
var captures: Array[String] = []

class Surface extends Node2D:
	var room := "street"
	var minute := 720
	var font: Font
	var people: Array[Dictionary] = []
	var environment = Ambient.new()
	var project_state := {"garden_planted":true,"tea_ready":true,"bicycle_repaired":true}
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		modulate = Lighting.ambient_for(minute,room)
		environment.advance(0.01,minute,room,false)
		environment.elapsed = 8.25
	func _draw() -> void:
		if Layout.is_outdoor(room): Sprites.draw_world(self,font,false,room,project_state)
		else: Sprites.draw_interior(self,font,room,project_state,false)
		Lighting.draw_fixtures(self,room)
		Lighting.draw_fixture_lights(self,room,minute)
		var items: Array = Sprites.scenery_objects(room,project_state)
		for person in people:
			var state: Dictionary = person.audit_state
			items.append({"actor":person,"y":Activities.sort_y(person,state,room,Layout.point(person.pos))})
		items.sort_custom(func(a,b): return float(a.y)<float(b.y))
		for item in items:
			if item.has("actor"):
				var person: Dictionary = item.actor
				if not Activities.draw_sleeping(self,person,person.audit_state,room): Sprites.draw_person(self,Layout.point(person.pos),person.appearance,1,false,0,Vector2.DOWN)
			else:
				if not environment.draw_object(self,item,font): Sprites.draw_object(self,item,font)
				Lighting.draw_object_lights(self,item,room,minute)
				if not Layout.is_outdoor(room) and item.id == "window": Lighting.draw_window_view(self,item,minute)
		environment.draw_foreground(self,room)

class Lights extends Node2D:
	var room := "street"
	var minute := 720
	func _ready() -> void:
		var blend := CanvasItemMaterial.new()
		blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = blend
	func _draw() -> void: Lighting.draw(self,room,minute,8.25)

class Markers extends Node2D:
	var room := "street"
	var font: Font
	func cross(at: Vector2, tint: Color) -> void:
		draw_line(at-Vector2(2,0),at+Vector2(2,0),tint,1)
		draw_line(at-Vector2(0,2),at+Vector2(0,2),tint,1)
	func _draw() -> void:
		draw_rect(Layout.bounds(room),Color("ffffff"),false,1)
		for prop in Sprites.scenery_objects(room,{"garden_planted":true,"tea_ready":true,"bicycle_repaired":true}):
			draw_rect(prop.rect,Color(CYAN,0.60),false,1)
			if prop.has("footprint"): draw_rect(prop.footprint,Color(MAGENTA,0.90),false,1)
			draw_line(Vector2(prop.rect.position.x,prop.y),Vector2(prop.rect.end.x,prop.y),Color(GOLD,0.8),1)
			if prop.has("support_point"): cross(prop.support_point,Color.WHITE)
		for id in Layout.section(room).get("interactions",{}): cross(Layout.stand_at(id,room),Color("89ff99"))
		if Layout.is_outdoor(room):
			for home in Layout.data().doors:
				if Layout.home_area(home)!=room: continue
				cross(Layout.door_positions()[home],MAGENTA)
				var opening: Dictionary = Layout.data().door_openings[home]
				for object in Sprites.scenery_objects(room):
					if object.key==opening.prop_key: draw_rect(Rect2(object.rect.position+Layout.point(opening.rect.slice(0,2)),Layout.point(opening.rect.slice(2,4))),MAGENTA,false,1)
			for seat in Seats.seats(room):
				draw_rect(seat.rect,GOLD,false,1); cross(seat.anchor,GOLD); cross(seat.stand_at,Color("89ff99"))
			for edge in Layout.exits(room): cross(edge.at,Color.WHITE)
		else:
			cross(Layout.point(Layout.data().entry),Color.WHITE)
			cross(Layout.point(Layout.data().exit),MAGENTA)
			var sleep: Dictionary = Activities.sleep_layout(room)
			draw_rect(sleep.head,GOLD,false,1); draw_rect(sleep.quilt,CYAN,false,1)
		draw_string(font,Vector2(16,59),room+" | cyan sprite, pink solid/door, gold depth/pose, green stand",HORIZONTAL_ALIGNMENT_LEFT,-1,7,Color.WHITE)

class Sources extends Node2D:
	var ids := ["cafe","homes","alma_home","workshop","player_home","shop","fountain","cafe_table","bench","bed","tree","tree_small","bunting","flowerpot","plant","lamp","garden_left","garden_right","char_details","hair_0","hat_1","beard_1","bicycle_riding","tea_set"]
	var font: Font
	func _draw() -> void:
		draw_rect(Rect2(0,0,792,528),Color("28362e"))
		for index in ids.size():
			var id: String = ids[index]
			var info: Dictionary = Sprites.frame_info(id)
			var at := Vector2(index%6*132+10,int(index/6)*132+20)
			Sprites.draw_asset(self,id,Rect2(at,info.source.size))
			draw_string(font,at+Vector2(0,-6),id,HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color.WHITE)
			draw_rect(Rect2(at,info.source.size),Color(CYAN,0.6),false,1)
			for region in Lighting.object_light_regions(id): draw_rect(Rect2(at+region.position,region.size),GOLD,false,1)
			if Ambient.CROWN_LIMITS.has(id): draw_line(at+Vector2(0,Ambient.CROWN_LIMITS[id]),at+Vector2(info.source.size.x,Ambient.CROWN_LIMITS[id]),MAGENTA,1)
			if Ambient.CHIMNEYS.has(id): draw_circle(at+Ambient.chimney_at(id),2,MAGENTA)
			if id=="bunting":
				for region in Ambient.flag_sections(): draw_rect(Rect2(at+region.position,region.size),GOLD,false,1)
			if id=="bed":
				var sleep: Dictionary = Activities.sleep_layout("player")
				draw_rect(Rect2(at+sleep.head.position-sleep.bed.position,sleep.head.size),GOLD,false,1)
				draw_rect(Rect2(at+sleep.quilt_source.position,sleep.quilt_source.size),MAGENTA,false,1)
			for crop in Crops.variants(Sprites.uses_revised_art("garden_right")):
				if crop.asset==id: draw_rect(Rect2(at+crop.source.position,crop.source.size),GOLD,false,1)
			for seat in Seats.seats("street"):
				for object in Sprites.scenery_objects("street"):
					if object.key==seat.prop_key and object.id==id: draw_rect(Rect2(at+seat.source_rect.position,seat.source_rect.size),GOLD,false,1)
			for home in Layout.data().door_openings:
				var opening: Dictionary=Layout.data().door_openings[home]
				if opening.building!=id: continue
				var source_offset:=Vector2.ZERO
				for object in Sprites.scenery_objects(Layout.home_area(home)):
					if object.key==opening.prop_key and object.has("source_rect"): source_offset=object.source_rect.position
				var rect: Rect2 = Layout.rect(opening.rect)
				draw_rect(Rect2(at+source_offset+rect.position,rect.size),MAGENTA,false,1)

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func jsonable(value):
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Rect2: return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is Color: return value.to_html()
	if value is Array:
		var result: Array=[]
		for item in value: result.append(jsonable(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:
			if value[key] is Object: continue
			result[str(key)] = jsonable(value[key])
		return result
	return value

func actors_for(room: String, night: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in Registry.ids():
		if Layout.is_outdoor(room) and Layout.resident_spawn(id).room!=room: continue
		if not Layout.is_outdoor(room) and id not in [room,"player"]: continue
		var person: Dictionary=Registry.data()[id].duplicate(true)
		var at: Vector2=Layout.resident_spawn(id).position if Layout.is_outdoor(room) else (Layout.point(Layout.data().home_rest) if id==room else Layout.point(Layout.data().entry))
		at=Navigation.recover_position(at,room)
		person.room=room;person.home_id=id;person.pos=[at.x,at.y];person.target=person.pos.duplicate();person.audit_state={"kind":"idle"}
		if night and not Layout.is_outdoor(room) and id==room: person.audit_state={"kind":"sleeping"}
		result.append(person)
	return result

func attach(canvas: Node2D, viewport: SubViewport) -> void:
	canvas.scale=Vector2(2,2);canvas.position=Vector2(-24,-96);viewport.add_child(canvas)

func save_view(viewport: SubViewport, filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String=ProjectSettings.globalize_path("res://../"+output+"/"+filename)
	var image: Image=viewport.get_texture().get_image()
	expect(image!=null and not image.is_empty(),"rendered image "+filename)
	if image!=null and not image.is_empty():
		expect(image.save_png(path)==OK,"export "+filename); captures.append(filename)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--manifest="): manifest_path=arg.trim_prefix("--manifest=")
	if not output.begins_with("artifacts/") or ".." in output: push_error("Output must be inside artifacts/"); quit(2);return
	var capture: bool="--capture" in OS.get_cmdline_user_args()
	var loaded: Error = Sprites.reload_manifest(manifest_path)
	expect(loaded == OK,"selected manifest loads: "+manifest_path)
	if loaded != OK: push_error(Sprites.last_error);quit(1);return
	expect(Sprites.validation_errors().is_empty(),"current sprite resources load")
	if not failures.is_empty(): quit(1);return
	var font: FontFile=FontAsset
	font.antialiasing=TextServer.FONT_ANTIALIASING_NONE;font.subpixel_positioning=TextServer.SUBPIXEL_POSITIONING_DISABLED;font.oversampling=1
	var active_windows: Dictionary = {}
	for id in Lighting.WINDOW_PANES: active_windows[id] = Lighting.window_panes(id)
	var active_chimneys: Dictionary = {}
	for id in Ambient.CHIMNEYS: active_chimneys[id] = Ambient.chimney_at(id)
	var contract: Dictionary={"world_rect":Sprites.WORLD_RECT,"manifest":Sprites.manifest_data(),"doors":Layout.data().door_openings,"door_feet":Layout.data().doors,"places":Layout.data().places,"interior_entry":Layout.data().entry,"interior_exit":Layout.data().exit,"riding_bicycle":Layout.data().riding_bicycle,"lighting_windows":active_windows,"lighting_indoor":Lighting.indoor_panes(),"lamp_core":Lighting.lamp_core(),"crown_cuts":Ambient.CROWN_LIMITS,"chimneys":active_chimneys,"flag_sections":Ambient.flag_sections(),"crop_cuts":Crops.variants(Sprites.uses_revised_art("garden_right")),"head_crop":Activities.HEAD_SOURCE,"rooms":{}}
	for room in ROOMS:
		var objects: Array=Sprites.scenery_objects(room,{"garden_planted":true,"tea_ready":true,"bicycle_repaired":true})
		contract.rooms[room]={"bounds":Layout.bounds(room),"objects":objects,"interactions":Layout.section(room).get("interactions",{}),"seats":Seats.seats(room) if Layout.is_outdoor(room) else [],"sleep":{} if Layout.is_outdoor(room) else Activities.sleep_layout(room)}
		expect(not objects.is_empty(),"scenery exists "+room)
		for object in objects:
			if object.get("tile",false) or object.get("crop_row",false) or object.get("fixed_size",false): continue
			var info: Dictionary=Sprites.object_frame(object)
			expect(not info.is_empty() and object.rect.size==info.source.size,"native size "+room+":"+str(object.key))
	if not capture:
		print("ART AUDIT %d/%d checks; add --capture for baseline images"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1);return
	if DisplayServer.get_name()=="headless": push_error("Capture needs a real rendering driver; no blank screenshots exported.");quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../"+output))
	for room in ROOMS:
		for mode in ["day","night","markers"]:
			var viewport:=SubViewport.new();viewport.size=SCENE_SIZE;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
			var minute: int=1320 if mode=="night" else 720
			var surface:=Surface.new();surface.room=room;surface.minute=minute;surface.font=font;surface.people=actors_for(room,mode=="night");attach(surface,viewport)
			var lights:=Lights.new();lights.room=room;lights.minute=minute;attach(lights,viewport)
			if mode=="markers":
				var markers:=Markers.new();markers.room=room;markers.font=font;attach(markers,viewport)
			await save_view(viewport,room+"-"+mode+".png")
			viewport.queue_free();await process_frame
	var source_view:=SubViewport.new();source_view.size=Vector2i(1584,1056);source_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(source_view)
	var sources:=Sources.new();sources.font=font;sources.scale=Vector2(2,2);source_view.add_child(sources)
	await save_view(source_view,"source-markers.png");source_view.queue_free();await process_frame
	contract["capture"]={"output":output,"manifest_path":manifest_path,"scale":2,"minute_day":720,"minute_night":1320,"ambient_elapsed":8.25,"images":captures,"note":"Presentation fixtures: developed scenery, authored appearance, owner sleeping in night interior; no simulation/save or provider calls."}
	var file:=FileAccess.open(ProjectSettings.globalize_path("res://../"+output+"/anchors.json"),FileAccess.WRITE)
	expect(file!=null,"anchor contract export")
	if file!=null:file.store_string(JSON.stringify(jsonable(contract),"\t"));file.close()
	print("ART AUDIT %d/%d checks, %d captures, %s"%[checks-failures.size(),checks,captures.size(),output])
	quit(0 if failures.is_empty() else 1)
