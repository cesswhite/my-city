extends SceneTree
## Canonical outdoor graph, native artwork, exact routes and usable seats.
## Optional --capture exports real rendered views; never reads saves or providers.
const Layout = preload("res://scripts/world_layout.gd")
const Sprites = preload("res://scripts/sprite_art.gd")
const Art = preload("res://scripts/pixel_art.gd")
const Nav = preload("res://scripts/navigation.gd")
const Lighting = preload("res://scripts/world_lighting.gd")
const Seats = preload("res://scripts/seating.gd")
const Ambient = preload("res://scripts/ambient_environment.gd")
const FontAsset = preload("res://assets/fonts/PixelifySans.ttf")
var checks := 0
var failures: Array[String] = []
class View extends Node2D:
	var room := "street"
	var minute := 720.0
	var portal := false
	func _draw() -> void:
		Sprites.draw_world(self, FontAsset, false, room)
		var objects := Sprites.scenery_objects(room)
		for object in objects: object.actor = false
		for id in ["cesar","lupita","mateo","ines","alma","player"]:
			var spawn := Layout.resident_spawn(id)
			if portal and id == "player": spawn = {"room":"street","position":Vector2(44,192)}
			if spawn.room == room:
				objects.append({"actor":true,"position":spawn.position,"y":spawn.position.y,"shirt":["cesar","lupita","mateo","ines","alma","player"].find(id)})
		objects.sort_custom(func(a,b):return float(a.y)<float(b.y))
		for object in objects:
			if object.actor: Sprites.draw_person(self,object.position,{"shirt":object.shirt})
			else:
				Sprites.draw_object(self, object, FontAsset)
				Lighting.draw_object_lights(self, object, room, minute)

func _initialize(): call_deferred("run")
func expect(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func run():
	var font: FontFile = FontAsset
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.oversampling = 1.0
	for room in Layout.outdoor_ids():
		expect(Layout.is_outdoor(room),"outdoor "+room)
		var edges := Layout.exits(room)
		var origin: Vector2 = edges[0].at
		for edge in edges:
			expect(Nav.is_walkable(edge.at,room),"exit walkable "+edge.id)
			expect(Nav.is_walkable(edge.spawn,edge.to),"spawn walkable "+edge.id)
			var reciprocal := Layout.next_exit(edge.to,room)
			expect(not reciprocal.is_empty() and reciprocal.to==room and reciprocal.direction==-edge.direction,"reciprocal "+edge.id)
			if not reciprocal.is_empty():
				expect((edge.at.y==reciprocal.at.y and edge.spawn.y==reciprocal.at.y) if edge.direction.x!=0 else (edge.at.x==reciprocal.at.x and edge.spawn.x==reciprocal.at.x),"matching edge axis "+edge.id)
			var path := Nav.route(origin,edge.at,room)
			expect(not path.is_empty() and path.back().distance_to(edge.at)<0.01,"exact edge route "+edge.id)
		for home in Layout.data().doors:
			if Layout.home_area(home)!=room:continue
			var path := Nav.route(origin,Layout.door_positions()[home],room)
			expect(not path.is_empty() and path.back().distance_to(Layout.door_positions()[home])<0.01,"home route "+home)
		for item in Art.street_items(room):
			expect(Nav.is_walkable(item.stand_at,room),"lore stand "+room+":"+str(item.id))
			var path := Nav.route(origin,item.stand_at,room)
			expect(not path.is_empty() and path.back().distance_to(item.stand_at)<0.01,"lore route "+room+":"+str(item.id))
		for seat in Seats.seats(room):
			expect(Nav.is_walkable(seat.stand_at,room),"seat stand "+seat.id)
			var seat_path := Nav.route(origin,seat.stand_at,room)
			expect(not seat_path.is_empty() and seat_path.back().distance_to(seat.stand_at)<0.01,"seat route "+seat.id)
		for object in Sprites.scenery_objects(room):
			if object.get("tile",false) or object.get("crop_row",false):continue
			var frame := Sprites.object_frame(object)
			expect(not frame.is_empty() and frame.source.size==object.rect.size,"native sprite "+room+":"+str(object.key))
		var ambient := Ambient.new()
		ambient.advance(0.1,1320,room,false)
		expect(ambient.foreground_specs(room).size()<=Ambient.MAX_FOREGROUND,"bounded fx "+room)
		expect(Lighting.ambient_for(1320,room)==Lighting.ambient_for(1320,"street"),"outdoor night "+room)
		for emitter in Lighting.emitters(room):
			expect(emitter.kind in ["lamp","window"],"outdoor emitter "+room)
	for id in ["cesar","lupita","mateo","ines","alma","player"]:
		var spawn := Layout.resident_spawn(id)
		expect(Nav.is_walkable(spawn.position,spawn.room),"resident spawn "+id)
	if "--capture" in OS.get_cmdline_user_args():
		for room in Layout.outdoor_ids():
			var viewport := SubViewport.new()
			viewport.size = Vector2i(936,488)
			viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var surface := View.new()
			surface.room=room
			surface.portal = "--portal" in OS.get_cmdline_user_args()
			surface.scale=Vector2(2,2)
			surface.position=Vector2(-24,-96)
			viewport.add_child(surface)
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = ProjectSettings.globalize_path("res://../artifacts/neighborhood/"+room+("-portal" if surface.portal else "")+".png")
			viewport.get_texture().get_image().save_png(path)
			viewport.queue_free()
			await process_frame
	print("Neighborhood art %d/%d" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
