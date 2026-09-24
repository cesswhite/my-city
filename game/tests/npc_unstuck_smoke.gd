extends SceneTree
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Crowd = preload("res://scripts/crowd_motion.gd")
const STEP := 0.05
class MainProbe:
	extends "res://scripts/main.gd"
	var provider_calls := 0
	func decide_with_jev() -> void: provider_calls += 1
	func request_dialogue(_a: String,_b: String,_text: String) -> void: provider_calls += 1
var checks := 0
var failures := 0
func _init(): call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("FAIL: "+label)
	else: print("PASS: "+label)
func put(scene,id: String, at: Vector2, goal: Vector2, room: String = "street") -> void:
	var p: Dictionary = scene.colony.get_resident(id)
	p.room = room; p.pos = [at.x,at.y]; p.target = [goal.x,goal.y]; p.travel_intent = ""
	p.erase("travel_route")
func reset(scene) -> void:
	scene.paths.clear(); scene.colony.conversation_holds.clear()
	scene.crowd = Crowd.new(scene)
	for p: Dictionary in scene.colony.residents: put(scene,p.id,Layout.point(Layout.data().home_rest),Layout.point(Layout.data().home_rest),p.id)
func simulate(scene, ids: Array[String], seconds: float = 20.0, trace: bool = false) -> Dictionary:
	var result := {"arrived":false,"walkable":true,"speed":true,"gap":INF,"stalled":0.0,"max_stall":0.0,"elapsed":0.0,"distance":0.0}
	var goals := {}
	for id in ids: goals[id] = Layout.point(scene.colony.get_resident(id).target)
	for frame in range(int(seconds/STEP)):
		result.elapsed = (frame+1)*STEP
		var moved := 0.0
		for id in ids:
			var p: Dictionary = scene.colony.get_resident(id)
			var old: Vector2 = scene.position_of(p)
			var old_route: String = str(scene.paths.get(id,{}).get("points",[])) if trace else ""
			scene.move_resident(p,STEP)
			if trace and old_route != str(scene.paths.get(id,{}).get("points",[])):
				print("REPLAN ",result.elapsed," ",id," ",scene.paths.get(id,{}).get("points",[]))
			var at: Vector2 = scene.position_of(p)
			moved += at.distance_to(old)
			result.speed = result.speed and old.distance_to(at) <= 1.501
			result.walkable = result.walkable and Navigation.is_walkable(at,p.room)
			for other: Dictionary in scene.colony.residents:
				if p.id != other.id and p.room == other.room:
					result.gap = minf(result.gap,((at-scene.position_of(other))/Vector2(16,14)).length())
		result.stalled = float(result.stalled)+STEP if moved < 0.001 else 0.0
		result.distance += moved
		result.max_stall = maxf(result.max_stall,result.stalled)
		if trace and frame % 10 == 0:
			var states := []
			for id in ids:
				var state: Dictionary = scene.paths.get(id,{})
				var points: Array = state.get("points",[])
				var index: int = state.get("index",-1)
				states.append({"id":id,"pos":scene.colony.get_resident(id).pos,"target":goals[id],"index":index,"next":points[index] if index>=0 and index<points.size() else Vector2.ZERO,"key":state.get("key",""),"blocked":state.get("blocked",false),"detour":state.get("detour",false)})
			print("TRACE ",result.elapsed," ",states)
		var all_arrived := true
		for id in ids:
			var p: Dictionary = scene.colony.get_resident(id)
			all_arrived = all_arrived and scene.position_of(p).distance_to(goals[id]) < 0.01
		if all_arrived: result.arrived = true; break
	return result
