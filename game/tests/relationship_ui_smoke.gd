extends SceneTree
## Directional relationship UI and profile privacy, in a fresh provider-free scene.
const PanelUI = preload("res://scripts/relationship_ui.gd")
const ResidentUI = preload("res://scripts/resident_ui.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func expect(value: bool, description: String) -> void:
	checks += 1
	if value: print("PASS: " + description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)

func settle() -> void:
	for _frame in range(4): await process_frame

func text_in(node: Node) -> String:
	var result := ""
	if node is Label or node is Button: result += str(node.text) + "\n"
	if node is Control: result += str(node.tooltip_text) + "\n"
	for child in node.get_children(): result += text_in(child)
	return result

func memory(id: String, participants: Array, content: String) -> Dictionary:
	return {"id":id,"participants":participants,"kind":"conversacion","content":content,"origin":"Fixture local","time":"día 1 a las 08:00","minute":480,"day":1}

func run() -> void:
	if "--ui-test" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(768,432)
	var scene = preload("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	scene.use_jev = false
	scene.service_token = ""
	scene.service_url = ""
	scene.paused = true
	scene.open_inspector("cesar","historia")
	await settle()
	var world = scene.colony
	var npc: Dictionary = world.get_resident("cesar")
	var original_biography: String = npc.biography
	var initial: Dictionary = world.relationship_for("cesar","player")
	var block: VBoxContainer = scene.inspector.find_child("RelationshipToPlayer",true,false)
	expect(is_instance_valid(block),"NPC history has one clearly directional relationship block")
	if is_instance_valid(block):
		expect(block.size.y <= 118.1 and block.size.x <= 224.1,"all four native-size metrics fit a compact block inside the story scroll")
		var correct := true
		for spec: Array in PanelUI.METRICS:
			var row: HBoxContainer = block.get_node(str(spec[0]))
			var bar: ProgressBar = row.get_node("ValueBar")
			var value: Label = row.get_node("Value")
			correct = correct and bar.value == roundf(float(initial[spec[0]])) and value.text == str(roundi(float(initial[spec[0]]))) and bar.size.y <= 4.1
		expect(correct,"bars and numbers show the selected neighbor's actual values toward the player")
		expect(text_in(block).contains("Su relación contigo") and not text_in(block).to_lower().contains("enamor"),"affection is presented without inventing a romantic relationship")
		var probe := {"trust":92,"affection":17,"tolerance":-3,"frustration":140,"mood":"guarded"}
		PanelUI.update(block,probe)
		expect((block.get_node("trust/Value") as Label).text == "92" and (block.get_node("affection/Value") as Label).text == "17" and (block.get_node("tolerance/ValueBar") as ProgressBar).value == 0 and (block.get_node("frustration/ValueBar") as ProgressBar).value == 100,"metric refresh changes values in place and bounds all meters to 0–100")
		expect((block.get_node("Mood") as Label).text == "Ánimo: Con cautela","mood uses a short human-readable Spanish label")
		PanelUI.update(block,initial)
	var public_text: String = text_in(scene.inspector)
	expect(initial.disclosure == "public" and not public_text.contains(original_biography),"first inspection does not reveal the neighbor's full family biography")
	expect(not public_text.contains(str(npc.goal)),"a private personal goal is absent from the public profile")
	var profile: Dictionary = world.visible_profile_for("cesar","player")
	expect(public_text.contains(str(profile.biography)),"story displays the core's permitted biography instead of duplicating disclosure rules")
	var relationship_before: Dictionary = npc.relationships.player.duplicate(true)
	npc.relationships.player.trust = 48.0
	world.get_resident("player").relationships.cesar.trust = 3.0
	scene.refresh_status()
	await settle()
	var personal_text: String = text_in(scene.inspector)
	expect(personal_text.contains(str(world.visible_profile_for("cesar","player").biography)) and personal_text.contains(str(npc.goal)) and not personal_text.contains(original_biography),"an open profile reveals the permitted personal tier when actual trust changes")
	block = scene.inspector.find_child("RelationshipToPlayer",true,false)
	expect((block.get_node("trust/Value") as Label).text == "48","directional metrics never substitute the player's reverse relationship")
	npc.relationships.player.trust = 80.0
	npc.relationships.player.affection = 70.0
	scene.refresh_status()
	await settle()
	expect(text_in(scene.inspector).contains(original_biography),"the intimate tier permits the full biography when the core allows it")
	npc.relationships.player.trust = 18.0
	npc.relationships.player.frustration = 70.0
	scene.refresh_status()
	await settle()
	expect(not text_in(scene.inspector).contains(original_biography) and not text_in(scene.inspector).contains(str(npc.goal)),"losing disclosure permission removes private text from an already open profile")
	var npc_snapshot: Dictionary = npc.duplicate(true)
	npc.memories.append(memory("private_other",["cesar","mateo"],"PRIVATE_OTHER_CONVERSATION"))
	npc.memories.append(memory("private_self",["cesar"],"PRIVATE_SOLO_MEMORY"))
	npc.memories.append(memory("wrong_owner",["player","alma"],"PRIVATE_WRONG_OWNER"))
	npc.known_people["PRIVATE_KNOWN_PERSON"] = {}
	npc.skills["private_test"] = {"name":"PRIVATE_SKILL","status":"demostrada","source":"PRIVATE_LEARNING_SOURCE"}
	for index in range(24):
		npc.memories.append(memory("shared_%d" % index,["cesar","player"],"SHARED_%02d: Conversaron sobre un paseo por la colonia y recordaron el café." % index))
	scene.open_inspector("cesar","recuerdos")
	await settle()
	var shared_text: String = text_in(scene.inspector)
	expect(not shared_text.contains("PRIVATE_"),"NPC memory hides third-party conversations, solo experiences, social graph and private skills")
	expect(shared_text.contains("Recuerdos contigo · 24") and shared_text.contains("SHARED_23"),"shared memories remain readable at public trust")
	expect(ResidentUI.visible_memories(npc).size() == 24,"only memories naming both the selected owner and player pass the filter")
	var scroll: ScrollContainer = scene.inspector.find_children("*","ScrollContainer",true,false)[0]
	expect(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,"long shared recollections scroll vertically inside the existing inspector")
	var private_count: int = npc.memories.size()
	scene.open_inspector("cesar","historia")
	await settle()
	expect(npc.memories.size() == private_count and npc.biography == npc_snapshot.biography,"reading restricted panels never erases or rewrites the NPC's private state")
	var player: Dictionary = world.get_resident("player")
	npc.relationships.player = relationship_before
	player.room = npc.room
	player.pos = [float(npc.pos[0]) + 16.0,float(npc.pos[1])]
	player.target = player.pos.duplicate()
	var presenter = ResidentUI.new(scene)
	expect(presenter._chat_can_send("cesar"),"a nearby open conversation allows normal sending")
	expect(scene.start_player_conversation("cesar"),"the closed-conversation fixture begins a real nearby session")
	scene.player_chat._end_from_neighbor("cesar","Necesito seguir con mis cosas. Nos vemos.",true)
	expect(not presenter._chat_can_send("cesar"),"a finished conversation rejects sending even when the partner stays nearby")
	scene.player_chat._ended_id = ""
	scene.player_chat._farewell.clear()
	player.biography = "PLAYER_COMPLETE_BIOGRAPHY"
	player.goal = "PLAYER_COMPLETE_GOAL"
	player.personality = ["PLAYER_COMPLETE_PERSONALITY"]
	player.memories.append(memory("own_memory",["player"],"PLAYER_COMPLETE_MEMORY"))
	player.skills["own_skill"] = {"name":"PLAYER_COMPLETE_SKILL","status":"demostrada","source":"PLAYER_COMPLETE_SOURCE"}
	scene.open_inspector("player","historia")
	await settle()
	var own_text: String = text_in(scene.inspector)
	expect(own_text.contains("PLAYER_COMPLETE_BIOGRAPHY") and own_text.contains("PLAYER_COMPLETE_GOAL") and own_text.contains("PLAYER_COMPLETE_PERSONALITY"),"the player retains their complete biography, personality and goals")
	expect(scene.inspector.find_child("RelationshipToPlayer",true,false) == null,"the player does not get a misleading relationship meter toward themselves")
	scene.open_inspector("player","recuerdos")
	await settle()
	own_text = text_in(scene.inspector)
	expect(own_text.contains("PLAYER_COMPLETE_MEMORY") and own_text.contains("PLAYER_COMPLETE_SKILL") and own_text.contains("PLAYER_COMPLETE_SOURCE"),"the player's own memories and learning provenance remain complete")
	expect(scene.dialogue_job.is_empty() and not scene.decision_pending and not scene.save_allowed,"inspecting relationships never requests AI or saves the fixture")
	if "--capture-relationship" in OS.get_cmdline_user_args():
		scene.open_inspector("cesar","historia")
		scene.overlay.dismiss_toast()
		scene.actors.queue_redraw()
		await settle()
		await RenderingServer.frame_post_draw
		var output := ProjectSettings.globalize_path("res://../artifacts/relationships/profile-public.png")
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		expect(root.get_texture().get_image().save_png(output) == OK,"public relationship profile capture is saved")
	scene.free()
	print("RELATIONSHIP UI: %d/%d checks passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
