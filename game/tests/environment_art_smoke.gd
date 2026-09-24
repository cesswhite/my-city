extends SceneTree
const Art=preload("res://scripts/environment_art.gd")
const Sprites=preload("res://scripts/sprite_art.gd")
const Layout=preload("res://scripts/world_layout.gd")
const Catalog=preload("res://scripts/environmental_catalog.gd")
const Crops=preload("res://scripts/crop_sprites.gd")
const FontAsset=preload("res://assets/fonts/PixelOperator.ttf")
var checks:=0
var failures:Array[String]=[]
class View extends Node2D:
	var sample:Dictionary={}
	func _draw():
		Sprites._tile(self,"tile_grass",Sprites.WORLD_RECT,Color.WHITE,true)
		for item:Dictionary in Sprites.scenery_objects("forest",sample):
			if item.get("environment_object",false):Sprites.draw_object(self,item)
		for i in 6:
			draw_string(FontAsset,Vector2(35+i*69,165),str(i),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f4edda"))
		for i in 5:
			var cell:Dictionary={"id":"preview"+str(i),"stage":3 if i>2 else i+1,"condition":"bent" if i==3 else "healthy","bent":i==3,"destroyed":i==4,"index":i,"rect":Rect2(75+i*64,184,14,18),"at":Vector2(83+i*64,197)}
			Sprites._tile(self,"tile_soil",Rect2(69+i*64,181,30,24))
			for run:Dictionary in Art.crop_runs(cell,Sprites.frame_info,true):draw_texture_rect_region(run.texture,run.rect,run.source,run.tint)
			Sprites.draw_person(self,Vector2(83+i*64,220),{"shirt":i,"hair_style":i%4})
		Sprites.draw_asset(self,"window",Rect2(190,242,28,29))
		Sprites.draw_asset(self,"window_closed",Rect2(240,242,28,29))
		Sprites.draw_asset(self,"apple",Rect2(302,256,8,9))
		Sprites.draw_asset(self,"apple_golden",Rect2(324,256,8,9))
class GardenView extends Node2D:
	var sample: Dictionary={}
	func _draw():
		Sprites.draw_world(self,FontAsset,false,"gardens",sample)
		var objects: Array=Sprites.scenery_objects("gardens",sample)
		for i in 3:objects.append({"actor":true,"at":Vector2(367+i*30,245),"y":245.0,"index":i})
		objects.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.y)<float(b.y))
		for object:Dictionary in objects:
			if object.get("actor",false):Sprites.draw_person(self,object.at,{"shirt":object.index,"skin":object.index,"hair_style":object.index})
			else:Sprites.draw_object(self,object,FontAsset)
