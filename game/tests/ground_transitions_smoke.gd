extends SceneTree
## No save, providers or raster generation. Optional --capture renders existing PNGs.
const Ground = preload("res://scripts/ground_transitions.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Nav = preload("res://scripts/navigation.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const FontAsset = preload("res://assets/fonts/PixelifySans.ttf")
var checks := 0
var failures: Array[String] = []
var samples := 0

class View extends Node2D:
	var room := "street"
	var before := false
	func _draw():
		if not before:
			Sprites.draw_world(self,FontAsset,false,room)
		else:
			var layout: Dictionary=Layout.section(room)
			Sprites._tile(self,"tile_grass",Sprites.WORLD_RECT,Color(str(layout.get("grass_tint","ffffff"))),true)
			for background: Dictionary in layout.get("background_props",[]):
				Sprites._tile(self,str(background.id),Layout.rect(background.rect))
			for item: Dictionary in layout.get("ground",[]):
				for strip: Rect2 in legacy_strips(item):
					Sprites._tile(self,str(item.id),strip,Color(str(item.get("tint","ffffff"))),true)
			Sprites._draw_exit_labels(self,FontAsset,room)
		for object: Dictionary in Sprites.scenery_objects(room): Sprites.draw_object(self,object,FontAsset)
		var edge: Dictionary=Layout.exits(room)[0]
		Sprites.draw_person(self,edge.at-Vector2(0,10),{"shirt":1,"hat":1})

	static func legacy_strips(item: Dictionary) -> Array[Rect2]:
		var area: Rect2=Layout.rect(item.rect)
		if int(item.get("corner_cut",0))!=4:return [area]
		return [Rect2(area.position+Vector2(4,0),Vector2(area.size.x-8,2)),Rect2(area.position+Vector2(2,2),Vector2(area.size.x-4,2)),Rect2(area.position+Vector2(0,4),Vector2(area.size.x,area.size.y-8)),Rect2(area.position+Vector2(2,area.size.y-4),Vector2(area.size.x-4,2)),Rect2(area.position+Vector2(4,area.size.y-2),Vector2(area.size.x-8,2))]

func _initialize():call_deferred("run")
func expect(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func painted(plan: Dictionary,point: Vector2,id: String="") -> bool:
	for item: Dictionary in plan.base:
		if (id.is_empty() or item.id==id) and item.rect.has_point(point):return true
	return false
func run():
	if "--ui-test" not in OS.get_cmdline_user_args():quit(1);return
	var maximum := 0
	for room: String in Layout.outdoor_ids():
		var section: Dictionary=Layout.section(room)
		var before: String=JSON.stringify(section)
		var obstacles_before: Array=Layout.obstacles(room).duplicate(true)
		var plan: Dictionary=Ground.plan(section.ground,Sprites.WORLD_RECT)
		maximum=maxi(maximum,plan.fringes.size())
		expect(JSON.stringify(section)==before and Layout.obstacles(room)==obstacles_before,"renderer keeps immutable layout and collisions: "+room)
		expect(Ground.plan(section.ground,Sprites.WORLD_RECT)==plan,"deterministic cached plan: "+room)
		expect(not plan.fringes.is_empty() and plan.fringes.size()<512,"nonempty bounded edge geometry: "+room)
		var valid := true
		for piece: Dictionary in plan.fringes:
			valid=valid and piece.id in ["tile_sand","tile_stone"] and piece.rect.has_area() and Sprites.WORLD_RECT.encloses(piece.rect)
			valid=valid and piece.rect.position==piece.rect.position.round() and piece.rect.size==piece.rect.size.round()
			for original: Dictionary in section.ground:
				if piece.rect.intersects(Layout.rect(original.rect)):valid=false
		expect(valid,"native texture fringes only cover previously bare ground: "+room)
		# Every pre-existing non-pond terrain pixel remains covered. This checks
		# actual unions and corners, not just unchanged metadata or centre points.
		var kept := true
		for item: Dictionary in section.ground:
			if str(item.get("key",""))=="stream_bank":continue
			for strip: Rect2 in View.legacy_strips(item):
				for y in range(int(strip.position.y),int(strip.end.y)):
					for x in range(int(strip.position.x),int(strip.end.x)):
						samples+=1
						if not painted(plan,Vector2(x+0.5,y+0.5),str(item.id)):kept=false
		expect(kept,"all original path and plaza pixels remain covered: "+room)
		for edge: Dictionary in Layout.exits(room):
			expect(painted(plan,edge.at,"tile_sand") and Nav.is_walkable(edge.at,room),"exit retains visible traversable ground: "+edge.id)
			var other: Dictionary=Ground.plan(Layout.section(edge.to).ground,Sprites.WORLD_RECT)
			expect(painted(other,edge.spawn,"tile_sand") and Nav.is_walkable(edge.spawn,edge.to),"arrival retains visible traversable ground: "+edge.id)
			var route: Array=Nav.route(edge.at,Layout.exits(room)[0].at,room)
			expect(not route.is_empty() and route.back().distance_to(Layout.exits(room)[0].at)<0.01,"portal connection remains exact: "+edge.id)
	var forest: Dictionary=Ground.plan(Layout.section("forest").ground,Sprites.WORLD_RECT)
	var water := Rect2(322,224,100,44)
	var bank := Rect2(314,216,116,60)
	var shore_inside: bool = not forest.shore.is_empty()
	for piece: Dictionary in forest.shore:
		shore_inside=shore_inside and piece.id=="tile_stone" and water.encloses(piece.rect) and bank.encloses(piece.rect)
	expect(shore_inside,"shore pixels stay within the existing pond and solid footprint")
	var covered := true
	for y in range(224,268):
		for x in range(322,422):
			var point := Vector2(x+0.5,y+0.5)
			var visible := painted(forest,point,"tile_water")
			for piece: Dictionary in forest.shore: visible=visible or piece.rect.has_point(point)
			covered=covered and visible and not Nav.is_walkable(point,"forest")
	expect(covered,"entire impassable pond remains visibly water or stone, never grass")
	for index in range(24):
		Ground.plan([{"id":"tile_sand","rect":[40+index,170,64,32]}],Sprites.WORLD_RECT)
	expect(Ground._plans.size()<=Ground.MAX_PLANS,"geometry cache has a fixed bound")
	if "--capture" in OS.get_cmdline_user_args():await capture()
	print("Ground transitions %d/%d; %d preserved terrain samples; max %d fringe rectangles" % [checks-failures.size(),checks,samples,maximum])
	quit(0 if failures.is_empty() else 1)

func capture():
	var directory: String=OS.get_environment("MY_CITY_TRANSITION_CAPTURE")
	if directory.is_empty():directory=ProjectSettings.globalize_path("res://../artifacts/terrain-transitions")
	DirAccess.make_dir_recursive_absolute(directory)
	var font: FontFile=FontAsset
	font.antialiasing=TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning=TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.oversampling=1.0
	for room: String in ["street","homes","forest"]:
		for before: bool in [true,false]:
			var viewport:=SubViewport.new()
			viewport.size=Vector2i(936,488)
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var view:=View.new()
			view.room=room;view.before=before;view.scale=Vector2(2,2);view.position=Vector2(-24,-96)
			viewport.add_child(view)
			await process_frame
			await RenderingServer.frame_post_draw
			expect(viewport.get_texture().get_image().save_png(directory+"/"+room+("-before" if before else "-after")+".png")==OK,"capture "+room)
			viewport.queue_free()
			await process_frame
