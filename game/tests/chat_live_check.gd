extends SceneTree
## Opt-in live service check. Explicit flag, synthetic residents, no player save read/write.
var scene: Node
var checks: int = 0
var failures: Array[String] = []
var report: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	if "--live-chat" not in OS.get_cmdline_user_args() or "--ui-test" not in OS.get_cmdline_user_args():
		push_error("Explicit --live-chat --ui-test required. No provider call or save access was made.")
		quit(1)
		return
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.save_allowed = false
	if scene.service_token.is_empty():
		push_error("Configure the local service client token before this opt-in live check.")
		scene.free()
		quit(1)
		return
	var player: Dictionary = scene.colony.get_resident("player")
	var neighbor: Dictionary = scene.colony.get_resident("lupita")
	player.room = "street"
	neighbor.room = "street"
	player.pos = [280.0, 200.0]
	neighbor.pos = [296.0, 200.0]
	player.target = player.pos.duplicate()
	neighbor.target = scene.colony.PLACES.huerto.duplicate()
	scene.selected_id = "lupita"
	scene.page = "hablar"
	scene.build_inspector()
	var messages: Array[String] = ["Hola, Lupita. ¿Cómo estás?", "Bien, gracias. Soy nuevo aquí. ¿Qué te gusta hacer en la colonia?", "¿Cómo podría participar en eso?"]
	for index in range(messages.size()):
		var before: int = player.memories.size()
		scene.send_chat_text(messages[index])
		var deadline: int = Time.get_ticks_msec() + 18000
		while scene.chat_busy() and Time.get_ticks_msec() < deadline:
			await process_frame
		expect(not scene.chat_busy(), "Live turn completes before deadline")
		expect(scene.chat_error_for("lupita").is_empty(), "Live service returned a complete response")
		expect(scene.chat_partner_id == "lupita", "Partner stays in this conversation after the reply")
		expect(player.memories.size() == before + 1, "Only a completed exchange adds memory")
		if player.memories.size() != before + 1: break
		var reply: String = scene.player_chat.last_reply("lupita")
		report.append({"turn": index + 1, "utterance": messages[index], "reply": reply, "provider_chars": str(scene.dialogue_request._output).length(), "timing": scene.last_timing, "source": player.memories.back().origin})
		expect(reply.length() <= 180 and reply.split(" ", false).size() <= 30, "Reply stays short")
		expect(not reply.contains("—") and not reply.contains("\n") and not reply.contains("  "), "Reply stays in one compact paragraph")
		expect(scene.chat_transcript_for("lupita").contains(messages[0]), "First greeting survives subsequent turns")
		expect(scene.chat_transcript_for("mateo").is_empty(), "Another neighbor has no copy of this conversation")
	await process_frame
	if "--capture-chat" in OS.get_cmdline_user_args():
		scene.queue_redraw()
		scene.actors.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = OS.get_environment("MY_CITY_CHAT_CAPTURE")
		if not path.is_empty(): expect(root.get_texture().get_image().save_png(path) == OK, "Live chat capture saved")
	var report_path: String = OS.get_environment("MY_CITY_CHAT_REPORT")
	if not report_path.is_empty():
		var file = FileAccess.open(report_path, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify({"checks": checks, "failures": failures, "turns": report}, "\t"))
	scene.end_player_conversation()
	scene.free()
	print("LIVE CHAT: %d/%d checks; %d provider replies; synthetic fixture, no save writes." % [checks - failures.size(), checks, report.size()])
	quit(0 if failures.is_empty() and report.size() == 3 else 1)
