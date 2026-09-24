extends SceneTree
## Rendering adapters never mutate a save or the shared navigation plan.
const Layout = preload("res://scripts/world_layout.gd")
const Catalog = preload("res://scripts/settlement_catalog.gd")
const World = preload("res://scripts/settlement_world.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Interactions = preload("res://scripts/world_interactions.gd")
const Nav = preload("res://scripts/navigation.gd")
const Lighting = preload("res://scripts/world_lighting.gd")
const Ambient = preload("res://scripts/ambient_environment.gd")
const FontAsset = preload("res://assets/fonts/PixelifySans.ttf")
var checks := 0
var failures: Array[String] = []
var route_samples := 0
class View extends Node2D:
	var room := "street"
	var state: Dictionary = {}
	func _draw() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		Sprites.draw_world(self,FontAsset,false,room,state)
		var objects := Sprites.scenery_objects(room,state)
		objects.append({"actor":true,"position":Vector2(280,200),"y":200})
		objects.sort_custom(func(a,b):return float(a.y)<float(b.y))
		for object in objects:
			if object.get("actor",false): Sprites.draw_person(self,object.position,{"shirt":2,"hat":1})
			else: Sprites.draw_object(self,object,FontAsset)
func _initialize(): call_deferred("run")
func expect(ok: bool,message: String):
	checks += 1
	if not ok: failures.append(message);push_error(message)
func initial() -> Dictionary:
	var catalog := Catalog.data()
	return {"settlement":{"areas":catalog.initial.areas.duplicate(),"buildings":catalog.initial.buildings.duplicate(),"projects":{},"nodes":{},"plots":{},"discoveries":[],"minute":720}}
func developed() -> Dictionary:
	var state := initial()
	state.settlement.areas = Layout.outdoor_ids()
	for project: Dictionary in Catalog.data().projects.values():
		if not str(project.get("building","")).is_empty() and project.building not in state.settlement.buildings: state.settlement.buildings.append(project.building)
	return state
func object_key(room: String,key: String,state: Dictionary) -> Dictionary:
	for item in Sprites.scenery_objects(room,state):
		if item.key == key: return item
	return {}
func check_route(room: String,at: Vector2,label: String):
	expect(Nav.is_walkable(at,room),label+" walkable")
	var origin: Vector2 = Layout.exits(room)[0].at
	var route := Nav.route(origin,at,room)
	expect(not route.is_empty() and route.back().distance_to(at)<0.01,label+" exact route")
	var safe := true
	var previous := origin
	for next: Vector2 in route:
		for i in range(ceili(previous.distance_to(next))+1):
			var point: Vector2 = previous.move_toward(next,float(i))
			route_samples += 1
			safe = safe and Nav.is_walkable(point,room)
		previous = next
	expect(safe,label+" no solid crossing")
func run():
	var font: FontFile = FontAsset
	font.antialiasing=TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning=TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.oversampling=1.0
	var start := initial()
	var full := developed()
	var before: String = JSON.stringify(start)
	var catalog: Dictionary = Catalog.data()
	expect(Layout.outdoor_ids().size()==6 and Layout.area_grid("forest")==Vector2i(-2,0),"six connected areas with forest west")
	for room in Layout.outdoor_ids():
		var static_before: String = str(Layout.props(room))
		for edge in Layout.exits(room):
			check_route(room,edge.at,"edge "+str(edge.id))
			expect(Nav.is_walkable(edge.spawn,edge.to),"safe reciprocal spawn "+str(edge.id))
			var picked := Interactions.pick(edge.at,room,start)
			expect(picked.get("kind","")==("area" if World.area_open(edge.to,start) else "settlement"),"all edges gated "+str(edge.id))
			var completed_pick := Interactions.pick(edge.at,room,full)
			expect(completed_pick.get("kind","")=="area","completed edge "+str(edge.id))
		Sprites.scenery_objects(room,start)
		Sprites.scenery_objects(room,full)
		expect(str(Layout.props(room))==static_before,"immutable plan "+room)
		var closed_emitters := Lighting.emitters(room,start)
		Lighting.emitters(room,full)
		expect(Lighting.emitters(room,start)==closed_emitters,"light cache independent "+room)
		for light in closed_emitters: expect(World.building_ready(light.get("building",""),start),"no ghost window "+room)
	for group in ["projects","nodes","recipes","plots","explorations"]:
		for id in catalog[group]:
			var spec: Dictionary = catalog[group][id]
			check_route(str(spec.area),Layout.point(spec.at),group+":"+str(id))
	check_route(catalog.board.area,Layout.point(catalog.board.at),"community board")
	for home in ["cesar","mateo","alma"]:
		var room := Layout.home_area(home)
		var key: String = catalog.geometry.home_props[home]
		var raw := object_key(room,key,start)
		expect(raw.get("construction_stage","")=="foundation" and raw.id=="tile_soil","unbuilt foundation "+home)
		var scaffold := start.duplicate(true)
		scaffold.settlement.projects[catalog.home_buildings[home]]={"status":"building","progress":1}
		expect(object_key(room,key,scaffold).get("construction_stage","")=="scaffold","scaffold "+home)
		expect(not object_key(room,key,full).has("construction_stage"),"completed facade "+home)
		var targets := Interactions._targets(room,start)
		expect(not targets.any(func(t):return t.get("home_id","")==home),"no phantom door "+home)
		var built_targets := Interactions._targets(room,full)
		expect(built_targets.any(func(t):return t.get("home_id","")==home),"restored door "+home)
		var ambient := Ambient.new()
		ambient.advance(1.0,1200,room,false,start)
		expect(not ambient.foreground_specs(room).any(func(t):return t.kind=="smoke"),"no phantom smoke "+home)
	for node_id in catalog.nodes:
		var spec: Dictionary = catalog.nodes[node_id]
		var node_state := full.duplicate(true)
		node_state.settlement.nodes[node_id]={"period":0,"remaining":0}
		expect(World.remaining(node_id,node_state)==0,"depleted stock "+node_id)
		node_state.settlement.minute=int(spec.period)
		expect(World.remaining(node_id,node_state)==int(spec.stock),"renewed stock "+node_id)
		var node_targets := Interactions._targets(spec.area,full)
		var matches := node_targets.filter(func(t):return t.get("task_id","")=="gather:"+node_id)
		expect(matches.size()==1,"single resource target "+node_id)
		if not matches.is_empty():
			var target: Dictionary = matches[0]
			var pick := Interactions.pick(target.rect.get_center(),spec.area,full)
			expect(pick.get("task_id","")=="gather:"+node_id,"resource visible click "+node_id)
	for plot_id in catalog.plots:
		expect(World.plot_stage(plot_id,start)=="unprepared","garden not ready "+plot_id)
		expect(World.plot_stage(plot_id,full)=="empty","ready bed empty "+plot_id)
		var planted := full.duplicate(true)
		planted.settlement.plots[plot_id]={"status":"growing","planted_at":720,"tended":false}
		expect(World.plot_stage(plot_id,planted)=="seeded","small seedlings "+plot_id)
		planted.settlement.minute=900
		expect(World.plot_stage(plot_id,planted)=="growing","no harvest without tending "+plot_id)
		planted.settlement.plots[plot_id].tended=true
		expect(World.plot_stage(plot_id,planted)=="ready","mature after real time and tending "+plot_id)
		var mature_targets := Interactions._targets("gardens",planted)
		expect(mature_targets.any(func(t):return t.get("task_id","")=="harvest:"+plot_id),"mature harvest target "+plot_id)
	expect(JSON.stringify(start)==before,"input state untouched across all adapters")
	if "--capture" in OS.get_cmdline_user_args():
		var scaffold := full.duplicate(true)
		scaffold.settlement.buildings.erase("mateo_home")
		scaffold.settlement.projects.mateo_home={"status":"building","progress":12}
		var garden := full.duplicate(true)
		garden.settlement.plots={"north_bed":{"status":"growing","planted_at":720,"tended":false},"south_bed":{"status":"growing","planted_at":540,"tended":true}}
		for shot in [["initial-street","street",start],["initial-homes","homes",start],["foundation-gardens","gardens",start],["scaffold-workshops","workshops",scaffold],["growing-garden","gardens",garden],["forest","forest",full]]:
			await capture(shot[0],shot[1],shot[2])
	print("Settlement world %d/%d; %d safe route samples" % [checks-failures.size(),checks,route_samples])
	quit(0 if failures.is_empty() else 1)
func capture(title: String,room: String,state: Dictionary):
	var viewport := SubViewport.new()
	viewport.size=Vector2i(936,488)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := View.new()
	view.room=room;view.state=state;view.scale=Vector2(2,2);view.position=Vector2(-24,-96)
	viewport.add_child(view)
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../artifacts/settlement-world")
	DirAccess.make_dir_recursive_absolute(directory)
	viewport.get_texture().get_image().save_png(directory+"/"+title+".png")
	viewport.queue_free()
	await process_frame