func _initialize():call_deferred("run")
func expect(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run():
	if "--ui-test" not in OS.get_cmdline_user_args():quit(1);return
	for pair:Array in [["tree_sapling",Vector2(18,26)],["tree_young",Vector2(26,36)],["apple",Vector2(8,9)],["apple_golden",Vector2(8,9)],["window_closed",Vector2(28,29)]]:
		var frame:Dictionary=Sprites.frame_info(pair[0])
		expect(not frame.is_empty() and frame.source.size==pair[1],"native asset size "+pair[0])
		var image:Image=frame.texture.get_image()
		if image.is_compressed():image.decompress()
		var binary:=true
		for y in image.get_height():
			for x in image.get_width():
				var a:float=image.get_pixel(x,y).a
				binary=binary and (a==0.0 or a==1.0)
		expect(binary,"binary alpha removes generated outside halos "+pair[0])
	var cell:Dictionary=Catalog.crop_cells()[0].merged({"stage":3,"condition":"healthy","destroyed":false,"bent":false},true)
	var source_copy:String=JSON.stringify(cell)
	var healthy:Array=Art.crop_runs(cell,Sprites.frame_info,true)
	expect(not healthy.is_empty(),"healthy mature crop draws source foliage")
	var previous:=0
	for stage in range(4):
		var rows:Array=Art.crop_runs(cell.merged({"stage":stage},true),Sprites.frame_info,true)
		expect(rows.size()>=previous and (rows.is_empty()==(stage==0)),"monotonic native source growth "+str(stage))
		previous=rows.size()
	var bent:Array=Art.crop_runs(cell.merged({"bent":true,"condition":"bent"},true),Sprites.frame_info,true)
	expect(bent.size()==healthy.size() and bent!=healthy,"damage changes native pixel placement and foliage tint")
	var rooted:=true
	for i in healthy.size():
		if healthy[i].source.position.y>=Art.crop_spec(cell,true).source.end.y-2:rooted=rooted and healthy[i].rect==bent[i].rect
	expect(rooted,"bending keeps source root rows fixed")
	expect(Art.crop_runs(cell.merged({"destroyed":true},true),Sprites.frame_info,true).is_empty(),"destroyed plant has no visible vegetation")
	expect(not Art.crop_runs(cell.merged({"destroyed":true,"condition":"regrowing","stage":1},true),Sprites.frame_info,true).is_empty(),"regrowing damaged cell shows its new young sprout")
	expect(JSON.stringify(cell)==source_copy,"draw specifications never mutate persisted cells")
	var image_count:int=Crops._images.size()
	var run_count:int=Crops._runs.size()
	for i in 120:Art.crop_runs(cell,Sprites.frame_info,true)
	expect(image_count==Crops._images.size() and run_count==Crops._runs.size(),"rendered frames reuse foliage masks and CPU images")
	var snapshot:Dictionary={"environment":{"minute":720,"cropcells":[cell],"treeplants":[],"fruit":[],"households":{"player":{"curtains":{"window":true},"watered":{}}}}}
	var source_layout:String=JSON.stringify(Layout.props(cell.room))
	var objects:Array=Sprites.scenery_objects(cell.room,snapshot)
	var plants:Array=objects.filter(func(o:Dictionary):return o.get("environment_kind","")=="crop")
	var plots:Array=objects.filter(func(o:Dictionary):return o.get("environment_kind","")=="plot")
	expect(plants.size()==1 and float(plants[0].y)==cell.at.y,"individual plant uses root depth for actor overlap")
	expect(not plots.is_empty() and plants[0].rect.position==cell.rect.position+Vector2(4,4),"original farm target retained and crop source alignment unchanged")
	expect(JSON.stringify(Layout.props(cell.room))==source_layout,"immutable layout stays independent of environmental save")
	var windows:Array=Sprites.scenery_objects("player",snapshot).filter(func(o:Dictionary):return o.get("curtains_closed",false))
	expect(not windows.is_empty() and windows[0].id=="window_closed","closed window replaces the complete original view")
	expect(not Art.curtains_closed("player",{}) and Art.curtains_closed("player",snapshot),"absence of snapshot keeps legacy windows open")
	expect(not Art.curtains_closed("player",snapshot,"window_work"),"curtains are independent per window")
	var plant:Dictionary={"key":"test_plant","id":"plant","rect":Rect2(200,150,18,24),"y":174}
	snapshot.environment.households.player.watered.test_plant=716
	var watered:Array=Art.objects("player",[plant],snapshot)
	expect(watered[0].get("environment_kind","")=="watered" and watered[0].water_freshness>0.0,"watering has visible brief local feedback")
	snapshot.environment.minute=727
	expect(not Art.objects("player",[plant],snapshot)[0].get("environment_object",false),"water feedback expires without changing the plant asset")
	var trees:Array=[]
	for stage in 6:
		trees.append({"id":"stage"+str(stage),"room":"forest","at":Vector2(44+stage*69,146),"stage":stage})
	snapshot.environment.treeplants=trees
	var tree_objects:Array=Sprites.scenery_objects("forest",snapshot).filter(func(o:Dictionary):return o.get("environment_kind","")=="tree")
	for i in 6:
		expect(tree_objects[i].rect.size==Art.TREE_SIZES[i] and tree_objects[i].rect.end.y==146,"tree stage native size and fixed root "+str(i))
		if i>=2:expect(Sprites.frame_info(tree_objects[i].id).source.size==tree_objects[i].rect.size,"no runtime tree scaling "+str(i))
	snapshot.environment.fruit=[{"id":"fruit0","tree_id":"tree0","kind":"golden","room":"forest","at":Vector2(400,236)}]
	var fruit:Array=Sprites.scenery_objects("forest",snapshot).filter(func(o:Dictionary):return o.has("environment_fruit"))
	expect(fruit.size()==1 and fruit[0].environment_fruit=="tree0" and fruit[0].fruit_kind=="golden" and fruit[0].rect.size==Vector2(8,9),"fruit interaction metadata and native apple size")
	if "--capture" in OS.get_cmdline_user_args():await capture(snapshot)
	print("Environment art %d/%d"%[checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
func capture(snapshot:Dictionary):
	root.size=Vector2i(936,488)
	var viewport:=SubViewport.new();viewport.size=Vector2i(936,488);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view:=View.new();view.sample=snapshot;view.scale=Vector2(2,2);view.position=Vector2(-24,-96);viewport.add_child(view)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:Image=viewport.get_texture().get_image()
	var path:=ProjectSettings.globalize_path("res://../artifacts/environment-growth/render.png")
	expect(image.save_png(path)==OK,"actual Godot stage/crop/window render exported")
	view.queue_free();await process_frame
	var garden:=GardenView.new()
	garden.sample={"environment":{"minute":720,"cropcells":[],"treeplants":[],"fruit":[],"households":{}}}
	for cell:Dictionary in Catalog.crop_cells():garden.sample.environment.cropcells.append(cell.merged({"stage":3,"condition":"healthy","destroyed":false,"bent":false},true))
	garden.scale=Vector2(2,2);garden.position=Vector2(-24,-96);viewport.add_child(garden)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	expect(viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/environment-growth/garden-walking.png"))==OK,"garden actor depth render exported")
	viewport.queue_free();await process_frame