func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args(): quit(1); return
	root.size = Vector2i(768,432)
	var scene := MainProbe.new()
	scene.start_new_game = true
	scene.colony.save_path = "user://test_npc_unstuck_%d.json" % OS.get_process_id()
	root.add_child(scene); scene.set_process(false); scene.save_allowed=false; scene.use_jev=false; scene.service_url=""; scene.service_token=""; scene.paused=false
	# Captured before the fix in artifacts/npc-unstuck/route-probe.log. The
	# off-grid connector to (236,164) used to cut the stationary person's body.
	for reverse in [false, true]:
		reset(scene)
		var close_point := Vector2(239.53665,160.89287)
		var open_point := Vector2(304,190)
		var goal: Vector2 = close_point if reverse else open_point
		put(scene,"cesar",open_point if reverse else close_point,goal,Layout.home_area("alma"))
		var blocker := Vector2(249,172.3)
		put(scene,"lupita",blocker,blocker,Layout.home_area("alma"))
		scene.colony.conversation_holds.append("lupita")
		var result: Dictionary = simulate(scene,["cesar"])
		if not result.arrived: print("REPRO fractional reverse=",reverse," metrics=",result," pos=",scene.colony.get_resident("cesar").pos," path=",scene.paths.get("cesar",{}))
		check(result.arrived,"fractional %s connector reaches the original goal" % ("final" if reverse else "initial"))
		check(result.walkable and result.speed and result.gap >= 0.9998,"fractional connector sweeps remain outside walls and bodies")
		check(Layout.point(scene.colony.get_resident("cesar").target) == goal and scene.position_of(scene.colony.get_resident("lupita")) == blocker,"rerouting preserves intended goal and held interlocutor")
	for door_x in [142.0,195.0]:
		var door_room: String = Layout.home_area("cesar" if door_x == 142.0 else "lupita")
		for offset in [Vector2(-20,0),Vector2(-16,0),Vector2(-12,12),Vector2(-8,16),Vector2(0,16),Vector2(8,16),Vector2(12,12),Vector2(16,0),Vector2(20,0),Vector2(0,24)]:
			var start := Vector2(door_x,160)
			var obstacle: Vector2 = start+offset
			if not Navigation.is_walkable(obstacle, door_room): continue
			reset(scene)
			put(scene,"cesar",start,Vector2(door_x,256),door_room)
			put(scene,"lupita",obstacle,obstacle,door_room)
			scene.colony.conversation_holds.append("lupita")
			var result: Dictionary = simulate(scene,["cesar"])
			var label := "door%.0f blocker%s" % [door_x,obstacle]
			if not result.arrived:
				print("REPRO ",label," pos=",scene.colony.get_resident("cesar").pos," target=",scene.colony.get_resident("cesar").target," metrics=",result," path=",scene.paths.get("cesar",{}))
			check(result.arrived,label+" arrives around held neighbor")
			check(result.walkable and result.speed and result.gap >= 0.9998 and scene.position_of(scene.colony.get_resident("lupita")) == obstacle,label+" preserves terrain, speed, spacing and held position")
	reset(scene)
	put(scene,"cesar",Vector2(142,160),Vector2(195,160)); put(scene,"lupita",Vector2(195,160),Vector2(142,160))
	var head_on: Dictionary = simulate(scene,["cesar","lupita"],20.0,true)
	print("HEAD_ON_METRICS ",head_on)
	if not head_on.arrived: print("REPRO head_on",head_on," ",scene.colony.get_resident("cesar").pos," ",scene.colony.get_resident("lupita").pos," paths=",scene.paths)
	check(head_on.arrived,"head-on crossing between actual doors arrives")
	check(head_on.arrived and head_on.elapsed <= 12.0,"head-on crossing resolves within twelve seconds")
	check(head_on.distance <= 500.0,"head-on crossing avoids reciprocal loops around the cafe")
	check(head_on.walkable and head_on.speed and head_on.gap >= 0.9998,"head-on crossing never teleports or penetrates bodies")
	# Two actors on opposite sides of the same doorway must give way physically.
	# Neither successful room transfer is a same-room movement/teleport.
	reset(scene)
	var door: Vector2 = Navigation.door_positions().cesar
	var home_area: String = Layout.home_area("cesar")
	put(scene,"cesar",door,door,home_area)
	put(scene,"lupita",Layout.point(Layout.data().exit),Layout.point(Layout.data().exit),"cesar")
	scene.colony.get_resident("cesar").travel_intent = "casa"
	scene.colony.get_resident("lupita").travel_intent = "cafe"
	var portal_legal := true
	var portal_goal_preserved := true
	var entered := false
	var exited := false
	for frame in range(600):
		for id in ["cesar","lupita"]:
			var person: Dictionary = scene.colony.get_resident(id)
			var old: Vector2 = scene.position_of(person)
			var room: String = person.room
			scene.move_resident(person,STEP)
			var at: Vector2 = scene.position_of(person)
			portal_legal = portal_legal and Navigation.is_walkable(at,person.room)
			if room == person.room: portal_legal = portal_legal and old.distance_to(at) <= 1.501
			for other: Dictionary in scene.colony.residents:
				if other.id != id and other.room == person.room:
					portal_legal = portal_legal and ((at-scene.position_of(other))/Vector2(16,14)).length() >= 0.9998
			if id == "cesar" and person.room == home_area:
				portal_goal_preserved = portal_goal_preserved and Layout.point(person.target) == door and person.travel_intent == "casa"
		entered = entered or scene.colony.get_resident("cesar").room == "cesar"
		exited = exited or scene.colony.get_resident("lupita").room == home_area
		if entered and exited: break
	if not (entered and exited): print("REPRO portal cesar=",scene.colony.get_resident("cesar").pos,"/",scene.colony.get_resident("cesar").room," lupita=",scene.colony.get_resident("lupita").pos,"/",scene.colony.get_resident("lupita").room)
	check(entered and exited,"opposing doorway traffic eventually enters and exits")
	check(portal_legal,"yielding at doorway walks legally without overlap or same-room teleport")
	check(portal_goal_preserved,"temporary doorway yielding preserves original home target and intent")
	# Simultaneous outdoor crossings use distinct arrival space and then continue
	# the original goals, without pushing either actor or restoring the old room.
	# Traversal fixture explicitly includes the new forest. Growth tests unlock it through its real costs.
	if "forest" not in scene.colony.settlement.state.areas:
		scene.colony.settlement.state.areas.append("forest")
		scene.colony.settlement.state.discoveries.append("survey_forest")
		scene.colony.settlement.state.projects.forest_path = {"status":"completed","progress":30.0}
	for area: String in Layout.outdoor_ids():
		for edge: Dictionary in Layout.exits(area):
			reset(scene)
			var reverse: Dictionary = Layout.next_exit(edge.to, area)
			var a_goal: Vector2 = Navigation.recover_position(edge.spawn + edge.direction * 24.0, edge.to)
			var b_goal: Vector2 = Navigation.recover_position(reverse.spawn + reverse.direction * 24.0, area)
			put(scene,"cesar",edge.at,edge.at,area)
			put(scene,"lupita",reverse.at,reverse.at,edge.to)
			var assigned: bool = scene.colony.travel_to("cesar",edge.to,a_goal) and scene.colony.travel_to("lupita",area,b_goal)
			var legal := true
			var complete := false
			for _frame in range(200):
				for id in ["cesar","lupita"]:
					var actor: Dictionary = scene.colony.get_resident(id)
					var before: Vector2 = scene.position_of(actor)
					var before_room: String = actor.room
					scene.move_resident(actor,STEP)
					var after: Vector2 = scene.position_of(actor)
					legal = legal and Navigation.is_walkable(after,actor.room)
					if actor.room == before_room: legal = legal and before.distance_to(after) <= 1.501
					for other: Dictionary in scene.colony.residents:
						if other.id != id and other.room == actor.room:
							legal = legal and ((after-scene.position_of(other))/Vector2(16,14)).length() >= 0.9998
				var a: Dictionary = scene.colony.get_resident("cesar")
				var b: Dictionary = scene.colony.get_resident("lupita")
				complete = a.room == edge.to and b.room == area and scene.position_of(a).distance_to(a_goal) < 0.01 and scene.position_of(b).distance_to(b_goal) < 0.01
				if complete: break
			check(assigned and complete,"opposite neighbors cross and complete original goals " + area + "<->" + str(edge.to))
			check(legal,"outdoor crossing preserves speed, terrain and personal space " + area + "<->" + str(edge.to))
	check(scene.provider_calls==0 and not FileAccess.file_exists(scene.colony.save_path),"no providers or user saves")
	scene.queue_free(); await process_frame
	print("NPC UNSTUCK: %d/%d checks passed" % [checks-failures,checks]); quit(0 if failures==0 else 1)
